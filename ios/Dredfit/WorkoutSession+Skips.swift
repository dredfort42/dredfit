//
//  The skip that happens DURING the workout: one set, the rest of the sets,
//  or the movement.
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// Whether a skip still leaves a trained movement behind, asked of the
    /// plan in front of us — the arithmetic itself is `SetFacts.skipFits`,
    /// where it can be tested without a screen.
    func skipsLeaveAMovement(_ count: Int) -> Bool {
        SetFacts.skipFits(count, of: exercise.sets,
                          alreadySkipped: setsSkipped[exercise.pattern] ?? 0)
    }

    /// Sets of this exercise already behind and actually performed.
    var setsPerformedHere: Int {
        setIndex - (setsSkipped[exercise.pattern] ?? 0)
    }

    /// "Skip this set": the set is not performed and the next one is up.
    ///
    /// No rest on the way out — there is nothing to recover from, and the
    /// minutes are the whole point of the tap.
    func skipSet() {
        // Skipping the PROBE takes no volume off anything: it was never a set
        // of the planned movement. The outcome is "unresolved" (§40.4) — the
        // probe simply comes back next time — and the appearance is spent
        // exactly as it would have been.
        if onProbeSet {
            editing = nil
            probeActuals.removeValue(forKey: exercise.pattern)
            advancePastExercise()
            return
        }
        guard skipsLeaveAMovement(1) else { leaveExercise(); return }
        editing = nil
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
    func skipRestOfExercise() {
        // Only the WORKING sets can be taken off; on the probe set there are
        // none left, and the probe itself is not volume.
        let left = max(0, exercise.sets - setIndex)
        guard skipsLeaveAMovement(left) else { leaveExercise(); return }
        editing = nil
        setsSkipped[exercise.pattern, default: 0] += left
        advancePastExercise()
    }
}
