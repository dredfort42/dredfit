//
//  One tap to rate the workout. The rating applies to all non-adjusted,
//  non-skipped exercises; an exercise's own facts override it for theirs.
//

import SwiftUI
import DredfitCore

struct FeedbackView: View {
    let session: Session
    /// Per-set, as the flow recorded them. The single number each one
    /// collapses to for the engine is `overrides` below — computed here so
    /// the screen and the engine can never be shown different arithmetic.
    let facts: SetFacts.PerSet
    var skipped: Set<Pattern> = []
    /// To the engine a skip like the others; the label says "not finished".
    var interrupted: Pattern?
    let onComplete: (FeedbackResult, [Pattern: Int]) -> Void

    private var overrides: [Pattern: Int] {
        SetFacts.overrides(facts, in: session.exercises)
    }

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
                    }
                    .padding(.top, 18)

                    Spacer(minLength: 20)

                    // Three EQUAL cards: a highlighted "On plan" would read
                    // as "the correct answer is the middle one" and an
                    // agreeable user would pick it over the honest one.
                    //
                    // Captions promise a DIRECTION, never an amount. "Easy"
                    // used to promise double speed; that is no longer true —
                    // EngineConfig.maxUpByPatternTier caps growth per movement
                    // and per variation, so a session made of fourth
                    // variations climbs exactly like "on plan". The size is
                    // knowable only after the feedback is applied, because it
                    // depends on what the session was made of, which is why no
                    // caption here can be exact for six exercises at once.
                    VStack(spacing: 14) {
                        optionCard(title: String(localized: "Tough, did less"),
                                   caption: String(localized: "next workout eases off"),
                                   result: .less)
                        optionCard(title: String(localized: "On plan"),
                                   caption: String(localized: "the next one asks a little more"),
                                   result: .plan)
                        optionCard(title: String(localized: "Easy, could do more"),
                                   caption: String(localized: "the next one asks as much more as each movement allows"),
                                   result: .more)
                    }

                    Spacer(minLength: 20)

                    if !overrides.isEmpty || !skipped.isEmpty {
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
            // The card is the only place that states the rating's scope. A
            // banner above the cards used to say the same thing, and two
            // elements under a standing order never to contradict each other
            // are one element that got split.
            Text("Your rating applies to \(applies) of \(total)")
                .dredfitFont(13, weight: .semibold)
                .foregroundStyle(Theme.ink2)
            ForEach(session.exercises.filter { overrides[$0.pattern] != nil }) { ex in
                HStack {
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                    Spacer()
                    SetFactsLabel(values: SetFacts.allSets(facts, ex),
                                  reported: overrides[ex.pattern] ?? 0)
                }
            }
            // The "Discomfort" section is gone with the input that filled it.
            // Nothing is set aside for pain any more — a movement the person
            // found too hard is either skipped or done at the number they
            // actually managed.
            if !skipped.isEmpty {
                Kicker(text: String(localized: "feedback.skipped", defaultValue: "Skipped"))
                    .padding(.top, 8)
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
            if !skipped.isEmpty {
                Text("These keep their place either way.")
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Adjusted exercises follow their actual number, not the rating (see
    /// Engine.applyFeedback), so they are outside the scope too. The
    /// arithmetic is the banner's, unchanged: the session minus what was set
    /// aside minus what carries its own number.
    private var adjusted: Int {
        session.exercises.filter {
            overrides[$0.pattern] != nil && !skipped.contains($0.pattern)
        }.count
    }

    private var applies: Int { session.exercises.count - skipped.count - adjusted }

    private var total: Int { session.exercises.count }

    private func optionCard(title: String, caption: String,
                            result: FeedbackResult) -> some View {
        Button {
            onComplete(result, overrides)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .dredfitFont(18, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                    // A button's label centres its own multiline text, so a
                    // caption that wraps stops agreeing with the title above
                    // it. Stated rather than inherited.
                    Text(caption)
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.bg)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.hairline, lineWidth: 1.5))
            )
        }
    }
}
