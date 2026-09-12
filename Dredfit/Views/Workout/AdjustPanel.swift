//
//  The inline actual adjuster: −/value/+ and OK.
//

import SwiftUI
import DredfitCore

struct AdjustPanel: View {
    @Binding var value: Int
    /// Picks the corridor, which is defined once in `SetFacts.corridor`. The
    /// step is one unit — one rep, one second — here and in `SetFacts.snap`
    /// alike, so what this panel offers and what a hold stopped early rounds
    /// to are the same grid.
    let unit: LoadUnit
    /// A narrower range than the corridor, when the caller knows one. The
    /// summary of a hold passes the clock as the ceiling on every set but
    /// the last (`SetFacts.correctionRange`); nil is the corridor itself.
    var range: ClosedRange<Int>?
    let onConfirm: () -> Void

    /// How long a finger has to stay down before the panel starts counting on
    /// its own — long enough that no ordinary tap ever trips it.
    private static let repeatDelay: Duration = .milliseconds(450)
    private static let repeatInterval: Duration = .milliseconds(120)
    /// After a second of holding the person is plainly travelling, not
    /// picking, so the panel doubles the rate.
    private static let repeatFastInterval: Duration = .milliseconds(60)
    private static let stepsBeforeFast = 8

    @State private var repeatTask: Task<Void, Never>?
    /// A hold ends with the finger lifting inside the button, which is also
    /// what fires its tap — one extra step on top of everything the repeat
    /// already counted. Set by the repeat, cleared by the tap it swallows and
    /// by the next press, so a hold that ends outside the button cannot leave
    /// it standing to eat a later tap.
    @State private var repeatAteTheTap = false

    var body: some View {
        HStack(spacing: 18) {
            stepButton("minus", -1)
            Text(unit == .hold ? "\(value) s" : "\(value)")
                .dredfitFont(26, weight: .heavy)
                .monospacedDigit()
                .frame(minWidth: 76)
            stepButton("plus", +1)

            Button(action: onConfirm) {
                Text("OK")
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
            }
            // Named, like the two steppers beside it: "OK" is also what a
            // system alert calls its button, so a query for the label alone
            // can resolve to something this panel does not own.
            .accessibilityIdentifier("adjust-confirm")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // The width of the button it stands over, not the width of its own
        // contents: a pill floating in the middle of the screen read as a
        // detached widget rather than as the entry for the set below it.
        .frame(maxWidth: .infinity)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
        // The panel can leave under a held finger — OK is one thumb away —
        // and a repeat that outlived it would go on moving a number nobody
        // is looking at.
        .onDisappear { endRepeat() }
    }

    private var bounds: ClosedRange<Int> { range ?? SetFacts.corridor(for: unit) }

    private func bump(_ dir: Int) {
        let stepped = value + dir
        value = min(max(stepped, bounds.lowerBound), bounds.upperBound)
    }

    /// A stepper at its bound is a stepper with nothing to do in that
    /// direction, and it says so rather than swallowing the tap: on the
    /// summary the upper bound is the clock, and a "+" that looked live over
    /// a number that would not move was the one control on the screen that
    /// lied (§41.13).
    private func atBound(_ dir: Int) -> Bool {
        dir < 0 ? value <= bounds.lowerBound : value >= bounds.upperBound
    }

    /// 44, not 40. These were the only targets in the whole workout flow under
    /// the floor the rest of it holds to (`HeldSetCard`, `FlowChrome`,
    /// `SkipConfirmation`), and they are the ones hit repeatedly, with a wet
    /// finger, by somebody who has just got up off the floor
    /// (UX review, 05.09.2026).
    private func stepButton(_ icon: String, _ dir: Int) -> some View {
        Button {
            if repeatAteTheTap { repeatAteTheTap = false; return }
            bump(dir)
        } label: {
            Image(systemName: icon)
                .dredfitFont(15, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                // targetStroke, not hairline. These two circles have no fill,
                // so the ring IS the button — and hairline on the panel's
                // `cardBG` comes to about 1.05:1 in the light scheme, which
                // drew the most-tapped pair of targets in the flow as a glyph
                // floating in nothing. The token is the same one the pause
                // capsule, the block escapes and the summary cards wear, so
                // one idiom answers for every outline a thumb aims at
                // (finding 31, UX review 05.09.2026).
                .background(Circle().stroke(Theme.targetStroke, lineWidth: 1.5))
        }
        // The step stays ONE unit — the five-second grid was taken off holds
        // deliberately (`SetFacts.snap`), and a hand-stopped 38 s has to stay
        // sayable. What was wrong is the price of a step, not its size: this
        // panel is the screen that exists to correct a number, and correcting
        // a 45 s hold to 25 cost twenty separate taps, which is a price people
        // pay by not correcting it (UX review, 05.09.2026).
        .buttonStyle(PressReportingButtonStyle { pressing in
            if pressing { beginRepeat(dir) } else { endRepeat() }
        })
        // Dimmed AND disabled: the height stays, the tap goes nowhere, and
        // VoiceOver hears "dimmed" instead of a control that does nothing.
        .opacity(atBound(dir) ? 0.3 : 1)
        .disabled(atBound(dir))
        .accessibilityLabel(Text(icon == "minus"
                                 ? String(localized: "Fewer")
                                 : String(localized: "More")))
        // Pinned so the label above does not move the symbol-derived id.
        .accessibilityIdentifier(icon)
    }

    private func beginRepeat(_ dir: Int) {
        endRepeat()
        repeatAteTheTap = false
        // A Task, not a Timer: the view is MainActor-isolated and so is the
        // task it starts, so the number is moved on the main actor without a
        // @Sendable hop to reason about.
        repeatTask = Task {
            try? await Task.sleep(for: Self.repeatDelay)
            var steps = 0
            while !Task.isCancelled {
                repeatAteTheTap = true
                bump(dir)
                steps += 1
                try? await Task.sleep(for: steps < Self.stepsBeforeFast
                                      ? Self.repeatInterval
                                      : Self.repeatFastInterval)
            }
        }
    }

    private func endRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// Reports the press itself, which a `Button` action cannot: the action fires
/// once, on release, and press-and-hold needs the moment the finger lands and
/// the moment it lifts. The look is the label's own — the style adds only the
/// dimming every system button gives while it is down.
private struct PressReportingButtonStyle: ButtonStyle {
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChange(pressed)
            }
    }
}
