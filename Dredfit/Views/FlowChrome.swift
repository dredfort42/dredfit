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

/// The pause both guided blocks carry on every timed screen (issue #61) —
/// compact, one slot under the countdown, the same weight as the technique
/// affordance above it. The outline says "control" where a bare label would
/// read as one more caption.
struct BlockPauseButton: View {
    let paused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(paused ? String(localized: "Resume") : String(localized: "Pause"),
                  systemImage: paused ? "play.fill" : "pause.fill")
                .dredfitFont(14, weight: .medium)
                .foregroundStyle(paused ? Theme.accentText : Theme.ink2)
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1.5))
        }
        // The identifier carries the state, not just the control: a localized
        // run must still be able to tell a paused block from a running one.
        .accessibilityIdentifier(paused ? "block-resume" : "block-pause")
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

/// The per-position escape both guided blocks carry.
struct PositionSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip this move")
                .dredfitFont(14, weight: .medium)
                .foregroundStyle(Theme.ink2)
                .frame(minHeight: 44)
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
        // Without an identifier the button answers only to its English
        // label, and a localized run cannot open the sheet at all.
        .accessibilityIdentifier("technique")
    }
}
