//
//  One tap to rate the workout. The rating applies to all non-adjusted,
//  non-skipped exercises; an exercise's own facts override it for theirs.
//
//  "Easy, could do more" is the exception: it is offered only for a plan
//  finished in full. The engine already keeps that rating away from a skipped
//  exercise and from one carrying its own number, but NOT from a movement that
//  lost a set — there the tap still buys the "more" step on the dose. The card
//  is the cheapest place to close that, and the only one that can also say
//  why.
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
    /// The ones among those the person skipped: the fold and the "actual"
    /// row leave them out.
    var skippedSets: SetFacts.SkippedSets = [:]
    var skipped: Set<Pattern> = []
    /// Steps added "for next time" on the summaries of the holds behind.
    /// Shown so the decision is seen to have reached the rating
    /// — it lands after it, through the engine, and nothing here changes it.
    var raised: [Pattern: Int] = [:]
    /// To the engine a skip like the others; the label says "not finished".
    var interrupted: Pattern?
    let onComplete: (FeedbackResult, [Pattern: Double]) -> Void

    private var overrides: [Pattern: Double] {
        SetFacts.overrides(facts, skipping: skippedSets, in: session.exercises)
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
                    // Captions promise a DIRECTION, never an amount.
                    // `EngineConfig.maxUp` caps growth per movement and per
                    // variation, so where the ceiling is one step "easy"
                    // climbs exactly like "on plan". The size is knowable only
                    // after the feedback is applied, because it depends on
                    // what the session was made of, which is why no caption
                    // here can be exact for six exercises at once.
                    //
                    // They also share a SHAPE and a register: all three say
                    // what the next workout does AND where. An unnamed "less"
                    // moves ONE movement (`Engine.lessTargets`) until the
                    // third in a row, so a caption naming the whole workout
                    // would be one a person could check the next morning and
                    // find false.
                    VStack(spacing: 14) {
                        optionCard(title: String(localized: "Tough, did less"),
                                   caption: String(localized: "the next one eases off where it's hardest"),
                                   result: .less, enabled: true)
                        optionCard(title: String(localized: "On plan"),
                                   caption: String(localized: "the next one adds a step where there's room"),
                                   result: .plan, enabled: true)
                        // The one rating that claims MORE than the plan is the
                        // one the plan has to have been finished for. The other
                        // two stay live in every state: honesty downward is
                        // never gated, and "on plan" is the truth about a
                        // session that fell short of nothing it recorded.
                        optionCard(title: String(localized: "Easy, could do more"),
                                   caption: String(localized: "the next one adds as much as each movement allows"),
                                   result: .more, enabled: didFullPlan)
                    }

                    // Why the card is spent. A dimmed control on a screen with
                    // no way out is a riddle otherwise — and the sentence has
                    // to name the way back, not just the refusal.
                    //
                    // CENTRED, and against the rest of this left-aligned
                    // screen: centred under the three cards it reads as a
                    // caption for the group, while flush left it would read as
                    // a stray paragraph. An icon is wrong here — `info.circle`
                    // already means "tap me for the explainer" in this app
                    // (`TechniqueButton`), and this line opens nothing.
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

                    if !overrides.isEmpty || !skipped.isEmpty || !trainedShort.isEmpty
                        || !raisedRows.isEmpty {
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
            // The card is the only place that states the rating's scope: a
            // second statement of it would be one more thing to keep from
            // contradicting this one.
            Text("Your rating applies to \(applies) of \(total)")
                .dredfitFont(13, weight: .semibold)
                .foregroundStyle(Theme.ink2)
            ForEach(session.exercises.filter { overrides[$0.pattern] != nil }) { ex in
                HStack {
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                    Spacer()
                    // The screen shows a whole number. The fraction is
                    // how the engine decides whether the top set was taken; a
                    // person reading "you did 7.33" would learn nothing.
                    SetFactsLabel(values: SetFacts.performed(facts, ex,
                                                             skipping: skippedSets[ex.pattern] ?? [])
                                    .map(\.value),
                                  reported: Int((overrides[ex.pattern] ?? 0).rounded()))
                }
            }
            // A movement that lost a set, and how much came off it: without
            // these rows the "Easy" card would go dim with its reason
            // unnamed, and a workout whose only shortfall was a dropped set
            // would build no summary at all.
            //
            // ABOVE the "Skipped" block, not inside it: the sentence that
            // closes that block says the rating does NOT apply to what is
            // listed there, and a movement that lost a set is governed by the
            // rating like any other — it is inside `applies`.
            if !trainedShort.isEmpty {
                Kicker(text: String(localized: "Sets skipped"))
                    .padding(.top, 8)
            }
            ForEach(trainedShort) { ex in
                HStack {
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                    Spacer()
                    // "1 of 3" under a header that says SETS SKIPPED: the
                    // loss and the size of the movement in one figure, and
                    // no plural to inflect in any of the seven languages.
                    Text(String(localized: "feedback.setsSkipped.count",
                                defaultValue: "\(setsLost(ex)) of \(ex.sets)"))
                        .dredfitFont(14, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                }
                // The header is a separate element to VoiceOver, so the row
                // has to carry the word "skipped" itself.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text("\(ex.name), \(setsLost(ex)) of \(ex.sets) sets skipped"))
            }
            // The additions, named where the rating is given: a person who
            // added five seconds on a summary three movements ago should
            // see here that the decision is still standing, and not have to
            // find out from tomorrow's plan.
            if !raisedRows.isEmpty {
                Kicker(text: String(localized: "Your additions"))
                    .padding(.top, 8)
            }
            ForEach(raisedRows) { ex in
                HStack {
                    Text(ex.name)
                        .dredfitFont(14, weight: .medium)
                    Spacer()
                    Text(verbatim: RaiseLabel.text(steps: raised[ex.pattern] ?? 0, unit: ex.unit))
                        .dredfitFont(14, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(ex.name), "
                    + RaiseLabel.spoken(steps: raised[ex.pattern] ?? 0, unit: ex.unit)))
                .accessibilityIdentifier("feedback-raised-\(ex.pattern.rawValue)")
            }
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
                        // ink2, not ink3: on `cardBG` ink3 comes to ≈2.2:1 in
                        // light, and 14 pt is small text, where the floor is
                        // 4.5 — a set-aside movement is meant to read quieter,
                        // not to be the one name on the screen a person has to
                        // squint at. The state is said without dimming: by the
                        // "Skipped" header above, the label below and, for an
                        // interrupted movement, the "not finished" tag.
                        .foregroundStyle(Theme.ink2)
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
                // press, and says the outcome. "These movements" also covers
                // the row that says "not finished", which is in this list too.
                Text("The rating doesn't apply to these movements — they stay as they were.")
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Adjusted exercises follow their actual number, not the rating (see
    /// Engine.applyFeedback), so they are outside the scope too: the session
    /// minus what was set aside minus what carries its own number.
    private var adjusted: Int {
        session.exercises.filter {
            overrides[$0.pattern] != nil && !skipped.contains($0.pattern)
        }.count
    }

    private var applies: Int { session.exercises.count - skipped.count - adjusted }

    /// Movements trained short of their sets. A movement that was LEFT is
    /// excluded rather than trusted to be absent: `leaveExercise` clears its
    /// set count on the way out, and a row printed from a stale entry would
    /// count sets off a movement the same screen calls skipped.
    private var trainedShort: [SessionExercise] {
        session.exercises.filter {
            setsLost($0) > 0 && !skipped.contains($0.pattern)
        }
    }

    private func setsLost(_ ex: SessionExercise) -> Int { setsSkipped[ex.pattern] ?? 0 }

    /// Movements with an addition standing, in session order. A movement
    /// that was LEFT cannot carry one — the summary is the last set's screen
    /// — but the filter is written down rather than trusted.
    private var raisedRows: [SessionExercise] {
        session.exercises.filter {
            (raised[$0.pattern] ?? 0) > 0 && !skipped.contains($0.pattern)
        }
    }

    private var total: Int { session.exercises.count }

    /// One sentence, shared by the line under the cards and by the dimmed
    /// card's hint: VoiceOver announces "dimmed" and stops, so the reason has
    /// to travel with the control as well as beside it.
    private var easyGateReason: String {
        String(localized: "“Easy, could do more” is for a workout done in full.")
    }

    /// `enabled` is passed at every call site rather than defaulted: an
    /// omitted gate argument is a known defect class in this project, and a
    /// compile error is a stronger guard than a grep.
    private func optionCard(title: String, caption: String,
                            result: FeedbackResult, enabled: Bool) -> some View {
        Button {
            onComplete(result, overrides)
        } label: {
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
                    // Two lines held open, never capped: the three cards are
                    // EQUAL only if one caption that wraps does not make its
                    // card taller than the other two. A range, not
                    // `lineLimit(2)`: at accessibility sizes a caption takes
                    // three lines and must not be cut.
                    .lineLimit(2...)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.bg)
                    // A border, not a chevron: a chevron elsewhere in the app
                    // opens something you can back out of, while here one tap
                    // writes the journal and applies the rating.
                    //
                    // `targetStroke`, because it is the ONLY thing marking the
                    // card as a control: hairline is 1.17:1 on `bg` and ink3
                    // 2.35:1 in light, both under the 3:1 that boundary owes
                    // (1.4.11).
                    //
                    // `strokeBorder`, not `stroke`: a plain stroke sits
                    // centred on the edge, half of it outside the card, and
                    // that outer half gets clipped along the top and bottom —
                    // the border would read 0.75 pt on the long sides and
                    // 1.5 pt on the short ones. Inset, the whole line is drawn
                    // inside the shape, as the summary's cards draw theirs.
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Theme.targetStroke, lineWidth: 1.5))
            )
        }
        .disabled(!enabled)
        // Derived from the RESULT rather than passed in, so a fourth card
        // could not be added with a copied identifier. Every walk that ends a
        // workout taps one of these three, and an identifier keeps it off the
        // English caption.
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
