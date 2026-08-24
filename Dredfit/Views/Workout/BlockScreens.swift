//
//  The three screens of a guided block: the "Get ready" transition, a
//  running warm-up move, and a running cool-down position.
//
//  Layout only — each is a pure function of what it is handed; the flow view
//  keeps the state machine and the timers.
//

import SwiftUI

struct GetReadyScreen: View {
    let name: String
    let remaining: Int
    let index: Int
    let count: Int
    /// The way back in after a pause borrows this screen (issue #61) and
    /// names its countdown differently, so the two can be told apart.
    var countdownIdentifier: String = "getready-countdown"
    let blockSkipTitle: String
    var blockSkipIdentifier: String?
    let paused: Bool
    let onTechnique: () -> Void
    let onStart: () -> Void
    let onPauseToggle: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            VStack(spacing: 6) {
                // The kicker is half a sentence the name finishes; VoiceOver
                // gets it whole, once, from the name below.
                Kicker(text: String(localized: "Get ready"))
                    .accessibilityHidden(true)
                BlockPositionName(name: name)
                    .accessibilityLabel(Text("Get ready: \(name)"))
            }

            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: countdownIdentifier, paused: paused)
                .padding(.top, 20)

            BlockPauseButton(paused: paused, action: onPauseToggle)
                .padding(.top, 12)

            BlockDots(count: count, current: index)
                .padding(.top, 22)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            // Frozen, the transition has nothing to start early — "I'm ready"
            // would run a position the user has just stopped. hidden(), not
            // removed: the escapes must not jump up under the thumb.
            // (Precedent: "Start hold" during the side-switch pause.)
            Group {
                if paused {
                    PrimaryButton(title: String(localized: "I'm ready"), action: { }).hidden()
                } else {
                    PrimaryButton(title: String(localized: "I'm ready"), action: onStart)
                        .accessibilityIdentifier("get-ready-start")
                }
            }
            .padding(.bottom, 12)

            BlockSkipButton(title: blockSkipTitle,
                            identifier: blockSkipIdentifier,
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }
}

struct WarmupMoveScreen: View {
    let name: String
    let remaining: Int
    let index: Int
    let count: Int
    let paused: Bool
    let onTechnique: () -> Void
    let onPauseToggle: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            BlockPositionName(name: name)

            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: "warmup-countdown", paused: paused)
                .padding(.top, 20)

            BlockPauseButton(paused: paused, action: onPauseToggle)
                .padding(.top, 12)

            BlockDots(count: count, current: index)
                .padding(.top, 22)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            BlockSkipButton(title: String(localized: "Skip warm-up"),
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }
}

struct CooldownPositionScreen: View {
    let position: CooldownPosition
    let stage: Cooldown.Stage
    let remaining: Int
    let index: Int
    let count: Int
    let paused: Bool
    let onTechnique: () -> Void
    let onPauseToggle: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            BlockPositionName(name: position.name)
            if position.perSide {
                stageLine.padding(.top, 6)
            }

            // Freezes the countdown mid-pause too: the switch waits.
            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: "cooldown-countdown", paused: paused)
                .padding(.top, 20)

            BlockPauseButton(paused: paused, action: onPauseToggle)
                .padding(.top, 12)

            BlockDots(count: count, current: index)
                .padding(.top, 22)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            BlockSkipButton(title: String(localized: "cooldown.skip",
                                          defaultValue: "Skip cool-down"),
                            identifier: "skip-cooldown",
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var stageLine: some View {
        switch stage {
        case .switchPause:
            Text("Switch sides")
                .dredfitFont(14, weight: .semibold)
                .foregroundStyle(Theme.accentText)
        case .secondSide:
            Text("second side")
                .dredfitFont(14, weight: .semibold)
                .foregroundStyle(Theme.accentText)
        case .getReady, .single, .firstSide:
            Text(String(localized: "cooldown.perSide", defaultValue: "15 s per side"))
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
        }
    }
}

/// Content centred in whatever room is left, escapes pinned under it.
///
/// It scrolls rather than clips: at the largest accessibility sizes a
/// three-line position name plus the countdown outgrows the screen, and the
/// escapes must never be pushed out from under the user. Below that size
/// nothing scrolls and nothing moved.
private struct BlockLayout<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            footer
        }
    }
}

/// The long es/pt-BR names wrap to three lines at the largest Dynamic Type
/// sizes; let them.
private struct BlockPositionName: View {
    let name: String

    var body: some View {
        Text(name)
            .dredfitFont(23, weight: .bold)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            .fixedSize(horizontal: false, vertical: true)
    }
}
