//
//  The athlete's handles.
//
//  The two mechanisms that decided FOR the person — the pain channel and the
//  time budget — are gone, and controls that decide WITH them came back in
//  their place. So are the last two that still asked for the decision BEFORE
//  the workout: "shorter today" and "fewer sets" on the plan. Both wanted an
//  answer to a question the person only knows the answer to standing on the
//  mat, and both are replaced by the skip on the work screen.
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

    /// False on the first variation — there is nothing below it in the
    /// library, and the block that carries the handle is ABSENT there rather
    /// than standing disabled. This comment used to claim the opposite ("the
    /// control says so instead of disappearing") while the code had always
    /// hidden it; a rule stated backwards is worse than none, because the next
    /// reader implements the comment.
    func canMakeEasier(_ pattern: Pattern) -> Bool {
        Engine.easierPosition(pattern: pattern, position: engineState.position(pattern),
                              shown: engineState.shown) != nil
    }

    /// The movement one step down the ladder, in the pieces the technique
    /// sheet draws (R30). It replaced `easierPreview`, which glued the same
    /// facts into one string for a 12.5 pt line on the plan — the block has
    /// room to say them apart, and one of them could not be said at all in a
    /// glued string: on `pull_bar` 3 → 2 the UNIT changes, and "3×15" turning
    /// into "3×15 sec" is not a difference anyone reads off a preview.
    ///
    /// Nil when the handle is inactive, which is the same question
    /// `canMakeEasier` answers — asked through it, so the block cannot appear
    /// on a movement the engine would refuse to move.
    struct EasierStep {
        let name: String
        let dose: String
        /// Reps → hold, or hold → reps. The one fact a name and a number
        /// cannot carry between them.
        let unitChanged: Bool
        /// The variation AFTER the step, for the sheet that redraws onto it.
        let variation: Int
    }

    /// Asks the engine and writes nothing: `easierVariation` on a COPY of the
    /// state, then the ordinary session generator, so what is shown is what the
    /// tap would deliver rather than a second arithmetic that could disagree
    /// with it.
    func easierStep(_ pattern: Pattern) -> EasierStep? {
        guard canMakeEasier(pattern) else { return nil }
        let before = Library.unit(pattern, engineState.position(pattern).variation)
        let after = Engine.easierVariation(state: engineState, pattern: pattern)
        return Engine.generateSession(after).exercises
            .first { $0.pattern == pattern }
            .map { EasierStep(name: $0.name, dose: $0.display,
                              unitChanged: $0.unit != before, variation: $0.variation) }
    }

    // MARK: - How long today can be

    /// The two ends of today's session: the full plan, and the same
    /// plan with every movement on the sets floor — the shortest the person
    /// can make it from inside the workout.
    ///
    /// This is what replaced the handle. The question the handle answered was
    /// "will this fit today", and a range answers it without asking anyone to
    /// decide anything.
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
                cut: Engine.cutMax(sets: floored.position(pattern).sets))
        }
        let shortest = min(Engine.generateSession(floored).estimatedTotalMin, full)
        return (Int(shortest.rounded()), Int(full.rounded()))
    }
}
