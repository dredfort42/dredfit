//
//  The athlete's handles. The wave removes two
//  mechanisms that decided FOR the person — the pain channel and the time
//  budget — and gives back three controls that decide WITH them.
//
//  All three are engine entry points on purpose. The app layer writing into
//  the state directly is the very bypass of `applyFeedback` the audit counts
//  as a finding: a cut written by hand skips the floor, skips the sanitizer,
//  and skips the position measure the postcondition repair reads.
//

import Foundation

extension Engine {

    /// Where "give me an easier variation" lands, or nil when the handle is
    /// inactive.
    ///
    /// The target is one tier down and the landing goes through the ORDINARY
    /// gate — the handle has no arithmetic of its own. `descendNoHarder`
    /// already knows the rep-continuity and the change of unit
    /// (`landOnUnitChange`), which is why a landing may sit ABOVE the floor of
    /// the tier below: on `pull_bar` the tier-2 negatives are reps and tier 1
    /// is a hang in seconds, and dropping to the tier's floor there would cut
    /// the time under load fivefold instead of by a few per cent. Five cells
    /// of the whole grid do this, all on `pull_bar`, and all are pinned by the
    /// golden fixture so a port cannot "fix" them into the floor.
    ///
    /// On tier 1 the handle is INACTIVE and says so by returning nil rather
    /// than by standing still: a control that promises what it cannot deliver
    /// is worse than a disabled one.
    public static func easierLevel(pattern: Pattern, level: Int,
                                   sub: Int = 0, cut: Int = 0) -> Int? {
        let tier = Level.decode(level).tier
        if tier <= 1 { return nil }
        return Level.descendNoHarder(pattern: pattern, from: level,
                                     factLevel: (tier - 2) * EngineConfig.stepsPerTier,
                                     fromSub: sub, fromCut: cut)
    }

    /// The state after "give me an easier variation" on one movement.
    ///
    /// The sub-step and the sets taken off are ZEROED: the variation changed,
    /// and there is nothing to carry a position of the old one over on — the
    /// measure across a variation boundary is invalid.
    ///
    /// Mirrors the reference field for field: `levels`, `sub` and `cut` are
    /// rebuilt through their sanitizers, everything else is passed through
    /// untouched. That asymmetry is deliberate and is pinned by the diff test:
    /// a handle is a NARROW EDITOR of one axis, not a state builder, and one
    /// that silently rewrote fields it was not asked about would be worse.
    public static func easierVariation(state: EngineState, pattern p: Pattern) -> EngineState {
        let levels = Self.healedLevels(state)
        let subs = EngineState.healSub(state.sub, levels: levels)
        let cuts = EngineState.healCut(state.cut, levels: levels)
        guard let to = Self.easierLevel(pattern: p, level: levels[p] ?? 0,
                                        sub: subs[p] ?? 0, cut: cuts[p] ?? 0) else {
            return state
        }
        var next = state
        next.levels = levels
        next.levels[p] = to
        next.sub = subs
        next.cut = cuts
        next.sub.removeValue(forKey: p)
        next.cut.removeValue(forKey: p)
        return next
    }

    /// "fewer sets" on one movement. The floor is the shared one — two sets —
    /// and the handle CLAMPS to it rather than dropping the plan under it.
    /// Asking for nine on a band of three gives the same plan as asking for
    /// one.
    ///
    /// Levels are NOT written back here (the reference does not either): this
    /// handle touches one axis, `cut`, and nothing else.
    public static func setCut(state: EngineState, pattern p: Pattern, cut: Int) -> EngineState {
        let levels = Self.healedLevels(state)
        let cuts = EngineState.healCut(state.cut, levels: levels)
        let value = EngineState.clamped(
            cut, 0, Level.cutMax(level: levels[p] ?? 0, floor: EngineConfig.setsFloor))
        var next = state
        next.cut = cuts
        if value > 0 { next.cut[p] = value } else { next.cut.removeValue(forKey: p) }
        return next
    }

    /// "shorter today" — the same cut across every movement at once.
    ///
    /// NO NEW STATE FIELD is introduced, and that is the point rather than an
    /// implementation detail: this is the same `cut`, written as a list, so a
    /// set earned back by growing works for it exactly as it does for a cut
    /// taken one movement at a time. A separate "session mode" field would
    /// have needed its own return path, its own sanitizer and its own place in
    /// every gate that reads the position.
    ///
    /// Each movement takes `max(current, steps)`: the session handle never
    /// gives a set BACK to a movement the person had already cut deeper by
    /// hand. Releasing it is `setCut(..., 0)`.
    public static func shorterSession(state: EngineState, steps: Int) -> EngineState {
        let k = max(0, steps)
        var next = state
        // Walked in `Pattern.allCases` order, which is the reference's
        // `ALL_PATTERNS` order: each step re-reads the cut through the
        // sanitizer, so the walk is not order-free.
        for p in Pattern.allCases {
            let levels = Self.healedLevels(next)
            let current = EngineState.healCut(next.cut, levels: levels)[p] ?? 0
            next = Self.setCut(state: next, pattern: p, cut: max(current, k))
        }
        return next
    }

    /// The levels container as every handle reads it — the reference's
    /// `cleanLevels`, which fills in the missing patterns and clamps the rest.
    private static func healedLevels(_ state: EngineState) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for p in Pattern.allCases {
            out[p] = EngineState.clamped(state.levels[p] ?? 0, 0, EngineConfig.levelMax)
        }
        return out
    }
}
