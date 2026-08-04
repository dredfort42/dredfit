//
//  FeedbackView.swift
//  Dredfit
//
//  One tap to rate the workout. The rating applies to all non-adjusted,
//  non-skipped exercises; per-exercise actuals override it for theirs.
//

import SwiftUI
import DredfitCore

struct FeedbackView: View {
    let session: Session
    let actuals: [Pattern: Int]
    var skipped: Set<Pattern> = []
    /// To the engine a skip like the others; the label says "not finished".
    var interrupted: Pattern?
    /// A memory aid, not a default: no card is pre-selected.
    var lastResult: FeedbackResult?
    let onComplete: (FeedbackResult, [Pattern: Int]) -> Void

    var body: some View {
        // Centred while it fits, scrollable once it doesn't: a fixed VStack
        // would clip the mandatory rating step at accessibility sizes.
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
                        if !skipped.isEmpty {
                            Text(scopeLine)
                                .dredfitFont(13)
                                .foregroundStyle(Theme.ink2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 18)

                    Spacer(minLength: 20)

                    // Three EQUAL cards: a highlighted "On plan" would read
                    // as "the correct answer is the middle one" and an
                    // agreeable user would pick it over the honest one.
                    // Captions promise a direction, never an amount — one
                    // caption cannot be exact for six exercises at once.
                    VStack(spacing: 14) {
                        optionCard(title: String(localized: "Tough, did less"),
                                   caption: String(localized: "next workout eases off"),
                                   result: .less)
                        optionCard(title: String(localized: "On plan"),
                                   caption: String(localized: "the next one asks a little more"),
                                   result: .plan)
                        optionCard(title: String(localized: "Easy, could do more"),
                                   caption: String(localized: "progress comes twice as fast"),
                                   result: .more)
                    }

                    if let lastResult {
                        Text("Last time you chose: \(lastChoiceTitle(lastResult))")
                            .dredfitFont(11.5)
                            .foregroundStyle(Theme.ink3)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
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

    // MARK: - Read-only summary of in-workout adjustments

    private var adjustedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !actuals.isEmpty {
                Kicker(text: String(localized: "Adjusted"))
            }
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
            if !skipped.isEmpty {
                Kicker(text: String(localized: "feedback.skipped", defaultValue: "Skipped"))
                    .padding(.top, actuals.isEmpty ? 0 : 8)
            }
            ForEach(session.exercises.filter { skipped.contains($0.pattern) }) { ex in
                HStack {
                    // VoiceOver keeps what sighted users get from the header:
                    // the name's label carries the state, so nothing only
                    // LOOKS dimmed.
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                        .foregroundStyle(Theme.ink3)
                        .accessibilityLabel(ex.pattern == interrupted
                            ? Text("\(ex.name), not finished")
                            : Text("\(ex.name), skipped"))
                    Spacer()
                    if ex.pattern == interrupted {
                        Text("not finished")
                            .dredfitFont(14, weight: .semibold)
                            .foregroundStyle(Theme.ink2)
                            .accessibilityHidden(true)   // the label above already says it
                    }
                }
            }
            if skipped.isEmpty {
                Text("Your rating applies to the rest")
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Adjusted exercises follow their actual number, not the rating (see
    /// Engine.applyFeedback), so they are outside the scope too.
    private var scopeLine: String {
        let adjusted = session.exercises.filter {
            actuals[$0.pattern] != nil && !skipped.contains($0.pattern)
        }.count
        let applies = session.exercises.count - skipped.count - adjusted
        let total = session.exercises.count
        if skipped.count == 1,
           let ex = session.exercises.first(where: { skipped.contains($0.pattern) }) {
            // Must not contradict the summary card on the same screen.
            return ex.pattern == interrupted
                ? String(localized: "Applies to \(applies) of \(total) — \(ex.name) not finished, stays put")
                : String(localized: "Applies to \(applies) of \(total) — \(ex.name) skipped, stays put")
        }
        return String(localized: "Applies to \(applies) of \(total) — skipped exercises stay put")
    }

    private func lastChoiceTitle(_ result: FeedbackResult) -> String {
        switch result {
        case .less: return String(localized: "Tough, did less")
        case .plan: return String(localized: "On plan")
        case .more: return String(localized: "Easy, could do more")
        }
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
