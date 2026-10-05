//
//  The exercise summary as the phase shows it. Which cards there are, what a
//  tap on one writes and what the "next time" block asks the engine are
//  WorkoutSession's (+Summary); the leaves themselves are
//  ExerciseSummary.swift — what a card looks like is not what the phase
//  decides.
//

import SwiftUI
import DredfitCore

extension WorkoutFlowView {

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
                        HeldSetsRow(sets: flow.heldSets, onEdit: flow.startSummaryAdjusting)
                            // The row asks for its IDEAL height — the tallest
                            // card — and the cards stretch to it: without this
                            // the cards' `maxHeight: .infinity` would fill the
                            // whole scroll view instead of levelling the row.
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 22)
                        // ONE sentence, about the past, under the cards, in
                        // the words the app already uses for this act: "Went
                        // differently" is the control that corrects a set on
                        // the work screen, and the summary says the same
                        // thing about the same act. A sentence about the
                        // future here would be answered in the future tense,
                        // with the number wanted next time entered into a
                        // card that records what was held. The future has its
                        // own block.
                        //
                        // It names the LAST set because only the last set
                        // can be corrected: every earlier one ended on its
                        // signal or under a thumb, and the card carries that
                        // number as it ran. The reason is said as "stand as
                        // they ran", not "ended on the clock": a set stopped
                        // by hand is on this row too, marked ≈, and it did not
                        // end on the clock.
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
            // control the screen is about. While a number is being entered
            // the panel takes the slot and the block stands down: one thing
            // to read at a time, the rule of every message slot in the flow.
            if case .summaryCard(let index) = flow.editing {
                // Which set and what was recorded for it, said above the
                // panel. ONLY THE LAST SET OPENS THE PANEL. Down is always
                // the person's; up goes as far as nothing stopped the set —
                // the corridor when nothing followed it and they may have
                // kept holding, what the clock ran when the rest before a
                // probe started on its signal (`summaryRange`). Every earlier
                // card is inert (`HeldSetCard`): a panel whose "+" and "−"
                // are both dead reads as a broken control.
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
                              factEntered: SetFacts.override(flow.actuals, for: flow.exercise,
                                                             skipping: flow.leftOutHere) != nil,
                              preview: flow.nextPlan(withAdditions:),
                              onChange: flow.setRaise)
                    .padding(.bottom, 18)
            }

            // "Done", like every other tap that logs work in this app, and
            // the same identifier: it IS the same act — the movement is
            // finished when the person says its numbers are right. "Next
            // exercise" would name the LANDING rather than the act and rename
            // a control people have already learned; what comes next is the
            // flow's business, not the button's.
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
