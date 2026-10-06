//
//  The inline actual adjuster: −/value/+ and OK.
//

import SwiftUI
import DredfitCore

struct AdjustPanel: View {
    @Binding var value: Int
    /// Picks the corridor, which is defined once in `SetFacts.corridor`, and
    /// the step: one rep, or five seconds for a hold (`holdStep`).
    let unit: LoadUnit
    /// A narrower range than the corridor, when the caller knows one. The
    /// summary of a hold passes `SetFacts.correctionRange`; nil is the
    /// corridor itself.
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
            // ONE line, whatever the unit's word is: "10 сек" at 26 pt heavy
            // is wider than "10 s", and between two 44 pt targets and OK it
            // would break into "10" over "сек". The number is
            // the one flexible thing in the row — it yields size before it
            // yields the line — and OK below is pinned to its own width, so
            // on a narrow phone it is the number that shrinks, not the word
            // on the button.
            Text(unit == .hold ? "\(value) s" : "\(value)")
                .dredfitFont(26, weight: .heavy)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minWidth: 76)
            stepButton("plus", +1)

            Button(action: onConfirm) {
                Text("OK")
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
                    .fixedSize()
            }
            // Named, like the two steppers beside it: "OK" is also what a
            // system alert calls its button, so a query for the label alone
            // can resolve to something this panel does not own.
            .accessibilityIdentifier("adjust-confirm")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // The width of the button it stands over, not the width of its own
        // contents: a pill floating in the middle of the screen would read
        // as a detached widget rather than as the entry for the set below it.
        .frame(maxWidth: .infinity)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
        // The panel can leave under a held finger — OK is one thumb away —
        // and a repeat that outlived it would go on moving a number nobody
        // is looking at.
        .onDisappear { endRepeat() }
    }

    private var bounds: ClosedRange<Int> { range ?? SetFacts.corridor(for: unit) }

    /// One rep, or FIVE seconds: a hold is set and corrected on the grid it
    /// is planned on (`Dose.hold` steps by 5), and a panel walking one second
    /// at a time would ask a person standing over the phone for tap after tap
    /// to say "45". A number that is not on the grid —
    /// a hand-stopped 38 s the summary opened on — moves to the next grid
    /// line in the tapped direction, so the first tap already lands where
    /// every later one will.
    static func holdStep(_ value: Int, _ dir: Int) -> Int {
        let grid = 5
        if dir > 0 { return (value / grid + 1) * grid }
        return value.isMultiple(of: grid) ? value - grid : (value / grid) * grid
    }

    private func bump(_ dir: Int) {
        let stepped = unit == .hold ? Self.holdStep(value, dir) : value + dir
        value = min(max(stepped, bounds.lowerBound), bounds.upperBound)
    }

    /// A stepper at its bound is a stepper with nothing to do in that
    /// direction, and it says so rather than swallowing the tap: a "+" that
    /// looks live over a number that will not move is a control that lies.
    private func atBound(_ dir: Int) -> Bool {
        dir < 0 ? value <= bounds.lowerBound : value >= bounds.upperBound
    }

    /// 44 pt, the floor the rest of the workout flow holds to (`HeldSetCard`,
    /// `FlowChrome`, `SkipConfirmation`): these are the targets hit
    /// repeatedly, with a wet finger, by somebody who has just got up off the
    /// floor.
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
                // `cardBG` is 1.09:1 in the light scheme, which would draw the
                // most-tapped pair of targets in the flow as a glyph floating
                // in nothing. The token is the same one the pause capsule, the
                // block escapes and the summary cards wear, so one idiom
                // answers for every outline a thumb aims at.
                .background(Circle().stroke(Theme.targetStroke, lineWidth: 1.5))
                // The TARGET is bigger than the ring. A Button takes taps
                // only where its label draws — here the glyph and the
                // circle's interior — not on the 44 pt frame around them,
                // so without this the frame's four corners and everything
                // past the ring would take no tap at all. A thumb reaching
                // across the phone to "−" lands its centroid at the ring's
                // edge or just past it, and lands there again on every
                // repeat: the button would "stick" (#251). The shape is the
                // square plus the panel's own padding and half the gap to
                // the number — 62 × 68 pt — laid over the same 44 pt of
                // layout, so nothing in the row moves.
                .padding(.vertical, 12)
                .padding(.horizontal, 9)
                .contentShape(Rectangle())
                .padding(.vertical, -12)
                .padding(.horizontal, -9)
        }
        // A rep is one unit; a hold steps by five seconds (`holdStep`): a
        // hand-stopped 38 s is what the clock writes on its own, and the
        // panel is for what the person says, which is in fives. The
        // press-and-hold repeat covers distance; it never makes the step
        // finer.
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
