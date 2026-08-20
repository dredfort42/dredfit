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
        let holdStart = EngineConfig.holdStartBand[sets]
            ?? EngineConfig.holdStart[tier] ?? EngineConfig.holdMin
        let holdStep = EngineConfig.holdStepBand[sets] ?? EngineConfig.holdStepSec
        return LevelDecoded(
            tier: tier,
            sets: sets,
            reps: repStart + step,
            hold: holdStart + step * holdStep
        )
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

    /// v2.14 (spec §25.1): the encoding step of a unit — one rep, or
    /// `holdStepSec` seconds. The window of "the plan was met" is one step
    /// wide, so for reps it collapses to the old equality.
    static func step(of unit: LoadUnit) -> Int {
        unit == .reps ? 1 : EngineConfig.holdStepSec
    }

    /// v2.14 (spec §25.3): how much work the plan of a level asks for. Only
    /// comparable within one unit.
    ///
    /// v2.19 (spec §30.1): sides are IN the measure. The old wording — "sides
    /// are a property of the variation, not of the rung, so they stay out of
    /// it" — was the reason a descent from a two-sided movement onto a
    /// one-sided one passed the gate: hinge L24 3×4 with both legs → 3×5 per
    /// leg is 12 reps against 30.
    struct PlanWork {
        let tier: Int
        let sets: Int
        let unit: LoadUnit
        let sides: Int
        let load: Int

        var total: Int { sets * load * sides }
    }

    static func work(pattern: Pattern, level: Int) -> PlanWork {
        let d = decode(level)
        let entry = ExerciseLibrary.entry(for: pattern)
        let unit = entry.unit(forTier: d.tier)
        return PlanWork(tier: d.tier, sets: d.sets, unit: unit,
                        sides: entry.variations[d.tier - 1].unilateral ? 2 : 1,
                        load: unit == .reps ? d.reps : d.hold)
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
    static func noHarder(pattern: Pattern, from: Int, to: Int) -> Bool {
        let a = work(pattern: pattern, level: from), b = work(pattern: pattern, level: to)
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
    static func descendNoHarder(pattern: Pattern, from: Int, factLevel: Int) -> Int {
        if factLevel >= from || noHarder(pattern: pattern, from: from, to: factLevel) {
            return factLevel
        }
        var cand = factLevel - 1
        while cand > 0 {
            if noHarder(pattern: pattern, from: from, to: cand) { return cand }
            cand -= 1
        }
        return 0
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
        let holdStart = EngineConfig.holdStartBand[sets]
            ?? EngineConfig.holdStart[tier] ?? EngineConfig.holdMin
        let holdStep = EngineConfig.holdStepBand[sets] ?? EngineConfig.holdStepSec
        let step: Int
        switch lib.unit(forTier: tier) {
        case .reps:
            step = actual - repStart
        case .hold:
            step = Int((Double(actual - holdStart) / Double(holdStep)).rounded())
        }
        let base = sets <= EngineConfig.setsBase
            ? (tier - 1) * EngineConfig.stepsPerTier
            : (EngineConfig.tiers + sets - EngineConfig.setsBase - 1) * EngineConfig.stepsPerTier
        return min(max(base + step, 0), EngineConfig.levelMax)
    }
}
