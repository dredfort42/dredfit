//
//  v2.26 (§37): the athlete's handles.
//
//  The app does not guess what a person can do. It offers handles and works
//  out the consequences. Both of these change the state THROUGH the engine —
//  the app layer writing state directly would bypass the floor, the sanitizer
//  and the postcondition repair, which is why they are entry points and not
//  helpers.
//

import Foundation

extension Engine {

    /// "Give me an easier variation" (§37.4, rewritten by §40.6, amended by
    /// §41.1): one variation down, at the dose from the JOURNAL OF WHAT WAS
    /// SHOWN — but the journal is the CEILING, not the answer. A neighbour
    /// variation can be trained per side, so the same remembered dose is twice
    /// the work; `landInVar` steps down from the ceiling until the plan fits
    /// the work already being done. Without that, "make it easier" made 49
    /// boundaries out of 49 harder.
    ///
    /// On the first variation the handle is inert: there is nothing below it
    /// in the library, and 3×4 is the accepted minimum base (§37.1).
    public static func easierPosition(pattern p: Pattern, position: Position,
                                      shown: [Pattern: [Int: Int]]) -> Position? {
        guard position.variation > 1 else { return nil }
        return landInVar(p, position.variation - 1, shown: shown, from: position)
    }

    public static func easierVariation(state dirty: EngineState, pattern p: Pattern) -> EngineState {
        let state = dirty.sanitized()
        guard let to = easierPosition(pattern: p, position: state.position(p),
                                      shown: state.shown) else { return dirty }
        var next = state
        setPosition(&next, p, to)
        return next
    }

    /// "Fewer sets" on one movement (§37.5, and the entry point a skipped set
    /// arrives through, §38.2). The floor is the shared one: two sets.
    public static func setCut(state dirty: EngineState, pattern p: Pattern,
                              cut: Int) -> EngineState {
        let state = dirty.sanitized()
        var next = state
        var pos = state.position(p)
        pos.cut = effCut(sets: state.sets[p] ?? EngineConfig.setsBase, cut: cut)
        setPosition(&next, p, pos)
        return next
    }

    /// Feedback plus the sets skipped DURING the session, in the one order
    /// that is correct (§38.2, rule 1): `applyFeedback` FIRST, then `setCut`.
    ///
    /// On a session the person completed, `applyFeedback` calls `riseBy`, and
    /// `riseBy` hands a set BACK instead of raising the dose — so a cut
    /// recorded in advance is eaten by exactly the event that should have
    /// returned it later. The cut belongs on the RESULT of the feedback, never
    /// on its input, and the golden fixture pins both the cut before the skip
    /// and the plan of the next step, so a port that swaps them fails loudly.
    ///
    /// The app layer never has to get this right, because it cannot express
    /// the wrong order through this entry point.
    ///
    /// `setsSkipped` is ADDED to whatever cut the feedback left behind — not
    /// assigned — and `setCut` clamps it to `cutMax`, so asking for more than
    /// remains is ordinary, not an error. A movement already at the floor has
    /// nothing to take: that skip travels as an ordinary skipped EXERCISE, in
    /// `skipped`, never as a fact of 0 reps.
    public static func applyFeedback(
        state: EngineState,
        session: Session,
        result: FeedbackResult,
        overrides: [Pattern: Double] = [:],
        skipped: Set<Pattern> = [],
        setsSkipped: [Pattern: Int],
        gapDays: Double? = nil,
        probes: [Pattern: Int] = [:]) -> EngineState {
        var next = Self.applyFeedback(state: state, session: session, result: result,
                                      overrides: overrides, skipped: skipped,
                                      gapDays: gapDays, probes: probes)
        // Walked in `Pattern.allCases` order — the reference's `ALL_PATTERNS`.
        // Each step re-reads the cut it is adding to, so the walk is written
        // down rather than left to a dictionary's arbitrary order.
        for p in Pattern.allCases {
            guard let k = setsSkipped[p], k > 0 else { continue }
            next = Self.setCut(state: next, pattern: p, cut: next.cutOf(p) + k)
        }
        return next
    }
}
