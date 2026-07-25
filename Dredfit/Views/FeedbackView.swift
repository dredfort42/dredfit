//
//  FeedbackView.swift
//  Dredfit
//
//  The heart of the "thermostat": one tap to rate the workout.
//
//  Actuals arrive already collected during the workout (see WorkoutFlowView)
//  and show here as a read-only summary; the chosen rating applies to all
//  non-adjusted exercises, per-exercise actuals override it for theirs.
//  Skipped exercises are listed too — the rating does not apply to them
//  (the engine keeps their level unchanged).
//

import SwiftUI
import DredfitCore

struct FeedbackView: View {
    let session: Session
    let actuals: [Pattern: Int]
    var skipped: Set<Pattern> = []
    /// The exercise "Finish now" cut mid-way. To the engine it is a skip like
    /// the others; to the person who did 24 push-ups of 36 it is "not
    /// finished", and the summary label says so.
    var interrupted: Pattern? = nil
    /// The rating chosen after the previous workout — a memory aid, not a
    /// default: no card is pre-selected, the scale still has to be answered.
    var lastResult: FeedbackResult? = nil
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
                        // The rating's scope, stated before the choice, not in
                        // a footnote after it: skipped exercises sit this one
                        // out, and the person deciding should know that now.
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

                    // Three equal cards on purpose: the rating is the
                    // regulator's only input, and a filled "On plan" card
                    // reads as "the correct answer is the middle one" — an
                    // agreeable user would pick the highlighted card over the
                    // honest one. Order alone carries the scale.
                    // Captions say what the answer does in workout terms, not
                    // in regulator constants — "+1 step" is the engine's
                    // vocabulary, "one more rep" is the user's.
                    // Directional promises only: "+1" means one more rep on an
                    // ordinary level, a new variation at a band boundary, +5 s
                    // on a hold — one caption can't be exact for six exercises
                    // at once, so it says where the plan moves, not by what.
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
            // With skips the scope chip under the title already said this;
            // repeating it here would be the footnote the chip replaced.
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

    /// "Applies to 5 of 6 — Plank skipped, stays put": the count, and — when a
    /// single exercise sat out — its name; several skips get the plural form.
    /// Adjusted exercises follow their actual number, not the rating (see
    /// Engine.applyFeedback), so they are outside the rating's scope too.
    private var scopeLine: String {
        let adjusted = session.exercises.filter {
            actuals[$0.pattern] != nil && !skipped.contains($0.pattern)
        }.count
        let applies = session.exercises.count - skipped.count - adjusted
        let total = session.exercises.count
        if skipped.count == 1,
           let ex = session.exercises.first(where: { skipped.contains($0.pattern) }) {
            // The one exercise "Finish now" cut mid-way is "not finished", not
            // "skipped" — the summary card below says so, and the chip must
            // not contradict it on the same screen.
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
