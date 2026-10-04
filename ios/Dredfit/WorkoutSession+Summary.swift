//
//  The exercise summary a hold movement ends on: which card the adjuster
//  edits, the ceiling of a correction, and the steps added "for next time".
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// Opens the entry on the card that was tapped. Only the last card
    /// calls this (`HeldSetsRow`); the guard keeps it true if a caller
    /// changes.
    func startSummaryAdjusting(set index: Int) {
        guard isLastSummarySet(index) else { return }
        adjustValue = SetFacts.inForce(actuals, exercise, set: index)
        editing = .summaryCard(index)
    }

    /// OK on the summary's panel: the correction lands on the card that was
    /// tapped.
    func commitSummaryEdit(set index: Int) {
        actuals = SetFacts.recordingSet(adjustValue, in: actuals,
                                        exercise, set: index)
        // The correction moves the base under an addition already
        // made: on the grid's ceiling the steps added before it
        // burn, and the stepper read "+10 s" over a sentence that
        // showed the plan "+5 s" shows (review, 12.09.2026).
        trimRaiseToWhatStillMoves()
        // A number the person typed is not an estimate any
        // more, whatever produced the one it replaced.
        holdApproxSets.remove(index)
        // The second door of the same channel, and it spends
        // the same one-way flag: the work screen's hint asks
        // people to say a number of their own, and correcting
        // a card here IS saying one. Without this call the
        // hint went on being shown to somebody who had
        // already answered it (UX review, 05.09.2026).
        store.markOwnNumberReported()
        editing = nil
        persistProgress()
    }

    /// What the clock counted for a set — the number before any correction.
    /// A set no clock ran for (skipped mid-movement, restored from a snapshot
    /// written before the field) falls back to what the card shows, which is
    /// what the ceiling used to be read off for every set.
    func summaryMeasured(set index: Int) -> Int {
        holdMeasured[index] ?? SetFacts.inForce(actuals, exercise, set: index)
    }

    func isLastSummarySet(_ index: Int) -> Bool { index == exercise.sets - 1 }

    /// The rule is `SetFacts.correctionRange`, where a test can reach it;
    /// what is measured is the CLOCK's number, not the card's — a card
    /// corrected downwards must be correctable back up to what was counted.
    /// Only the last set reaches this from the screen now.
    func summaryRange(set index: Int) -> ClosedRange<Int> {
        SetFacts.correctionRange(measured: summaryMeasured(set: index),
                                 isLastSet: isLastSummarySet(index))
    }

    /// The plan this movement will get with `steps` additions — the engine's
    /// own answer, dry-run through the store with everything this session
    /// has recorded so far (§41.13).
    func nextPlan(withAdditions steps: Int) -> SessionExercise? {
        var raised = raisedSteps
        raised[exercise.pattern] = steps > 0 ? steps : nil
        return store.previewPosition(after: session, pattern: exercise.pattern,
                                     overrides: SetFacts.overrides(actuals, in: exercises),
                                     skipped: skippedPatterns, setsSkipped: setsSkipped,
                                     probes: probeActuals, raised: raised)?
            .asPlanned(exercise.pattern)
    }

    /// The stepper's write: a DECISION, kept apart from the facts and
    /// persisted like them — a kill between here and the rating must not
    /// drop it.
    func setRaise(_ steps: Int) {
        let clamped = min(max(steps, 0), EngineConfig.raiseStepsMax)
        raisedSteps[exercise.pattern] = clamped > 0 ? clamped : nil
        persistProgress()
    }

    /// The count after a correction: the rule is `NextTimeBlock`'s — the
    /// same comparison its "+" is disabled with — walked down from the
    /// count. Persisted by the caller with the correction it follows.
    func trimRaiseToWhatStillMoves() {
        let steps = raisedSteps[exercise.pattern] ?? 0
        let live = NextTimeBlock.stepsThatStillMove(steps, preview: nextPlan(withAdditions:))
        if live != steps { raisedSteps[exercise.pattern] = live > 0 ? live : nil }
    }
}
