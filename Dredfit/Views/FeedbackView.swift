//
//  FeedbackView.swift
//  Dredfit
//
//  The heart of the "thermostat": one tap to rate the workout.
//
//  UPDATE-5: actuals arrive already collected during the workout (see
//  WorkoutFlowView). This screen shows them as a read-only summary; the
//  chosen rating applies to all non-adjusted exercises, per-exercise
//  actuals override it for theirs. The separate adjustment sheet is gone.
//
//  v1.1: skipped exercises are listed too — the rating does not apply to
//  them (the engine keeps their level unchanged).
//

import SwiftUI
import DredfitCore

struct FeedbackView: View {
    let session: Session
    let actuals: [Pattern: Int]
    var skipped: Set<Pattern> = []
    /// The exercise "Finish now" cut mid-way (v1.7). To the engine it is a
    /// skip like the others; to the person who did 24 push-ups of 36 it is
    /// "not finished", and the summary label says so.
    var interrupted: Pattern? = nil
    let onComplete: (FeedbackResult, [Pattern: Int]) -> Void

    var body: some View {
        // Centred while it fits, scrollable once it doesn't (the MilestoneView
        // construction): at accessibility text sizes the header plus three
        // cards outgrow the screen, and a fixed VStack would clip the
        // mandatory rating step instead of scrolling it.
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: String(localized: "Workout \(session.sessionNumber)"))
                        Text("How did it go?")
                            .dredfitFont(32, weight: .heavy)
                            .tracking(-0.5)
                        Text("One tap — the next workout adapts")
                            .dredfitFont(15)
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.top, 18)

                    Spacer(minLength: 20)

                    // Three equal cards on purpose (v1.7): the rating is the
                    // regulator's only input, and a filled "On plan" card read
                    // as "the correct answer is the middle one" — an
                    // agreeable user would pick the highlighted card over the
                    // honest one. Order alone carries the scale.
                    VStack(spacing: 14) {
                        optionCard(title: String(localized: "Tough, did less"),
                                   caption: String(localized: "the next one will be easier"),
                                   result: .less)
                        optionCard(title: String(localized: "On plan"),
                                   caption: String(localized: "next: +1 step"),
                                   result: .plan)
                        optionCard(title: String(localized: "Easy, could do more"),
                                   caption: String(localized: "next: +2 steps"),
                                   result: .more)
                    }

                    Spacer(minLength: 20)

                    if !actuals.isEmpty || !skipped.isEmpty {
                        adjustedSummary
                            .padding(.bottom, 24)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            }
        }
    }

    // MARK: - Read-only summary of in-workout adjustments (UPDATE-5)

    private var adjustedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: String(localized: "Adjusted"))
            ForEach(session.exercises.filter { actuals[$0.pattern] != nil }) { ex in
                HStack {
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                    Spacer()
                    Text("actual \(actuals[ex.pattern] ?? 0)")
                        .dredfitFont(14, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                }
            }
            ForEach(session.exercises.filter { skipped.contains($0.pattern) }) { ex in
                HStack {
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    // ink2 for the state word: the dimmed name signals
                    // exclusion, but WHY it is dimmed has to stay readable.
                    Text(ex.pattern == interrupted
                         ? String(localized: "not finished")
                         : String(localized: "skipped"))
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.ink2)
                }
            }
            Text("Your rating applies to the rest")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
    }

    private func optionCard(title: String, caption: String,
                            result: FeedbackResult) -> some View {
        Button {
            onComplete(result, actuals)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .dredfitFont(18, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                    // ink2, not ink3: what the answer will DO to the next
                    // plan is information, not decoration.
                    Text(caption)
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.hairline, lineWidth: 1.5))
            )
        }
    }
}
