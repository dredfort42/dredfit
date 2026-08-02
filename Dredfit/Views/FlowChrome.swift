//
//  FlowChrome.swift
//  Dredfit
//
//  The small pieces every timed block of the workout flow shares: the big
//  rolling countdown number, the full-width outline escape button, and the
//  "ⓘ technique" affordance. One look, defined once — the warm-up, rest
//  and cool-down screens assemble these instead of restating them.
//

import SwiftUI

/// The big rolling number with its "sec" caption.
struct CountdownNumber: View {
    let value: Int
    let identifier: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .dredfitFont(112, weight: .heavy, cap: 150)
                .tracking(-4)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .accessibilityIdentifier(identifier)
            Text("sec")
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
        }
    }
}

/// The full-width outline escape at the bottom of a block — "Skip warm-up",
/// "Skip rest", "Skip cool-down".
struct BlockSkipButton: View {
    let title: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dredfitFont(17, weight: .medium)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1.5))
        }
        .accessibilityIdentifier(identifier ?? title)
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
        }
        // Addressed by identifier, like every other control a test drives:
        // without one the button answers only to its English label, so a
        // localized run cannot open the technique sheet at all.
        .accessibilityIdentifier("technique")
    }
}
