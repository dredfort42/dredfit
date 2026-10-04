//
//  The exercise summary as the phase shows it. What a tap on a card writes
//  and what the "next time" block asks the engine are WorkoutSession's
//  (+Summary); the leaves themselves are ExerciseSummary.swift — what a card
//  looks like is not what the phase decides.
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
        SetFacts.allSets(flow.actuals, flow.exercise).enumerated().map { index, seconds in
            HeldSet(index: index, seconds: seconds,
                    planned: flow.exercise.plannedLoad(set: index),
                    approximate: flow.summaryCardIsApproximate(set: index))
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
                        HeldSetsRow(sets: heldSets, onEdit: flow.startSummaryAdjusting)
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
                        //
                        // It names the LAST set because only the last set
                        // can be corrected: every earlier one ended on its
                        // signal or under a thumb, and the card carries that
                        // number as it ran (owner, 13.09.2026). The reason
                        // is said as "stand as they ran", not "ended on the
                        // clock": a set stopped by hand is on this row too,
                        // marked ≈, and it did not end on the clock.
                        // One literal per key, because the literal is the key.
                        Text(flow.exercise.perSide
                             // swiftlint:disable:next line_length
                             ? String(localized: "Went differently? Tap the last set and correct — the numbers are per side, and the others stand as they ran.")
                             : String(localized: "Went differently? Tap the last set and correct — the others stand as they ran."))
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
            if case .summaryCard(let index) = flow.editing {
                // Which set and what was recorded for it, said above the
                // panel. ONLY THE LAST SET OPENS THE PANEL: nothing followed
                // it and the person may have kept holding, so both directions
                // are theirs. Every earlier card is inert (`HeldSetCard`) — a
                // panel whose "+" and "−" were dead at the floor read as a
                // broken control (owner, 13.09.2026).
                Text(flow.summaryPanelLine(set: index))
                    .dredfitFont(14)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("summary-panel-line")
                AdjustPanel(value: $flow.adjustValue, unit: .hold,
                            range: flow.summaryRange(set: index)) {
                    flow.commitSummaryEdit(set: index)
                }
                .padding(.bottom, 18)
            } else {
                NextTimeBlock(exercise: flow.exercise,
                              steps: flow.raisedSteps[flow.exercise.pattern] ?? 0,
                              factEntered: SetFacts.override(flow.actuals, for: flow.exercise) != nil,
                              preview: flow.nextPlan(withAdditions:),
                              onChange: flow.setRaise)
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
                flow.leaveExerciseSummary()
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
            Text(verbatim: flow.exercise.name)
                .dredfitFont(23, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }

}
