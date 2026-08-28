//
//  One tap to rate the workout. The rating applies to all non-adjusted,
//  non-skipped exercises; an exercise's own facts override it for theirs.
//
//  "Easy, could do more" is the exception: it is offered only for a plan
//  finished in full. The engine already keeps that rating away from a skipped
//  exercise and from one carrying its own number, but NOT from a movement that
//  lost a set — there the tap still buys the full +2 on the dose. The card is
//  the cheapest place to close that, and the only one that can also say why.
//

import SwiftUI
import DredfitCore

struct FeedbackView: View {
    let session: Session
    /// Per-set, as the flow recorded them. The single number each one
    /// collapses to for the engine is `overrides` below — computed here so
    /// the screen and the engine can never be shown different arithmetic.
    let facts: SetFacts.PerSet
    /// Sets dropped mid-movement. Never reaches `overrides` — a skipped set
    /// is a statement about volume, not about the dose — so it is the one
    /// shortfall the rating still governs at full speed, and the only reason
    /// this screen needs it (see `didFullPlan`).
    var setsSkipped: SetFacts.Skips = [:]
    var skipped: Set<Pattern> = []
    /// To the engine a skip like the others; the label says "not finished".
    var interrupted: Pattern?
    let onComplete: (FeedbackResult, [Pattern: Double]) -> Void

    private var overrides: [Pattern: Double] {
        SetFacts.overrides(facts, in: session.exercises)
    }

    /// Whether "easy" is on offer. The rule itself is `SetFacts.didFullPlan`,
    /// where a test can reach it.
    private var didFullPlan: Bool {
        SetFacts.didFullPlan(facts, skips: setsSkipped, skipped: skipped,
                             in: session.exercises)
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
                                   result: .less, enabled: true)
                        optionCard(title: String(localized: "On plan"),
                                   caption: String(localized: "the next one adds a step to the movements that have room for one"),
                                   result: .plan, enabled: true)
                        // The one rating that claims MORE than the plan is the
                        // one the plan has to have been finished for. The other
                        // two stay live in every state: honesty downward is
                        // never gated, and "on plan" is the truth about a
                        // session that fell short of nothing it recorded.
                        optionCard(title: String(localized: "Easy, could do more"),
                                   caption: String(localized: "the next one asks as much more as each movement allows"),
                                   result: .more, enabled: didFullPlan)
                    }

                    // Why the card is spent. A dimmed control on a screen with
                    // no way out is a riddle otherwise — and the sentence has
                    // to name the way back, not just the refusal.
                    //
                    // CENTRED, and against the rest of this left-aligned
                    // screen: centred under the three cards it reads as a
                    // caption for the group, while flush left it read as a
                    // stray paragraph. An icon was the other candidate and is
                    // wrong here — `info.circle` already means "tap me for the
                    // explainer" in this app (TodayView, TechniqueButton), and
                    // this line opens nothing.
                    if !didFullPlan {
                        Text(easyGateReason)
                            .dredfitFont(13)
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .center)
                            // The cards run to the column's edge; a wrapped
                            // second line must not, or the caption stops
                            // reading as one.
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
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
                    // §41.3: the screen shows a whole number. The fraction is
                    // how the engine decides whether the top set was taken; a
                    // person reading "you did 7.33" would learn nothing.
                    SetFactsLabel(values: SetFacts.allSets(facts, ex),
                                  reported: Int((overrides[ex.pattern] ?? 0).rounded()))
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
                // Names the RATING, which is the thing the reader is about to
                // press, and says the outcome. It read "These keep their place
                // either way" and needed explaining (owner, 27.08.2026): a
                // bare plural demonstrative over a list that usually holds ONE
                // movement, "their place" in nothing the screen names, and the
                // part that matters — whichever of the three cards you choose
                // — folded into an idiom. "These movements" also covers the
                // row that says "not finished", which is in this list too.
                Text("The rating doesn't apply to these — they stay as they were.")
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

    /// One sentence, shared by the line under the cards and by the dimmed
    /// card's hint: VoiceOver announces "dimmed" and stops, so the reason has
    /// to travel with the control as well as beside it.
    private var easyGateReason: String {
        String(localized: "“Easy, could do more” is for a workout done in full.")
    }

    /// `enabled` is passed at every call site rather than defaulted: an
    /// omitted gate argument is the defect class this project has already
    /// paid for twice, and a compile error is a stronger guard than a grep.
    private func optionCard(title: String, caption: String,
                            result: FeedbackResult, enabled: Bool) -> some View {
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
        .disabled(!enabled)
        // Derived from the RESULT rather than passed in, so a fourth card
        // could not be added with a copied identifier. Every walk that ends a
        // workout taps one of these three, and until now all of them reached
        // for the English caption.
        .accessibilityIdentifier("rating-\(result.rawValue)")
        // `.disabled` alone changes nothing on a custom label — the same trap
        // the rest extension records. The card has to LOOK spent while keeping
        // its place, so the three stay a set of three rather than a gap.
        .opacity(enabled ? 1 : 0.35)
        // `verbatim`, not a literal: `Text("")` is a localizable string to the
        // extractor, and an empty key in the catalog fails the Localization
        // check for all six languages at once.
        .accessibilityHint(enabled ? Text(verbatim: "") : Text(easyGateReason))
    }
}
