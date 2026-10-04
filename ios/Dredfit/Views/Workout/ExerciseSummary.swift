//
//  Every set of a finished hold movement, on one screen, with the last one a
//  tap from being corrected — and, under them, what the next plan will be
//  and the one control that can raise it.
//
//  The work screen's writer records the set under way and truncates what
//  follows, because on that screen the sets after it have not happened yet.
//  Here they have, so the writer is `SetFacts.recordingSet`, which changes
//  one and leaves the rest standing.
//
//  TWO TENSES, TWO BLOCKS. The cards are the past — what the clock counted,
//  correctable only in the past tense ("how long was the last set held?").
//  The block under them is the future — what the app will set, and how much
//  the person adds to it. Folded into the cards — a set above its plan in
//  orange with "+5", a line saying "the next plan starts from these
//  numbers" — the future would invite people to enter what they WANT next
//  time, and the journal would record it as held. Nothing on the cards is
//  accented; the accent belongs to the one thing on this screen that is a
//  decision.
//
//  The leaf views live apart from the flow (WorkoutFlowView+Summary.swift):
//  what a card looks like is not what the phase decides.
//

import SwiftUI
import DredfitCore

/// One set of the movement as the summary prints it.
struct HeldSet: Identifiable {
    /// 0-based, like everything the flow counts sets with.
    let index: Int
    let seconds: Int
    let planned: Int
    /// The number is an ESTIMATE rather than a measurement: the set ended
    /// under a thumb, which pays a guessed three-second reach allowance.
    /// Printed as "≈", because a number the app guessed at must not be shown
    /// with the confidence of one the clock produced.
    let approximate: Bool

    var id: Int { index }
}

/// One tappable number. 44 pt is the floor for the target, not for the card:
/// the number alone is 40 pt tall at the default text size and a card that
/// only just cleared it would fail the moment somebody turned text up (R18).
struct HeldSetCard: View {
    let held: HeldSet
    /// Only the last set of the movement: nothing followed it, so what it
    /// ran is the person's to correct in both directions. Every earlier set
    /// ended on its signal or under a thumb and stands as it ran — the
    /// card is inert, without the outline that says "tap me" and without
    /// the hint that promises a change. It stays a button in the tree so
    /// the tests that read the cards by identifier keep reading them.
    let correctable: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if correctable { action() }
        } label: {
            VStack(spacing: 2) {
                // Verbatim: a bare numeral with a maths sign carries no words
                // to translate, and the "≈" is drawn in the number's OWN
                // colour rather than a quieter one — a mark that says "this
                // figure is an estimate" is not decoration (R16).
                Text(verbatim: held.approximate ? "≈\(held.seconds)" : "\(held.seconds)")
                    .dredfitFont(34, weight: .heavy, cap: 46)
                    .monospacedDigit()
                Text("set \(held.index + 1)")
                    .dredfitFont(12, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                // THE PLAN ON EVERY CARD, even when it is the same on all of
                // them. The comparison is the reader's to make, and it is
                // made by two numbers standing together — not by a "+5",
                // which reads as easily as "next time +5" as it does as
                // "5 s over the plan".
                Text("plan \(held.planned)")
                    .dredfitFont(12, weight: .semibold)
                    .monospacedDigit()
                // An estimate says so: it is a statement about how much the
                // number can be trusted, which the "≈" alone does not explain.
                if held.approximate {
                    Text("stopped by hand")
                        .dredfitFont(12, weight: .medium)
                        .foregroundStyle(Theme.ink2)
                }
            }
            .foregroundStyle(Theme.ink)
            // maxHeight: the estimate's third line makes one card taller,
            // and a row of cards of three heights reads as three kinds of
            // thing. Stretched, they share the tallest.
            .frame(minWidth: 78, minHeight: 72, maxHeight: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // One fill for every card, never the accent: on this app's
            // screens the accent means "a decision beyond the ordinary", and a
            // card of measured seconds is not one — accented, it would read as
            // the app having changed something. The block under the row is
            // where that colour lives.
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
            // The outline is the affordance. In fill and radius alone the
            // card would look like the flow's NON-tappable information panel
            // (FeedbackView).
            //
            // `targetStroke` at 1.5, the token `flowSecondaryLabel`, the block
            // escapes and the adjuster's steppers wear: ink3 is 2.35:1 in the
            // light scheme, under the 3:1 1.4.11 asks of an affordance.
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(correctable ? Theme.targetStroke : Theme.cardBG, lineWidth: 1.5))
        }
        .accessibilityIdentifier("summary-set-\(held.index + 1)")
        .accessibilityLabel(Text(spoken))
        .accessibilityHint(Text(correctable ? String(localized: "Change this number") : ""))
    }

    /// Spoken as a sentence, with the plan in it: "48" and "set 2" read out
    /// as two facts leave the listener nothing to measure the number against,
    /// and the whole point of the screen is the comparison.
    private var spoken: String {
        held.approximate
            ? String(localized: """
                set \(held.index + 1), approximately \(held.seconds) seconds, \
                planned \(held.planned)
                """)
            : String(localized: """
                set \(held.index + 1), \(held.seconds) seconds, \
                planned \(held.planned)
                """)
    }
}

/// The row of cards: one line while they fit, two lines when they do not, and
/// a column when even that is too wide. Five sets, an accessibility text size
/// and an iPhone SE are all real at once — the pattern is the app's own, and
/// the caller wraps this in the scroll that makes the last case survivable.
struct HeldSetsRow: View {
    let sets: [HeldSet]
    let onEdit: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) { cards(sets) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { cards(sets) }
                VStack(spacing: 10) {
                    HStack(spacing: 10) { cards(Array(sets.prefix(3))) }
                    if sets.count > 3 {
                        HStack(spacing: 10) { cards(Array(sets.dropFirst(3))) }
                    }
                }
                VStack(spacing: 10) { cards(sets) }
            }
        }
    }

    @ViewBuilder
    private func cards(_ sets: [HeldSet]) -> some View {
        ForEach(sets) { held in
            HeldSetCard(held: held, correctable: held.index == self.sets.count - 1) {
                onEdit(held.index)
            }
        }
    }
}

// MARK: - Next time

/// What the next plan for this movement will be, and the stepper that adds
/// to it. The only future tense on the screen, and the only accent.
///
/// ONE SENTENCE THAT CHANGES. Each tap on the stepper rewrites the plan in
/// the sentence itself — "The app will set 30-30-30 s" — rather than printing
/// a running total beside the control: two numbers about one plan is one
/// number too many, and what the person wants to see is what will actually be
/// asked of them. The stepper carries only its own
/// value; what "+" and "−" do needs no caption.
struct NextTimeBlock: View {
    let exercise: SessionExercise
    /// Steps already added, 0…`EngineConfig.raiseStepsMax`.
    let steps: Int
    /// Whether a number was entered for this movement. With one the step is
    /// taken from the fact and the rating never reaches it, so the sentence
    /// can promise; without one it depends on the rating, and says so.
    let factEntered: Bool
    /// The plan the movement will get with `steps` additions, as the engine
    /// would set it — a dry run, not a guess. Nil when nothing can be said.
    let preview: (Int) -> SessionExercise?
    let onChange: (Int) -> Void

    private var planned: SessionExercise? { preview(steps) }

    /// The grid's ceiling parks the raise: one more step would set
    /// the same plan.
    private var atCeiling: Bool {
        guard let now = planned, let next = preview(steps + 1) else { return true }
        return Self.samePlan(now, next)
    }

    /// Whether two previews promise one plan — compared on what is printed,
    /// which is what the person would be promised.
    static func samePlan(_ a: SessionExercise, _ b: SessionExercise) -> Bool {
        a.display == b.display && a.variation == b.variation
    }

    /// How many of `steps` still change the plan. The taps are made against
    /// the plan of the moment, and a correction made AFTER them can move the
    /// base — the last card corrected upward lands the plan on the fact —
    /// onto the grid's ceiling, where the engine parks what was
    /// added. Walked down from the count while the step below promises the
    /// same plan; a preview that cannot be had leaves the count alone rather
    /// than reading as "nothing moves". Static so a test can reach the rule
    /// without a screen.
    static func stepsThatStillMove(_ steps: Int, preview: (Int) -> SessionExercise?) -> Int {
        var k = max(0, steps)
        while k > 0, let now = preview(k), let below = preview(k - 1), samePlan(now, below) {
            k -= 1
        }
        return k
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Named, like "Held" above it and for the same reason: the
            // uppercase fold makes the word unfindable by its spelling.
            Text("Next time")
                .dredfitFont(11, weight: .heavy)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(steps > 0 ? Theme.ink : Theme.accentText)
                .accessibilityIdentifier("summary-next-time")
            if let planned {
                sentence(for: planned)
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("summary-next-plan")
            }
            if steps == 0 && atCeiling {
                // Nothing to add: the movement is at the top of its grid.
                // Said instead of a stepper whose "+" would be dead on
                // arrival — a control that can do nothing is worse than a
                // sentence that says why.
                Text("This is the most for this movement.")
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("summary-next-max")
            } else {
                RaiseStepper(unit: exercise.unit, steps: steps,
                             canAdd: steps < EngineConfig.raiseStepsMax && !atCeiling,
                             onChange: onChange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // The accent goes on when the person has added something — and only
        // then. Off, the block is a panel with a hairline outline; on, it is
        // the one orange thing on the screen, and it is the person's own
        // decision. Never accentText on the fill, the kicker included: that
        // pair is 4.20:1 in the dark scheme and just under 4.5 in the light
        // one (I-21), under what small text needs.
        .background(steps > 0 ? Theme.accentSoft : Theme.cardBG,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(steps > 0 ? Theme.accent : Theme.hairline, lineWidth: 1.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The plan, and a name only when the variation changes — a probe passed
    /// on this movement lands the next plan on another exercise, and "3×15 s"
    /// with no name would read as a collapse rather than a promotion.
    ///
    /// With a fact entered the sentence is the plan and nothing else: the
    /// reader wants the number, not its origin. Without a fact the condition
    /// stays, because the number is not a promise until the rating is given.
    private func sentence(for planned: SessionExercise) -> Text {
        let what = planned.variation == exercise.variation
            ? planned.display
            : "\(planned.name) · \(planned.display)"
        return factEntered
            ? Text("The app will set \(what).")
            : Text("The app will set \(what) if you rate the workout “on plan”.")
    }
}

/// −/value/+ for the addition. No OK: the value is not entered, it is
/// standing, and the sentence above it already shows the consequence.
struct RaiseStepper: View {
    let unit: LoadUnit
    let steps: Int
    let canAdd: Bool
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 18) {
            stepButton("minus", enabled: steps > 0) { onChange(steps - 1) }
            Text(verbatim: RaiseLabel.text(steps: steps, unit: unit))
                .dredfitFont(22, weight: .heavy)
                .monospacedDigit()
                // One line in every language — "+10 сек" is the widest — the
                // same rule the entry panel's number follows.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minWidth: 64)
                .accessibilityLabel(Text(verbatim: RaiseLabel.spoken(steps: steps, unit: unit)))
                .accessibilityIdentifier("raise-value")
            stepButton("plus", enabled: canAdd) { onChange(steps + 1) }
        }
        .frame(maxWidth: .infinity)
    }

    /// The panel's own steppers, with the same 44 pt ring, the same outline
    /// and the same 62 × 68 pt hit shape over it (`AdjustPanel`). Dimmed AND
    /// disabled at a bound, so the tap goes nowhere and VoiceOver hears why.
    private func stepButton(_ icon: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .dredfitFont(15, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().stroke(Theme.targetStroke, lineWidth: 1.5))
                // The TARGET is bigger than the ring, as on the panel (#251).
                // A Button takes taps only where its label draws, so without
                // this the frame's corners would be dead, and a thumb reaching
                // across the phone lands at the ring's edge and misses there
                // again on every repeat. The margins are this row's own, not
                // the panel's copied: half the 18 pt gap to the number either
                // side, and 12 pt above and below — inside the block's 14 pt
                // bottom padding, and 2 pt over the 10 pt gap to the sentence
                // above, which is text and takes no tap. 62 × 68 pt of hit
                // shape over the same 44 pt of layout, so nothing in the row
                // moves.
                .padding(.vertical, 12)
                .padding(.horizontal, 9)
                .contentShape(Rectangle())
                .padding(.vertical, -12)
                .padding(.horizontal, -9)
        }
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .accessibilityLabel(Text(icon == "minus"
                                 ? String(localized: "Fewer")
                                 : String(localized: "More")))
        .accessibilityIdentifier("raise-\(icon)")
    }
}
