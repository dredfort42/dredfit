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
                exitButton(action: onExit)
                Spacer()
                Text(title)
                    .dredfitFont(13, weight: .semibold)
                    .kerning(0.5)
                    // ink2, not ink3: this is information, not decoration.
                    .foregroundStyle(Theme.ink2)
                Spacer()
                // Symmetry: the title is centred by two equal ends, so the
                // right one has to measure the same — including the 44 pt.
                exitButton(action: { }).hidden()
            }
            if steps > 0 {
                HStack(spacing: 5) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule()
                            .fill(i <= doneIndex ? Theme.ink : Theme.hairline)
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
    private func exitButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // ink2, not ink3: ink3 (~2.4:1) fails contrast for
            // interactive text.
            Text("Exit")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

/// The big rolling number with its "sec" caption.
struct CountdownNumber: View {
    let value: Int
    let identifier: String
    /// Paused (issue #61) the number dims and the unit gives way to the
    /// state, so a glance says why nothing is moving.
    var paused = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .dredfitFont(112, weight: .heavy, cap: 150)
                .tracking(-4)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(paused ? Theme.ink2 : Theme.ink)
                .accessibilityIdentifier(identifier)
            if paused {
                Text("Paused")
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(Theme.accentText)
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

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < current ? Theme.ink : (i == current ? Theme.accent : Theme.hairline))
                    .frame(width: 10, height: 10)
            }
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
