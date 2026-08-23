//
//  Level.swift
//  DredfitCore
//
//  The level encoding and everything derived from it: decoding a level into a
//  plan, the landings (unload, eased, rep continuity) and the inversion of a
//  reported fact. Split out of Engine.swift when that file outgrew the lint's
//  ceiling; the code is unchanged.
//

import Foundation

public enum Level {
    public static func decode(_ level: Int) -> LevelDecoded {
        let l = min(max(level, 0), EngineConfig.levelMax)
        let band = l / EngineConfig.stepsPerTier   // 0...5
        let step = l % EngineConfig.stepsPerTier
        let tier = min(EngineConfig.tiers, 1 + band)
        let sets = EngineConfig.setsBase + max(0, band - (EngineConfig.tiers - 1))
        // v2.17 (spec §28.1): inside a sets band the start and the step are
        // the band's own — otherwise entering a band halves the dose.
        let repStart = EngineConfig.repStartBand[sets]
            ?? EngineConfig.repStart[tier] ?? EngineConfig.repMin
        return LevelDecoded(
            tier: tier,
            sets: sets,
            reps: repStart + step,
            // v2.21 (spec §32.2): the static dose is read off the ladder — the
            // increment is relative and does not spell out as start + step.
            hold: ladder(tier: tier, sets: sets)[step]
        )
    }

    /// The ladder a dose belongs to: the set band outranks the tier — exactly
    /// the precedence `holdStartBand ?? holdStart[tier]` used to have.
    static func ladder(tier: Int, sets: Int) -> [Int] {
        EngineConfig.holdLadderBand[sets]
            ?? EngineConfig.holdLadder[tier]
            ?? [EngineConfig.holdMin]
    }

    /// Rounding to nearest with a tie going DOWN, entirely on integers: the
    /// platform's rounding mode has no business inside the engine's encoding.
    static func halfDown(_ delta: Int, step: Int) -> Int {
        let numerator = step - 2 * delta, denominator = 2 * step   // denominator > 0
        // Swift's `/` truncates toward zero; floor division is what the
        // half-down rule needs, and it has to match the reference exactly.
        let floored = numerator >= 0
            ? numerator / denominator
            : -((-numerator + denominator - 1) / denominator)
        return -floored
    }

    /// The ladder rung a reported number sits on: nearest, ties DOWN ("do no
    /// harm"). Walking left to right with a strict comparison is what makes an
    /// exact tie keep the lower rung.
    ///
    /// Past either edge the ladder is continued by its EDGE interval, and the
    /// rung returned goes freely below zero or above seven — cutting the
    /// inversion off at a tier's edge is not an option. Measured while building
    /// the wave: clamping the rung to [0,7] breaks the monotonicity of the
    /// estimate in the reported fact (§25.1, #139) at the top rung of EVERY
    /// tier and EVERY band — plank L7, plan 39 s: a fact of 42 gave level 8 and
    /// an honest 43 gave level 7. Precisely the defect v2.14 was written for.
    /// The edge a result settles on is the edge of the SCALE (0...47) in
    /// `fromActual`, not the edge of a tier; the §15.3/§17.1 caps and the §25.3
    /// gate apply on top, as they always did.
    static func holdRung(_ ladder: [Int], _ actual: Int) -> Int {
        let top = ladder.count - 1
        if actual < ladder[0] { return halfDown(actual - ladder[0], step: ladder[1] - ladder[0]) }
        if actual > ladder[top] {
            return top + halfDown(actual - ladder[top], step: ladder[top] - ladder[top - 1])
        }
        var best = 0
        for i in 1...top where abs(actual - ladder[i]) < abs(actual - ladder[best]) { best = i }
        return best
    }

    /// v2.11 (spec §21.1): where a pain report lands — the bottom of the
    /// previous tier. A change of variation, not fewer reps of the same one:
    /// "take the load off, don't trim it" (§15.2). The set bands are tier 4
    /// by encoding, so they too land at the bottom of tier 3.
    public static func unload(_ level: Int) -> Int {
        let tier = decode(level).tier
        return max(0, (tier - 2) * EngineConfig.stepsPerTier)
    }

    /// v2.19 (spec §30.6): the floor of the CURRENT tier — the first step of
    /// taking the load off. The variation does not change; the dose becomes
    /// the smallest that variation has. The work falls by construction:
    /// `repStart` is the tier's minimum and the mod-8 rung goes to zero.
    /// Swept over 10 patterns × 48 levels: 0 cells where the landing asks for
    /// more work than the level it came from.
    public static func tierFloor(_ level: Int) -> Int {
        let tier = decode(level).tier
        return (tier - 1) * EngineConfig.stepsPerTier
    }

    /// v2.23 (spec §34.1): the floor of a TIER OR SET BAND — the bottom of the
    /// mod-8 block the level sits in. Nothing lighter exists inside one
    /// variation, and the evaluative descent never steps past it.
    ///
    /// Why a block and not a tier: on the set bands (32–47) the tier is the
    /// same 4 throughout, but a step down across a band boundary changes both
    /// the set count and the starting dose (`repStartBand`, §28.1) — `squat`
    /// 32 → 31 reads as 4×4 → 3×11, 16 reps against 33. For levels 0..31 the
    /// block and the tier coincide word for word, and this equals `tierFloor`.
    public static func bandFloor(_ level: Int) -> Int {
        let l = min(max(level, 0), EngineConfig.levelMax)
        return l - (l % EngineConfig.stepsPerTier)
    }

    /// v2.12 (spec §22.1/§22.4): the rung of a tier that carries a given rep
    /// dose — rep continuity. A descent into an easier variation keeps the
    /// NUMBER of reps, not the mod-8 rung: repStart grows down the tiers, so
    /// keeping the rung landed on the top of the lower tier with a higher
    /// dose (audit finding A3-1).
    static func rung(tier: Int, reps: Int) -> Int {
        min(max(reps - (EngineConfig.repStart[tier] ?? EngineConfig.repMin), 0),
            EngineConfig.stepsPerTier - 1)
    }

    /// v2.12 (spec §22.4): the "I was sick" lens — the same level seen one
    /// tier easier. Tier 1 stays itself; the set bands are tier 4 by encoding
    /// and ease into tier 3 on base sets. Stored levels never change — this
    /// builds the plan's VIEW.
    public static func eased(_ level: Int) -> Int {
        let s = min(max(level, 0), EngineConfig.levelMax)
        let d = decode(s)
        if d.tier <= 1 { return s }
        let t = d.tier - 1
        return (t - 1) * EngineConfig.stepsPerTier + rung(tier: t, reps: d.reps)
    }

    /// v2.14 (spec §25.1): the encoding step of a unit — one rep, or as many
    /// seconds as ONE rung costs. The window of "the plan was met" is one step
    /// wide, so for reps it collapses to the old equality.
    ///
    /// v2.21 (spec §32.4): for statics that step is no longer a constant. The
    /// ladder is relative, so a rung costs anywhere from 1 s (tier 4, bottom)
    /// to 4 s (tier 1, top), and the window has to equal ONE REAL rung —
    /// otherwise it drifts apart from the inversion again, exactly as in #139.
    /// The step is local: the interval to the right of the plan's rung, or on
    /// the last rung the interval to the left, there being no ladder further
    /// right.
    static func step(of unit: LoadUnit, tier: Int, sets: Int, load: Int) -> Int {
        guard unit != .reps else { return 1 }
        let l = ladder(tier: tier, sets: sets)
        let top = l.count - 1
        let i = min(max(holdRung(l, load), 0), top)
        return i < top ? l[i + 1] - l[i] : l[top] - l[top - 1]
    }

    /// v2.14 (spec §25.3): how much work the plan of a level asks for. Only
    /// comparable within one unit.
    ///
    /// v2.19 (spec §30.1): sides are IN the measure. The old wording — "sides
    /// are a property of the variation, not of the rung, so they stay out of
    /// it" — was the reason a descent from a two-sided movement onto a
    /// one-sided one passed the gate: hinge L24 3×4 with both legs → 3×5 per
    /// leg is 12 reps against 30.
    /// v2.22 (spec §33): the measure takes a PAIR `(level, sub)`. `load` stays
    /// the BASE (smallest) dose of the plan, and the sub-steps' addition goes
    /// into `total`:
    ///
    ///     total = (sets·load + sub·(dose(L+1) − dose(L)))·sides
    ///
    /// At `sub == 0` both numbers are bit-for-bit what v2.21 gave.
    struct PlanWork {
        let tier: Int
        let sets: Int
        let unit: LoadUnit
        let sides: Int
        let load: Int
        let sub: Int
        let cut: Int
        let subDelta: Int

        var total: Int { (sets * load + sub * subDelta) * sides }
    }

    /// v2.25 (spec §36.2): the plan's sets are the band's LESS the ones taken
    /// off. The level fixes the variation and the dose per set; the cut only
    /// ever touches volume — neither the unit, nor the sides, nor the
    /// variation move — so the measure stays valid whatever the cut is:
    /// 3→2 is −33.3 %, 4→3 is −25.0 %, 5→4 is −20.0 %.
    ///
    /// `cut` carries NO default on purpose. Four skeptic rounds in a row found
    /// the same class of defect — an optional argument left out, or left out
    /// with the wrong floor — and a compile error is a stronger guard than a
    /// grep. The same rule holds for every §36 function below.
    static func work(pattern: Pattern, level: Int, sub: Int, cut: Int) -> PlanWork {
        let d = decode(level)
        let entry = ExerciseLibrary.entry(for: pattern)
        let unit = entry.unit(forTier: d.tier)
        let sets = setsAfterCut(level: level, cut: cut)
        let s = effectiveSub(level: level, sub: sub, sets: sets)
        return PlanWork(tier: d.tier, sets: sets, unit: unit,
                        sides: entry.variations[d.tier - 1].unilateral ? 2 : 1,
                        load: unit == .reps ? d.reps : d.hold,
                        sub: s,
                        cut: effCut(level: level, cut: cut,
                                    floor: EngineConfig.setsFloorPain),
                        subDelta: subDelta(pattern: pattern, level: level))
    }

    /// v2.14 (spec §25.3) · v2.19 (spec §30.2): "no harder". A descent has no
    /// right to make the plan heavier — neither per set nor in total work
    /// across sides. An honest zero on a 4×4 band used to land on 3×8, half
    /// again as many reps of the same movement ("I said zero and it added
    /// more"). Same root cause as A3-1: repStart grows DOWN the tiers, so
    /// rung arithmetic done in the planned tier's coordinates means more work
    /// one tier below.
    ///
    /// The rejected alternative was to drop v2.14's "landing on a tier floor
    /// is never harder" exemption: `Level.unload` returns exactly a tier
    /// floor, so on the pain path the gate rests on that one exemption — of
    /// the 400 pairs where the unload crosses a tier it is what lets 34
    /// through, and in 41 the total work across sides grows. But fixing that
    /// here would declare a measure in reps valid across a change of
    /// variation, which it is not. The
    /// exemption stays; the pain path is closed by the first step of §30.6,
    /// which never crosses a tier boundary at all.
    ///
    /// §30.4, ACCEPTED GAP: a change of unit (`pullBar` holds seconds at tier
    /// 1 and counts reps above) does not submit to comparison — 3×4 negative
    /// pull-ups and 3×50 s of hanging are incommensurable. That break belongs
    /// to the LADDER and is fixed in the library, the way v2.18 (§29) fixed
    /// pike → handstand, not in the measure of work.
    ///
    /// v2.22 (spec §33): the gate takes PAIRS `(level, sub)`. A descent from
    /// `(L, sub>0)` to `(L, 0)` is legal and no harder by construction: `load`
    /// is the same number (it is the base) and `total` falls by exactly the
    /// sub-steps that were given up. The per-set comparison reads the BASE,
    /// which is stricter than reading the heaviest set — the safe direction —
    /// and with `sub == 0` on both sides the gate is bit-for-bit v2.21's.
    /// v2.25 (spec §36.4): the gate takes TRIPLES `(level, sub, cut)`. Taking a
    /// set off inside one variation is always comparable — the dose per set is
    /// the same, the sides are the same, only the number of sets falls — so
    /// neither `load` nor `total` can grow by construction.
    static func noHarder(pattern: Pattern, from: Int, to: Int,
                         fromSub: Int = 0, toSub: Int = 0,
                         fromCut: Int, toCut: Int) -> Bool {
        let a = work(pattern: pattern, level: from, sub: fromSub, cut: fromCut)
        let b = work(pattern: pattern, level: to, sub: toSub, cut: toCut)
        if b.tier > a.tier { return false }
        if b.tier == a.tier {
            guard b.unit == a.unit else { return true }
            // Inside a tier the variation is the same one, so sides are
            // comparable and count. Across a tier boundary they are not.
            return b.load <= a.load && b.total <= a.total
        }
        // A lower tier: rep continuity (§22.1) — never more reps than the plan
        // asked for, except landing on that tier's own floor, which is the
        // step §15.2 provides for taking the load off.
        if to == (b.tier - 1) * EngineConfig.stepsPerTier { return true }
        guard b.unit == a.unit else { return true }
        return b.load <= a.load
    }

    /// v2.14 (spec §25.3): the nearest level at or below the inversion's
    /// result that does not ask for more work than the current plan. Applies
    /// to descents only — growth lives under the §15.3 ceiling, where by
    /// construction nothing gets heavier.
    /// v2.22 (spec §33): "the current plan" is the pair `(from, fromSub)`; the
    /// target of a descent always carries `sub == 0`, because every descent
    /// zeroes the sub-step.
    /// v2.25 (spec §36.4): the descent reads the triple, and a landing that
    /// CHANGES THE UNIT is chosen by time under load rather than by the rung
    /// next door — see `landOnUnitChange`.
    static func descendNoHarder(pattern: Pattern, from: Int, factLevel: Int,
                                fromSub: Int = 0, fromCut: Int) -> Int {
        if factLevel >= from { return factLevel }
        if noHarder(pattern: pattern, from: from, to: factLevel,
                    fromSub: fromSub, toSub: 0, fromCut: fromCut, toCut: 0) {
            // v2.25 (round 6, fix 5): the unit check stands on the EARLY
            // return too — without it an honest fact walked past it into the
            // hang.
            let a0 = work(pattern: pattern, level: from, sub: fromSub, cut: fromCut)
            let b0 = work(pattern: pattern, level: factLevel, sub: 0, cut: 0)
            if a0.unit != b0.unit {
                return landOnUnitChange(pattern: pattern, fromLevel: from, fromSub: fromSub,
                                        fromCut: fromCut, toTier: b0.tier)
            }
            return factLevel
        }
        // v2.25 (Ф2): the loop covers ZERO as well. The old `while cand > 0`
        // ended in an unconditional `return 0` — a position the gate might
        // itself have rejected: 352 triples were handed out around the very
        // check the gate exists for.
        var cand = factLevel - 1
        while cand >= 0 {
            if noHarder(pattern: pattern, from: from, to: cand,
                        fromSub: fromSub, toSub: 0, fromCut: fromCut, toCut: 0) {
                let a = work(pattern: pattern, level: from, sub: fromSub, cut: fromCut)
                let b = work(pattern: pattern, level: cand, sub: 0, cut: 0)
                if a.unit != b.unit {
                    return landOnUnitChange(pattern: pattern, fromLevel: from, fromSub: fromSub,
                                            fromCut: fromCut, toTier: b.tier)
                }
                return cand
            }
            cand -= 1
        }
        // Below zero there is nothing. If the gate rejected the whole scale we
        // do not move at all: standing still is always safer than jumping into
        // a cell the measure just called heavier. From here the descent goes
        // by taking sets off (§36.4).
        return from
    }

    /// Level from an actual value (reps or seconds) given the planned tier and
    /// sets. Tier 4 spans three set bands, so the base depends on sets; the
    /// unit comes from the (pattern, tier) library record.
    public static func fromActual(pattern: Pattern, tier: Int, sets: Int, actual: Int) -> Int {
        let lib = ExerciseLibrary.entry(for: pattern)
        // v2.17 (spec §28.1): the inversion reads the same start and step the
        // render used — the band's own when the plan sits in a band.
        let repStart = EngineConfig.repStartBand[sets]
            ?? EngineConfig.repStart[tier] ?? EngineConfig.repMin
        let step: Int
        switch lib.unit(forTier: tier) {
        case .reps:
            step = actual - repStart
        case .hold:
            // v2.21 (spec §32.5): the static inversion is a lookup of the
            // nearest rung ON THE TABLE of the same ladder that drew the plan.
            // A tie settles down, and past the ladder's edge the edge interval
            // carries on: the caps §15.3/§17.1 and the §25.3 gate apply on top.
            step = holdRung(ladder(tier: tier, sets: sets), actual)
        }
        let base = sets <= EngineConfig.setsBase
            ? (tier - 1) * EngineConfig.stepsPerTier
            : (EngineConfig.tiers + sets - EngineConfig.setsBase - 1) * EngineConfig.stepsPerTier
        return min(max(base + step, 0), EngineConfig.levelMax)
    }
}
