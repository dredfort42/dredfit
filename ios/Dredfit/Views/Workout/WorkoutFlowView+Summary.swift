//
//  The flow's half of the exercise summary: what the phase shows, what the
//  tap on a card writes, and what the "next time" block asks the engine. The
//  leaves themselves are ExerciseSummary.swift — what a card looks like is
//  not what the phase decides.
//
//  A file of its own because WorkoutFlowView.swift is bounded at 1200 lines
//  by the lint as an ERROR, and it is the FILE that a split cures; an
//  extension only moves the other ceiling, the 600 a type's own body gets.
//  Swift's `private` is file-scoped, so what this reaches for is declared
//  without it, like the five siblings before it.
//

import SwiftUI
import DredfitCore

extension WorkoutFlowView {

    /// Every set of the movement as the screen prints it, in set order.
    ///
    /// `SetFacts.allSets` is the source deliberately: it is what the work
    /// screen showed for each set as it ran, so the summary and the flow
    /// cannot disagree about a number — and `recordingSet` freezes exactly
    /// this list before it changes one of them.
    var heldSets: [HeldSet] {
        SetFacts.allSets(actuals, exercise).enumerated().map { index, seconds in
            HeldSet(index: index, seconds: seconds,
                    planned: exercise.plannedLoad(set: index),
                    approximate: holdApproxSets.contains(index))
        }
    }

    var exerciseSummaryView: some View {
        VStack(spacing: 0) {
            // Centred while it fits, scrollable once it does not — five cards,
            // an accessibility text size and an iPhone SE are all real at the
            // same time, and a number that cannot be read is a number that
            // cannot be corrected. The pattern is the app's own (MilestoneView,
            // the rating screen); the spacers collapse as the content grows.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        summaryHead
                        HeldSetsRow(sets: heldSets, onEdit: startSummaryAdjusting)
                            // The row asks for its IDEAL height — the tallest
                            // card — and the cards stretch to it: without this
                            // the cards' `maxHeight: .infinity` filled the whole
                            // scroll view instead of levelling the row.
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 22)
                        // ONE sentence, about the past, under the cards, in
                        // the words the app already uses for this act: "Went
                        // differently" is the control that corrects a set on
                        // the work screen, and the summary says the same
                        // thing about the same act (owner, 12.09.2026). It
                        // used to say "these are the numbers the next plan
                        // starts from" — a sentence about the future, which
                        // people answered in the future tense, entering the
                        // number they wanted next time into a card that
                        // records what was held. The future has its own
                        // block now.
                        Text(exercise.perSide
                             ? String(localized: "Went differently? Tap and correct — the numbers are per side.")
                             : String(localized: "Went differently? Tap and correct."))
                            .dredfitFont(14)
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                            .padding(.horizontal, 8)
                            .accessibilityIdentifier("summary-counted")
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }

            // ONE SLOT above the button, two occupants. The "next time"
            // block stands there — the same distance from Done that the
            // entry panel keeps, because it is the same kind of thing: the
            // control the screen is about (owner, 12.09.2026; it used to
            // float under the cards with the whole spare height between it
            // and the button). While a number is being entered the panel
            // takes the slot and the block stands down: one thing to read at
            // a time, the rule of every message slot in the flow.
            if adjusting, let index = summarySet {
                // What the panel is standing on, said above it: which set,
                // and what the clock counted. On every set but the last the
                // clock is the ceiling (`SetFacts.correctionRange`) — the "+"
                // is dimmed at it, and this line is the reason, because a
                // dimmed control with no reason on screen looks broken. The
                // last set says only what was counted: nothing followed it,
                // and both directions are the person's.
                Text(summaryPanelLine(set: index))
                    .dredfitFont(14)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier(summaryRange(set: index).upperBound
                                             < SetFacts.corridor(for: .hold).upperBound
                                             ? "summary-ceiling" : "summary-panel-line")
                AdjustPanel(value: $adjustValue, unit: .hold,
                            range: summaryRange(set: index)) {
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
                    adjusting = false
                    summarySet = nil
                    persistProgress()
                }
                .padding(.bottom, 18)
            } else {
                NextTimeBlock(exercise: exercise,
                              steps: raisedSteps[exercise.pattern] ?? 0,
                              factEntered: SetFacts.override(actuals, for: exercise) != nil,
                              preview: nextPlan(withAdditions:),
                              onChange: setRaise)
                    .padding(.bottom, 18)
            }

            // "Done", like every other tap that logs work in this app, and
            // the same identifier: it IS the same act — the movement is
            // finished when the person says its numbers are right. It briefly
            // read "Next exercise" off the last set, which named the LANDING
            // rather than the act and so renamed a control people have already
            // learned; what comes next is the flow's business, not the
            // button's (owner, 01.09.2026).
            PrimaryButton(title: String(localized: "Done")) {
                leaveExerciseSummary()
            }
            .accessibilityIdentifier("exercise-done")
            .padding(.bottom, 10)

            // NO escapes. The movement is behind — there is no set left to
            // skip and nothing left to leave — and an escape here would offer
            // to throw away the numbers the screen is asking you to confirm.
            // The way out of the workout is Exit, in the header, as always.
        }
    }

    private var summaryHead: some View {
        VStack(spacing: 6) {
            // Named, like the probe badge it is shaped after, and for the
            // same reason twice over: `.textCase(.uppercase)` folds the
            // string the accessibility tree carries, so a query for the word
            // as written cannot match it at all — and a localized run could
            // not match it either way.
            Text("Held")
                .dredfitFont(11, weight: .heavy)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accentText)
                .accessibilityIdentifier("summary-held")
            Text(verbatim: exercise.name)
                .dredfitFont(23, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }

    /// Opens the entry on the card that was tapped, not on the set the flow
    /// happens to be standing on — the whole point of the screen is that any
    /// of them can be corrected.
    func startSummaryAdjusting(set index: Int) {
        summarySet = index
        adjustValue = SetFacts.inForce(actuals, exercise, set: index)
        adjusting = true
    }

    /// What the clock counted for a set — the number before any correction.
    /// A set no clock ran for (skipped mid-movement, restored from a snapshot
    /// written before the field) falls back to what the card shows, which is
    /// what the ceiling used to be read off for every set.
    func summaryMeasured(set index: Int) -> Int {
        holdMeasured[index] ?? SetFacts.inForce(actuals, exercise, set: index)
    }

    /// The rule is `SetFacts.correctionRange`, where a test can reach it;
    /// what is measured is the CLOCK's number, not the card's — a card
    /// corrected downwards must be correctable back up to what was counted.
    func summaryRange(set index: Int) -> ClosedRange<Int> {
        SetFacts.correctionRange(measured: summaryMeasured(set: index),
                                 isLastSet: index == exercise.sets - 1)
    }

    /// The line above the panel: the set, what the clock counted, and — on
    /// every set but the last — that nothing above it goes in.
    func summaryPanelLine(set index: Int) -> String {
        let measured = summaryMeasured(set: index)
        let range = summaryRange(set: index)
        return range.upperBound < SetFacts.corridor(for: .hold).upperBound
            ? String(localized: "set \(index + 1) · the clock saw \(measured) s — no more than that goes in")
            : String(localized: "set \(index + 1) · the clock saw \(measured) s")
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
