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
    /// Whether what is counting down is already the count-in — the last
    /// `GetReady.countInSeconds` of a transition, however it got there.
    let countingIn: Bool
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
            // Two reasons the transition has nothing left to start early.
            // Frozen, "I'm ready" would run a position the user has just
            // stopped. Inside the count-in it is simply spent: the cut it
            // makes is `min(remaining, countInSeconds)`, so once the
            // countdown is down there the tap can only return the same
            // number — a control that answers with nothing is worse than no
            // control, and the last five seconds are the count-in whether a
            // tap made them so or the transition ran down to them.
            //
            // hidden(), not removed: the escapes must not jump up under the
            // thumb. (Precedent: "Start hold" during the side-switch pause
            // and during its own count-in.)
            Group {
                if paused || countingIn {
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
    let move: WarmupMove
    /// Which half of a unilateral move is running (§41.12). A bilateral move
    /// has one stage and shows no line at all.
    let stage: Warmup.Stage
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
            BlockPositionName(name: move.name)
            if move.perSide {
                SideStageLine(stage).padding(.top, 6)
            }

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
            // `identifier:` stated for the same reason `skip-cooldown` states
            // it below: the default is `identifier ?? title`, and `title` is
            // already localized — omitting it makes the identifier move with
            // the display language.
            BlockSkipButton(title: String(localized: "Skip warm-up"),
                            identifier: "skip-warmup",
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
                SideStageLine(stage).padding(.top, 6)
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
}

/// The line a per-side position shows over its countdown.
///
/// ONE view, not a copy per block: the two stage machines differ (`.single`
/// against `.move`), the three lines they show do not, and §41.12 — which gave
/// the warm-up the cool-down's side switch — would otherwise have written the
/// second copy that drifts. Each block hands over its own stage; the mapping
/// lives here, so a new stage on either side is a compile error here rather
/// than a screen that quietly says nothing.
private struct SideStageLine: View {
    private enum Phase { case beforeTheSwitch, switching, secondSide }
    private let phase: Phase

    init(_ stage: Warmup.Stage) {
        switch stage {
        case .switchPause: phase = .switching
        case .secondSide:  phase = .secondSide
        case .getReady, .move, .firstSide: phase = .beforeTheSwitch
        }
    }

    init(_ stage: Cooldown.Stage) {
        switch stage {
        case .switchPause: phase = .switching
        case .secondSide:  phase = .secondSide
        case .getReady, .single, .firstSide: phase = .beforeTheSwitch
        }
    }

    var body: some View {
        switch phase {
        case .switching:
            Text("Switch sides")
                .dredfitFont(14, weight: .semibold)
                .foregroundStyle(Theme.accentText)
        case .secondSide:
            Text("second side")
                .dredfitFont(14, weight: .semibold)
                .foregroundStyle(Theme.accentText)
        case .beforeTheSwitch:
            // A `cooldown.` key read by the warm-up too: the key is older than
            // the warm-up's side switch, the STRING is the same 15 s per side
            // in both blocks, and renaming it would cost six translations and
            // the whole screenshot set to say exactly what it says now.
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
