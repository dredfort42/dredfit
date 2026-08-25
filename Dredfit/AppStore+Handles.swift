//
//  The athlete's handles.
//
//  v2.26 removed the two mechanisms that decided FOR the person — the pain
//  channel and the time budget — and gave back controls that decide WITH them.
//  v2.27 removed the last two that still asked for the decision BEFORE the
//  workout: "shorter today" and "fewer sets" on the plan. Both wanted an
//  answer to a question the person only knows the answer to standing on the
//  mat, and both are replaced by the skip on the work screen (§38.2).
//
//  What is left on the plan is one handle and one number. The handle changes
//  the VARIATION, not the volume — a different question, and the only one
//  worth asking before the first set. The number is the range the session can
//  land in, so "will this fit today" has an answer without a control at all.
//
//  This file holds what the plan can be ASKED. The one action that WRITES
//  state lives in AppStore proper, the same way `acceptComeback` does: the
//  store owns its own mutations. Every handle goes through the ENGINE — the
//  app writing a level or a cut into the state by hand is the bypass of
//  `applyFeedback` the audit counts as a finding: it would skip the floor, the
//  sanitizer, and the position measure the postcondition repair reads.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Per-movement: an easier variation

    /// False on tier 1 — there is no variation below it, and the control says
    /// so instead of disappearing.
    func canMakeEasier(_ pattern: Pattern) -> Bool {
        Engine.easierLevel(pattern: pattern,
                           level: engineState.levels[pattern] ?? 0,
                           sub: engineState.sub[pattern] ?? 0,
                           cut: engineState.cutOf(pattern)) != nil
    }

    /// The name this movement would carry after the handle — shown BEFORE the
    /// tap, so the choice is made on the thing itself rather than on a
    /// promise. Nil when the handle is inactive.
    func easierPreview(_ pattern: Pattern) -> String? {
        guard canMakeEasier(pattern) else { return nil }
        let after = Engine.easierVariation(state: engineState, pattern: pattern)
        return Engine.generateSession(after).exercises
            .first { $0.pattern == pattern }
            .map { "\($0.name) · \($0.display)" }
    }

    // MARK: - How long today can be

    /// The two ends of today's session (§38.3): the full plan, and the same
    /// plan with every movement on the sets floor — the shortest the person
    /// can make it from inside the workout.
    ///
    /// This is what replaced the handle. The question the handle answered was
    /// "will this fit today", and a range answers it without asking anyone to
    /// decide anything: 26–34 min at L0, 40–94 at L47.
    ///
    /// Both numbers are the engine's own `estimatedTotalMin` — the app owns no
    /// arithmetic about duration. The floor session is a QUESTION put to the
    /// engine, never a state that is written: nothing here moves the plan, and
    /// the low end is only reached by actually skipping the sets.
    ///
    /// The floor is clamped to the full plan rather than trusted to be below
    /// it. Taking sets off cannot make a plan heavier by construction, but the
    /// line would be nonsense if it ever did, and a range is a promise about
    /// which end is which.
    func sessionLengthRange() -> (floor: Int, full: Int) {
        let full = nextSession.estimatedTotalMin
        var floored = engineState
        for pattern in Pattern.allCases {
            floored = Engine.setCut(
                state: floored, pattern: pattern,
                cut: Level.cutMax(level: floored.levels[pattern] ?? 0,
                                  floor: EngineConfig.setsFloor))
        }
        let shortest = min(Engine.generateSession(floored).estimatedTotalMin, full)
        return (Int(shortest.rounded()), Int(full.rounded()))
    }
}
