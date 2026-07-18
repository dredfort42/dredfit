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
    /// v1.5: true when the journal was empty before this session. Calibration
    /// only fires from a zero level, so the hint is worth showing exactly once.
    var isFirstWorkout = false
    let onComplete: (FeedbackResult, [Pattern: Int]) -> Void

    var body: some View {
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

            Spacer()

            VStack(spacing: 14) {
                optionCard(title: String(localized: "Tough, did less"),
                           caption: String(localized: "the next one will be easier"),
                           result: .less, primary: false)
                optionCard(title: String(localized: "On plan"),
                           caption: String(localized: "next: +1 rep"),
                           result: .plan, primary: true)
                optionCard(title: String(localized: "Easy, could do more"),
                           caption: String(localized: "next: +2 reps"),
                           result: .more, primary: false)
            }

            // v1.5: the one moment where an exact number is worth more than a
            // rating — from zero it sets the level outright instead of moving
            // it by two. Only shown when there is no exact number yet.
            if isFirstWorkout && actuals.isEmpty {
                Text("Came out well above the plan? Open the list and put in what you actually did — the system will land on your level right away.")
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            Spacer()

            if !actuals.isEmpty || !skipped.isEmpty {
                adjustedSummary
                    .padding(.bottom, 24)
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
                        .foregroundStyle(Theme.accent)
                }
            }
            ForEach(session.exercises.filter { skipped.contains($0.pattern) }) { ex in
                HStack {
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    Text("skipped")
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.ink3)
                }
            }
            Text("Your rating applies to the rest")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
    }

    private func optionCard(title: String, caption: String,
                            result: FeedbackResult, primary: Bool) -> some View {
        Button {
            onComplete(result, actuals)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .dredfitFont(18, weight: .semibold)
                        .foregroundStyle(primary ? .white : Theme.ink)
                    Text(caption)
                        .dredfitFont(13)
                        .foregroundStyle(primary ? .white.opacity(0.55) : Theme.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(primary ? .white.opacity(0.6) : Theme.ink3)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(primary ? Theme.ink : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(primary ? Theme.ink : Theme.hairline, lineWidth: 1.5))
            )
        }
    }
}
