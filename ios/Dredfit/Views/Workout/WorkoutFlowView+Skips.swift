//
//  The skip that happens DURING the workout: one set, the rest of the sets,
//  or the movement — and the two escapes the work screen offers for them.
//
//  A file of its own for the reason WorkoutFlowView+Summary.swift is: the
//  lint bounds WorkoutFlowView.swift at 1200 lines as an ERROR, and it is
//  the FILE that a split cures. The flow stood 41 lines under that ceiling
//  after §41.13 (review, 12.09.2026). Swift's `private` is file-scoped, so
//  what this reaches for — the two exits `leaveExercise` and
//  `advancePastExercise`, and the `pendingSkip` the confirmation hangs on —
//  is declared without it, like everything the earlier siblings reach for.
//

import SwiftUI
import DredfitCore

extension WorkoutFlowView {

    // MARK: - The skip that happens DURING the workout

    /// Whether a skip still leaves a trained movement behind, asked of the
    /// plan in front of us — the arithmetic itself is `SetFacts.skipFits`,
    /// where it can be tested without a screen.
    private func skipsLeaveAMovement(_ count: Int) -> Bool {
        SetFacts.skipFits(count, of: exercise.sets,
                          alreadySkipped: setsSkipped[exercise.pattern] ?? 0)
    }

    /// Sets of this exercise already behind and actually performed.
    private var setsPerformedHere: Int {
        setIndex - (setsSkipped[exercise.pattern] ?? 0)
    }

    /// "Skip this set": the set is not performed and the next one is up.
    ///
    /// No rest on the way out — there is nothing to recover from, and the
    /// minutes are the whole point of the tap.
    private func skipSet() {
        // Skipping the PROBE takes no volume off anything: it was never a set
        // of the planned movement. The outcome is "unresolved" (§40.4) — the
        // probe simply comes back next time — and the appearance is spent
        // exactly as it would have been.
        if onProbeSet {
            adjusting = false
            probeActuals.removeValue(forKey: exercise.pattern)
            advancePastExercise()
            return
        }
        guard skipsLeaveAMovement(1) else { leaveExercise(); return }
        adjusting = false
        setsSkipped[exercise.pattern, default: 0] += 1
        if isLastSet {
            advancePastExercise()
        } else {
            resetHoldSides()   // see `resetHoldSides`: this path skips it otherwise
            setIndex += 1
            phase = .work
            liveActivity.update(activityWorkState())
            persistProgress()
        }
    }

    /// "Skip the remaining sets": one tap for the whole movement. Sixteen
    /// separate taps to fit a session into 45 minutes is a thing nobody does;
    /// three to six is.
    private func skipRestOfExercise() {
        // Only the WORKING sets can be taken off; on the probe set there are
        // none left, and the probe itself is not volume.
        let left = max(0, exercise.sets - setIndex)
        guard skipsLeaveAMovement(left) else { leaveExercise(); return }
        adjusting = false
        setsSkipped[exercise.pattern, default: 0] += left
        advancePastExercise()
    }

    /// The set-level skip, or nil when it would take the movement with it —
    /// then the escape beside it says so in its own label instead of doing it
    /// quietly under a word that promises less.
    var setSkipAction: (() -> Void)? {
        // The probe can ALWAYS be skipped (§40.4): it is not a set of the
        // planned movement, so skipping it takes no volume off anything and
        // cannot leave the movement untrained. The outcome is "unresolved",
        // and the probe comes back on the next appearance.
        if onProbeSet {
            return { pendingSkip = SkipConfirmation(kind: .probeSet) { skipSet() } }
        }
        guard skipsLeaveAMovement(1) else { return nil }
        return { pendingSkip = SkipConfirmation(kind: .workingSet) { skipSet() } }
    }

    /// The exercise-level escape, and the landing its label names. The two
    /// controls collapse into one whenever they would do the same thing: on
    /// the floor both take the movement, and on the last set "the remaining
    /// sets" ARE this set.
    var exerciseEscape: ExerciseActionsRow.Escape? {
        // On the probe set the working sets are already behind: "skip the
        // exercise" would throw away a movement that was in fact trained.
        // Skipping the probe is the set-level control beside this one.
        guard !onProbeSet else { return nil }
        let leave = ExerciseActionsRow.Escape(
            title: String(localized: "Skip exercise"),
            identifier: "exercise-skip",
            action: { pendingSkip = SkipConfirmation(kind: .exercise) { leaveExercise() } })
        guard skipsLeaveAMovement(1) else { return leave }
        guard !isLastSet else { return nil }
        guard setsPerformedHere >= EngineConfig.setsFloor else { return leave }
        return ExerciseActionsRow.Escape(
            title: String(localized: "Skip remaining sets"),
            identifier: "exercise-skip-rest",
            action: { pendingSkip = SkipConfirmation(kind: .restOfSets) { skipRestOfExercise() } })
    }
}
