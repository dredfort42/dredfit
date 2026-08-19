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
        return LevelDecoded(
            tier: tier,
            sets: EngineConfig.setsBase + max(0, band - (EngineConfig.tiers - 1)),
            reps: (EngineConfig.repStart[tier] ?? EngineConfig.repMin) + step,
            hold: (EngineConfig.holdStart[tier] ?? EngineConfig.holdMin)
                + step * EngineConfig.holdStepSec
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
    /// comparable within one unit; sides are a property of the variation, not
    /// of the rung, so they stay out of it.
    struct PlanWork {
        let tier: Int
        let sets: Int
        let unit: LoadUnit
        let load: Int
    }

    static func work(pattern: Pattern, level: Int) -> PlanWork {
        let d = decode(level)
        let unit = ExerciseLibrary.entry(for: pattern).unit(forTier: d.tier)
        return PlanWork(tier: d.tier, sets: d.sets, unit: unit,
                        load: unit == .reps ? d.reps : d.hold)
    }

    /// v2.14 (spec §25.3): "no harder". A descent has no right to make the
    /// plan heavier — an honest zero on a 4×4 band used to land on 3×8, half
    /// again as many reps of the same movement ("I said zero and it added
    /// more"). Same root cause as A3-1: repStart grows DOWN the tiers, so
    /// rung arithmetic done in the planned tier's coordinates means more work
    /// one tier below.
    static func noHarder(pattern: Pattern, from: Int, to: Int) -> Bool {
        let a = work(pattern: pattern, level: from), b = work(pattern: pattern, level: to)
        if b.tier > a.tier { return false }
        if b.tier == a.tier {
            guard b.unit == a.unit else { return true }
            return b.sets * b.load <= a.sets * a.load
        }
        // A lower tier: rep continuity (§22.1) — never more reps than the plan
        // asked for, except landing on that tier's own floor.
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
        let step: Int
        switch lib.unit(forTier: tier) {
        case .reps:
            step = actual - (EngineConfig.repStart[tier] ?? EngineConfig.repMin)
        case .hold:
            let start = EngineConfig.holdStart[tier] ?? EngineConfig.holdMin
            step = Int((Double(actual - start) / Double(EngineConfig.holdStepSec)).rounded())
        }
        let base = sets <= EngineConfig.setsBase
            ? (tier - 1) * EngineConfig.stepsPerTier
            : (EngineConfig.tiers + sets - EngineConfig.setsBase - 1) * EngineConfig.stepsPerTier
        return min(max(base + step, 0), EngineConfig.levelMax)
    }
}
