//
//  The athlete's handles. v2.26 removed two mechanisms that decided FOR the
//  person — the pain channel and the time budget — and gave back controls that
//  decide WITH them. v2.27 removed the last one that still asked them to decide
//  BEFORE the workout ("shorter today"); what is left is one variation handle,
//  one axis entry point, and the order in which a skip has to land on it.
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

    /// A session's feedback and the sets skipped while doing it, landed in the
    /// ONE order that does not lose them (spec §38.2, rule 1).
    ///
    /// The order is a CONTRACT, not a caller's convention, which is why this
    /// exists at all: a skip written BEFORE the rating disappears in silence.
    /// On a session the person completed, `applyFeedback` calls `riseBy`, and
    /// `riseBy` hands a set BACK instead of raising the level (§37.6) — so the
    /// cut recorded in advance is eaten by exactly the event that should have
    /// returned it later. The cut belongs on the RESULT of the feedback, never
    /// on its input. Reproduced on L24 (3×4 stays 3×4 instead of becoming 2×4)
    /// and on L40 (5×8 stays 5×8 instead of 4×8), and the reference's block 55
    /// asserts BOTH directions so a port that swaps them cannot pass quietly.
    ///
    /// The app layer never has to get this right, because it cannot express
    /// the wrong order through this entry point: it hands over what happened,
    /// and the order is settled here.
    ///
    /// `setsSkipped` counts sets skipped DURING the session, per movement. It
    /// is added to whatever cut the feedback left behind — not assigned — and
    /// `setCut` clamps it to `cutMax`, so asking for more than remains is
    /// ordinary, not an error. A movement already at the floor has nothing to
    /// take: rule 2 says that skip travels as an ordinary skipped EXERCISE, in
    /// `skipped`, never as a fact of 0 reps, and the caller decides which of
    /// the two a tap became before it gets here.
    public static func applyFeedback(
        state: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides: [Pattern: Int] = [:],
        skipped: Set<Pattern> = [],
        setsSkipped: [Pattern: Int],
        gapDays: Double? = nil
    ) -> EngineState {
        var next = Self.applyFeedback(state: state, session: session, result: result,
                                      overrides: overrides, skipped: skipped,
                                      gapDays: gapDays)
        // Walked in `Pattern.allCases` order, which is the reference's
        // `ALL_PATTERNS` order: each step re-reads the cut it is adding to, so
        // the walk is not order-free.
        for p in Pattern.allCases {
            guard let k = setsSkipped[p], k > 0 else { continue }
            next = Self.setCut(state: next, pattern: p, cut: next.cutOf(p) + k)
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
