//
//  The flow's half of the exercise summary: what the phase shows, and what
//  the tap on a card writes. The cards themselves are ExerciseSummary.swift —
//  what a card looks like is not what the phase decides.
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
                        HeldSetsRow(sets: heldSets, unevenPlan: exercise.loads != nil,
                                    onEdit: startSummaryAdjusting)
                            .padding(.top, 22)
                        summaryPlanLine
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }

            // The same slot the work screen keeps for its messages, and the
            // same rule: one thing to read at a time, so the sentence stands
            // down while a number is being entered.
            if !adjusting {
                Text("These are the numbers the next plan starts from.")
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                    .accessibilityIdentifier("summary-starts-from")
            }

            // The entry opens in the slot of the button it will hand back to,
            // exactly as it does on the work screen.
            if adjusting {
                AdjustPanel(value: $adjustValue, unit: .hold) {
                    if let index = summarySet {
                        actuals = SetFacts.recordingSet(adjustValue, in: actuals,
                                                        exercise, set: index)
                        // A number the person typed is not an estimate any
                        // more, whatever produced the one it replaced.
                        holdApproxSets.remove(index)
                    }
                    adjusting = false
                    summarySet = nil
                    persistProgress()
                }
                .padding(.bottom, 18)
            }

            // Same identifier as the tap that logs a set of reps, because it
            // is the same act: the movement is finished when the person says
            // its numbers are right.
            PrimaryButton(title: isLastExercise
                          ? String(localized: "Done")
                          : String(localized: "Next exercise")) {
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

    /// The plan, and the invitation to argue with the numbers above it.
    ///
    /// "each" is held back on an UNEVEN plan, where it would be false: 9-8-8
    /// asks different things of different sets, and the cards carry their own
    /// planned figure there instead.
    @ViewBuilder
    private var summaryPlanLine: some View {
        VStack(spacing: 6) {
            if exercise.loads == nil {
                Text("planned \(exercise.load) s each")
                    .dredfitFont(14)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
            }
            // ink2, not ink3. ink3 is a floor of 3:1 on `bg` by design — the
            // palette keeps it for quiet GRAPHICS — and this is small text
            // that has to be read, which needs 4.5 (BrandPaletteTests).
            Text("tap a number to change it")
                .dredfitFont(13)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.top, 18)
    }

    /// Opens the entry on the card that was tapped, not on the set the flow
    /// happens to be standing on — the whole point of the screen is that any
    /// of them can be corrected.
    func startSummaryAdjusting(set index: Int) {
        summarySet = index
        adjustValue = SetFacts.inForce(actuals, exercise, set: index)
        adjusting = true
    }
}
