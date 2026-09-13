//
//  The small pieces every timed block of the workout flow shares: the header,
//  the big rolling countdown number, the set dots and the "ⓘ technique"
//  affordance. One look, defined once — the warm-up, rest and cool-down
//  screens assemble these instead of restating them. The escapes and the rest
//  ring are the same idea and live beside this, in FlowChrome+Controls and
//  FlowChrome+Rest.
//

import SwiftUI

/// The bar every timed phase wears: the way out on the left, what the screen
/// is in the middle, and the per-exercise capsules underneath. The rating and
/// milestone screens carry no header at all, so this view never knows about
/// them.
struct FlowHeader: View {
    let title: String
    /// 0 hides the capsule row — the warm-up is not an exercise yet.
    let steps: Int
    /// How many exercises are BEHIND: the capsules before this index are
    /// done, the one AT it is the movement under way, and the rest are ahead.
    /// The name predates the three-state fill below, and "the exercise under
    /// way" is only what it means while one IS under way.
    ///
    /// So `steps` itself is the honest value for a phase where none is —
    /// every capsule then reads done, which is what the old `i <= doneIndex`
    /// fill did by accident. The cool-down is that phase: neither
    /// `completeSet` nor `advancePastExercise` moves `exIndex` past the last
    /// exercise on the way into it, so a caller passing `exIndex` there paints
    /// the last capsule accent — the colour every other screen uses for the
    /// movement running now — for the several minutes a cool-down lasts
    /// (review 06.09.2026).
    let doneIndex: Int
    /// What is left of the session, or nil on the screens that carry a
    /// countdown of their own. The decision about the length of the workout is
    /// taken inside it now, so the number has to follow the decision: it drops
    /// the moment a set is skipped.
    var minutesLeft: Int?
    var onExit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                exitButton(identifier: "workout-exit", action: onExit)
                Spacer()
                Text(title)
                    .dredfitFont(13, weight: .semibold)
                    .kerning(0.5)
                    // ink2, not ink3: this is information, not decoration.
                    .foregroundStyle(Theme.ink2)
                Spacer()
                // Symmetry: the title is centred by two equal ends, so the
                // right one has to measure the same — including the 44 pt.
                // Its OWN identifier, because it is a second control reading
                // "Exit": the suite carried `.firstMatch` on every exit tap to
                // survive that ambiguity, and a name is a stronger guard than
                // an ordering assumption.
                exitButton(identifier: "workout-exit-spacer", action: { }).hidden()
            }
            if steps > 0 {
                HStack(spacing: 5) {
                    ForEach(0..<steps, id: \.self) { i in
                        // Three states, exactly as `BlockDots` below already
                        // draws the warm-up and the cool-down. Filling the
                        // CURRENT exercise as done overstated the bar by a
                        // whole movement: the first set of the first exercise
                        // opened with a capsule already black, and the last
                        // exercise saturated the row with three sets and the
                        // cool-down still ahead, so "nearly there" was a state
                        // it could not show (UX review, 05.09.2026).
                        //
                        // The capsules still AHEAD take ink2, not hairline.
                        // hairline is 1.17:1 on `bg` in the light scheme, so
                        // the track the finished capsules are measured against
                        // was not on the screen at all and the bar read as a
                        // row of loose marks with no length. ink2 is the only
                        // token clearing the 3:1 graphics floor in both
                        // schemes (4.96 / 6.97) and still reads a long way
                        // lighter than the ink of a finished exercise (18.7),
                        // so the three states stay three (UX review,
                        // 05.09.2026).
                        Capsule()
                            .fill(i < doneIndex
                                  ? Theme.ink
                                  : (i == doneIndex ? Theme.accent : Theme.ink2))
                            .frame(height: 4)
                    }
                }
                .frame(width: 200)
            }
            if let minutesLeft {
                // ink2 and 12 pt: an answer to "how much longer", not a
                // deadline. It is deliberately not a countdown — the clock is
                // nobody's business here, and what moves this number is what
                // the person decides to do.
                Text("≈ \(minutesLeft) min left")
                    .dredfitFont(12)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("time-left")
            }
        }
        .padding(.top, 12)
    }

    /// The way out of a workout in progress, and the hidden twin that keeps
    /// the title centred. 44 pt: a bare 14 pt label is about 17, and this is
    /// the control someone reaches for when a set has gone wrong.
    private func exitButton(identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // ink2, not ink3: ink3 (~2.4:1) fails contrast for
            // interactive text.
            Text("Exit")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        // No default: both call sites are one screen apart and one of them is
        // a placeholder, so an omitted argument would silently give the two
        // the same name.
        .accessibilityIdentifier(identifier)
    }
}

/// The big rolling number with the word under it: the unit while a position
/// is simply running itself down, or the STATE when the screen is doing
/// something else with the same 112 pt digit.
struct CountdownNumber: View {
    let value: Int
    let identifier: String
    /// Paused (issue #61) the number dims and the unit gives way to the
    /// state, so a glance says why nothing is moving.
    var paused = false
    /// What the number IS, when that is not seconds of the position itself —
    /// already localized by the caller, which is why it prints verbatim.
    ///
    /// nil is the ordinary case. The transition passes "Get ready", because
    /// without it the transition and a running move were the same picture: the
    /// same name, the same big number, the same dots, and the one word telling
    /// them apart was a 12 pt kicker at the top of the screen — off the phone
    /// that the block itself told the person to put on the floor. The work
    /// screen already solved this the same way, under the digit where the eye
    /// is (`WorkoutFlowView.loadCaption`) (UX review, 05.09.2026).
    var caption: String?

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .dredfitFont(112, weight: .heavy, cap: 150)
                .tracking(-4)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(paused ? Theme.ink2 : Theme.ink)
                .accessibilityIdentifier(identifier)
                // Same trait, same reason as the rest ring: a figure that
                // moves once a second must not make the reader talk over
                // itself while somebody is trying to hear where it is.
                .accessibilityAddTraits(.updatesFrequently)
            // Paused outranks the caption: a frozen "Get ready" would say what
            // the screen is FOR while hiding that it is not doing it.
            if paused {
                Text("Paused")
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(Theme.accentText)
            } else if let caption {
                // Accented like every other state in this slot across the
                // flow, and never ink3: this is the screen saying something
                // beyond the ordinary.
                Text(verbatim: caption)
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(Theme.accentText)
                    // The kicker this replaced carried the same trait, and for
                    // the same reason: on the block screens the phrase already
                    // stands under the number as the position's own name, so
                    // without this VoiceOver says "Get ready" twice in a row
                    // (review 06.09.2026). Hiding the CAPTION and not the
                    // number keeps `getready-countdown` in the tree, which
                    // three UI suites query by identifier.
                    .accessibilityHidden(true)
            } else {
                Text("sec")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }
}

/// One definition for the warm-up, the cool-down and the transition — three
/// copies would drift.
struct BlockDots: View {
    let count: Int
    let current: Int
    /// True on the transition, where the dot at `current` is the position
    /// ABOUT to run rather than the one under way.
    var upcoming = false

    /// 10 pt at the default text size, and it grows with the text. The dots
    /// are the whole of what this row says, and somebody who has turned text
    /// up has already told the phone they cannot read what it draws at 10
    /// (UX review, 05.09.2026).
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                dot(i).frame(width: dotSize, height: dotSize)
            }
        }
    }

    @ViewBuilder
    private func dot(_ i: Int) -> some View {
        if upcoming && i == current {
            // Outlined rather than filled, and only here: on the transition
            // this position has not started. A solid accent dot said it had,
            // which is the same overstatement `FlowHeader` above stopped
            // making about the exercise under way (UX review, 05.09.2026).
            Circle().strokeBorder(Theme.accent, lineWidth: 2)
        } else {
            // The dots still ahead take ink2 for the reason the header
            // capsules do: hairline is 1.17:1 on `bg` in the light scheme, so
            // "three of nine" was drawn as three dots and nothing.
            Circle().fill(i < current
                          ? Theme.ink
                          : (i == current ? Theme.accent : Theme.ink2))
        }
    }
}

/// The "ⓘ technique" affordance — one look shared by the work screen, the
/// rest screen and the warm-up/cool-down positions (issue #34).
struct TechniqueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "technique"), systemImage: "info.circle")
                .dredfitFont(14, weight: .medium)
                .foregroundStyle(Theme.ink2)
                // 44 pt, like the two escapes in FlowChrome+Controls — and
                // for a harder reason. This one is offered on five screens,
                // three of them mid-effort, where the hand that reaches for it
                // is the hand that just did the set. The bare label came to
                // about 17 pt.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        // Without an identifier the button answers only to its English
        // label, and a localized run cannot open the sheet at all.
        .accessibilityIdentifier("technique")
    }
}
