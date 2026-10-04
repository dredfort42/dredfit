//
//  The exercise summary a hold movement ends on: which card the adjuster
//  edits, what the panel's line and a card's "≈" say, the ceiling of a
//  correction, and the steps added "for next time" — and the probe's
//  caption, which speaks about the same next plan.
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
        // burn, and untrimmed the stepper would read "+10 s" over
        // a sentence that shows the plan "+5 s" shows.
        trimRaiseToWhatStillMoves()
        // The second door of the same channel, and it spends
        // the same one-way flag: the work screen's hint asks
        // people to say a number of their own, and correcting
        // a card here IS saying one. Without this call the
        // hint would go on being shown to somebody who has
        // already answered it.
        store.markOwnNumberReported()
        editing = nil
        persistProgress()
    }

    /// What the clock counted for a set — the number before any correction.
    /// A set no clock ran for (skipped mid-movement, restored from a snapshot
    /// written before the field) falls back to what the card shows.
    func summaryMeasured(set index: Int) -> Int {
        holdMeasured[index] ?? SetFacts.inForce(actuals, exercise, set: index)
    }

    /// The line above the panel: the set, and what was recorded for it —
    /// what the clock counted, or, for a set a thumb ended, the estimate it
    /// recorded (the clock less the reach allowance,
    /// `SetFacts.holdEndedByTap`). Chosen by the mark, not by the card's
    /// "≈": a correction changes the number on the card, not the fact that
    /// the clock never saw the estimate, and "the clock saw" about it would
    /// call a guess a measurement.
    func summaryPanelLine(set index: Int) -> String {
        let measured = summaryMeasured(set: index)
        return holdApproxSets.contains(index)
            ? String(localized: "set \(index + 1) · stopped by hand at about \(measured) s")
            : String(localized: "set \(index + 1) · the clock saw \(measured) s")
    }

    /// The card's "≈" and its "stopped by hand": a set a thumb ended, while
    /// the card still carries the number the thumb produced. A number the
    /// person put in its place is their own report, not a guess, and is
    /// printed as one; OK on the estimate, or a correction back to it,
    /// leaves the guess on the card, and the card says so.
    func summaryCardIsApproximate(set index: Int) -> Bool {
        holdApproxSets.contains(index)
            && SetFacts.inForce(actuals, exercise, set: index) == summaryMeasured(set: index)
    }

    /// The last WORKING set: the card the line under the row names, whether
    /// or not a probe came after it — the probe is a set of another movement
    /// and has no card here.
    func isLastSummarySet(_ index: Int) -> Bool { index == exercise.sets - 1 }

    /// The rule is `SetFacts.correctionRange`, where a test can reach it;
    /// what is measured is the CLOCK's number, not the card's — a card
    /// corrected downwards must be correctable back up to what was counted.
    /// Only the last set reaches this from the screen.
    ///
    /// A rest started on the signal of every set but the movement's very
    /// last one, its probe counted — so on this screen, on the last working
    /// set of a probing hold.
    func summaryRange(set index: Int) -> ClosedRange<Int> {
        SetFacts.correctionRange(measured: summaryMeasured(set: index),
                                 isLastSet: isLastSummarySet(index),
                                 restFollowed: index < totalSets - 1,
                                 endedByTap: holdApproxSets.contains(index))
    }

    /// The plan this movement will get with `steps` additions — the engine's
    /// own answer, dry-run through the store with everything this session
    /// has recorded so far.
    func nextPlan(withAdditions steps: Int) -> SessionExercise? {
        var raised = raisedSteps
        raised[exercise.pattern] = steps > 0 ? steps : nil
        return store.previewPlan(after: session, pattern: exercise.pattern,
                                 overrides: SetFacts.overrides(actuals, in: exercises),
                                 skipped: skippedPatterns, setsSkipped: setsSkipped,
                                 probes: probeActuals, raised: raised)
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

    // MARK: - The probe's caption

    /// What the probe set says under its number once one is in.
    enum ProbeOutcome: Equatable {
        /// The probe passed: next time is the probe's own movement.
        case passed(String)
        /// The working sets fell short, so the plan moves whatever the probe
        /// showed — onto the movement named.
        case planMoves(String)
        /// The probe fell short after working sets that met the plan.
        case stays
    }

    /// Decided here and not in the view: it is a promise about the next
    /// plan, and a rule stated inside a SwiftUI view is a rule no gating test
    /// can reach. Nil until a number is in for the probe.
    ///
    /// Working sets that fell short speak first (`SetFacts.foldFallsShort`):
    /// the engine reads that session as "hard" for the pattern, a hard
    /// pattern's probe does not count, and the plan steps down — so neither
    /// "next time: the probe's movement" nor "the plan stays" would be true.
    /// What the caption names instead is the movement of the plan it steps
    /// down to, off the summary's own preview, which stays true even when
    /// that plan is on another variation. The preview is nil only for a
    /// session the state no longer generates; the movement's own name is the
    /// most that can be said then.
    var probeOutcome: ProbeOutcome? {
        guard let entered = probeActuals[exercise.pattern] else { return nil }
        if SetFacts.foldFallsShort(actuals, of: exercise) {
            return .planMoves(nextPlan(withAdditions: 0)?.name ?? exercise.name)
        }
        return entered >= current.planned ? .passed(current.name) : .stays
    }
}
