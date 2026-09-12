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
                            .padding(.top, 22)
                        // ONE sentence, about the past, under the cards. It
                        // used to say "these are the numbers the next plan
                        // starts from", which is a sentence about the
                        // future — and people answered it in the future
                        // tense, entering the number they wanted next time
                        // into a card that records what was held. The future
                        // has its own block now.
                        Text(exercise.perSide
                             ? String(localized: "That is what counts, per side. Wrong number? Tap it and fix it.")
                             : String(localized: "That is what counts. Wrong number? Tap it and fix it."))
                            .dredfitFont(14)
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                            .padding(.horizontal, 8)
                            .accessibilityIdentifier("summary-counted")
                        // Stands down while a number is being entered: one
                        // thing to read at a time, the rule of every message
                        // slot in the flow.
                        if !adjusting {
                            NextTimeBlock(exercise: exercise,
                                          steps: raisedSteps[exercise.pattern] ?? 0,
                                          factEntered: SetFacts.override(actuals, for: exercise) != nil,
                                          preview: nextPlan(withAdditions:),
                                          onChange: setRaise)
                                .padding(.top, 22)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }

            // The entry opens in the slot of the button it will hand back to,
            // exactly as it does on the work screen — with the question it
            // is answering above it. The panel itself has no words, and
            // without any this was a stepper on a screen whose only sentence
            // invited planning; the past tense is what separates a
            // correction from a wish (§41.13).
            if adjusting, let index = summarySet {
                Text("How long was set \(index + 1) held?")
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("summary-question")
                AdjustPanel(value: $adjustValue, unit: .hold,
                            range: summaryRange(set: index)) {
                    actuals = SetFacts.recordingSet(adjustValue, in: actuals,
                                                    exercise, set: index)
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
                .padding(.bottom, summaryCeilingNote(set: index) == nil ? 18 : 8)
                // THE CLOCK IS THE CEILING on every set but the last
                // (`SetFacts.correctionRange`): the "+" above is dimmed at
                // it, and this says why — a dimmed control with no reason
                // is a control that looks broken.
                if let note = summaryCeilingNote(set: index) {
                    Text(note)
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 18)
                        .accessibilityIdentifier("summary-ceiling")
                }
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

    /// The rule is `SetFacts.correctionRange`, where a test can reach it;
    /// what is measured is what the card shows.
    func summaryRange(set index: Int) -> ClosedRange<Int> {
        SetFacts.correctionRange(measured: SetFacts.inForce(actuals, exercise, set: index),
                                 isLastSet: index == exercise.sets - 1)
    }

    /// The reason the "+" is dimmed, on the sets that have one.
    func summaryCeilingNote(set index: Int) -> String? {
        let range = summaryRange(set: index)
        guard range.upperBound < SetFacts.corridor(for: .hold).upperBound else { return nil }
        return String(localized: "the clock saw \(range.upperBound) s — no more than that goes in")
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
}
