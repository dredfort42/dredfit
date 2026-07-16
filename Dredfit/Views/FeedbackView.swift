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

import SwiftUI
import DredfitCore

struct FeedbackView: View {
    let session: Session
    let actuals: [Pattern: Int]
    let onComplete: (FeedbackResult, [Pattern: Int]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: String(localized: "Workout \(session.sessionNumber)"))
                Text("How did it go?")
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(-0.5)
                Text("One tap — the next workout adapts")
                    .font(.system(size: 15))
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

            Spacer()

            if !actuals.isEmpty {
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
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("actual \(actuals[ex.pattern] ?? 0)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
            }
            Text("Your rating applies to the rest")
                .font(.system(size: 12.5))
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(primary ? .white : Theme.ink)
                    Text(caption)
                        .font(.system(size: 13))
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
