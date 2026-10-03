//
//  The two escapes the work screen offers for a skip DURING the workout —
//  one set, the rest of the sets, or the movement — and the confirmation each
//  asks for. The skips themselves are WorkoutSession's (+Skips).
//

import SwiftUI
import DredfitCore

extension WorkoutFlowView {

    // MARK: - The skip that happens DURING the workout

    /// The set-level skip, or nil when it would take the movement with it —
    /// then the escape beside it says so in its own label instead of doing it
    /// quietly under a word that promises less.
    var setSkipAction: (() -> Void)? {
        // The probe can ALWAYS be skipped (§40.4): it is not a set of the
        // planned movement, so skipping it takes no volume off anything and
        // cannot leave the movement untrained. The outcome is "unresolved",
        // and the probe comes back on the next appearance.
        if flow.onProbeSet {
            return { pendingSkip = SkipConfirmation(kind: .probeSet) { flow.skipSet() } }
        }
        guard flow.skipsLeaveAMovement(1) else { return nil }
        return { pendingSkip = SkipConfirmation(kind: .workingSet) { flow.skipSet() } }
    }

    /// The exercise-level escape, and the landing its label names. The two
    /// controls collapse into one whenever they would do the same thing: on
    /// the floor both take the movement, and on the last set "the remaining
    /// sets" ARE this set.
    var exerciseEscape: ExerciseActionsRow.Escape? {
        // On the probe set the working sets are already behind: "skip the
        // exercise" would throw away a movement that was in fact trained.
        // Skipping the probe is the set-level control beside this one.
        guard !flow.onProbeSet else { return nil }
        let leave = ExerciseActionsRow.Escape(
            title: String(localized: "Skip exercise"),
            identifier: "exercise-skip",
            action: { pendingSkip = SkipConfirmation(kind: .exercise) { flow.leaveExercise() } })
        guard flow.skipsLeaveAMovement(1) else { return leave }
        guard !flow.isLastSet else { return nil }
        guard flow.setsPerformedHere >= EngineConfig.setsFloor else { return leave }
        return ExerciseActionsRow.Escape(
            title: String(localized: "Skip remaining sets"),
            identifier: "exercise-skip-rest",
            action: { pendingSkip = SkipConfirmation(kind: .restOfSets) { flow.skipRestOfExercise() } })
    }
}
