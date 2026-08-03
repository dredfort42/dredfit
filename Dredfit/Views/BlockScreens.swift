//
//  BlockScreens.swift
//  Dredfit
//
//  The three screens of a guided block: the "Get ready" transition (issue
//  #52), a running warm-up move, and a running cool-down position. Same
//  skeleton in all three — name, technique affordance, countdown, the
//  block's dots, the per-position escape and the block escape — so they are
//  drawn side by side here rather than three times inside the flow.
//
//  Layout only: every one of them is a pure function of what it is handed,
//  and the flow view keeps the state machine and the timers. Extracted when
//  the transition arrived and the flow file ran out of the linter's honest
//  room, the same way Warmup.swift and Cooldown.swift took the block data
//  out of it (issues #34, #28).
//

import SwiftUI

/// The transition before a position starts. Anyone already in place taps
/// "I'm ready" and it starts at once — the countdown is a floor on the pause
/// between positions, never a wait.
struct GetReadyScreen: View {
    let name: String
    let remaining: Int
    /// Which position of the block is coming — the dots read exactly as they
    /// do while it runs, so the transition never looks like a place of its own.
    let index: Int
    let count: Int
    let blockSkipTitle: String
    var blockSkipIdentifier: String?
    let onTechnique: () -> Void
    let onStart: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            VStack(spacing: 6) {
                // The kicker is the visible half of a sentence the name
                // finishes; VoiceOver gets that sentence whole, once, from
                // the name below — eyes are on the floor, not on the phone.
                Kicker(text: String(localized: "Get ready"))
                    .accessibilityHidden(true)
                BlockPositionName(name: name)
                    .accessibilityLabel(Text("Get ready: \(name)"))
            }

            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: "getready-countdown")
                .padding(.top, 20)

            BlockDots(count: count, current: index)
                .padding(.top, 30)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            // Sits exactly where "Done" and "Start hold" sit on the work
            // screen — the one button that moves the flow forward.
            PrimaryButton(title: String(localized: "I'm ready"), action: onStart)
                .accessibilityIdentifier("get-ready-start")
                .padding(.bottom, 12)

            BlockSkipButton(title: blockSkipTitle,
                            identifier: blockSkipIdentifier,
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }
}

/// A running warm-up move: 30 s of one of the six universal mobility moves.
struct WarmupMoveScreen: View {
    let name: String
    let remaining: Int
    let index: Int
    let count: Int
    let onTechnique: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            BlockPositionName(name: name)

            // Opens the mini-sheet and freezes the countdown (issue #34).
            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: "warmup-countdown")
                .padding(.top, 20)

            BlockDots(count: count, current: index)
                .padding(.top, 30)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            BlockSkipButton(title: String(localized: "Skip warm-up"),
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }
}

/// A running cool-down position, with the stage line a per-side one carries:
/// the structural hint on the first side, the pause's own instruction, then
/// the same "second side" marker the hold exercises use (issue #35).
struct CooldownPositionScreen: View {
    let position: CooldownPosition
    let stage: Cooldown.Stage
    let remaining: Int
    let index: Int
    let count: Int
    let onTechnique: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            BlockPositionName(name: position.name)
            if position.perSide {
                stageLine.padding(.top, 6)
            }

            // Opens the mini-sheet and freezes the countdown (issue #34) —
            // mid-pause too: the switch waits while you read.
            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: "cooldown-countdown")
                .padding(.top, 20)

            BlockDots(count: count, current: index)
                .padding(.top, 30)

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

/// The skeleton all three share: the block's content centred in whatever room
/// is left, and its escapes pinned under it.
///
/// The content scrolls rather than clips. At the largest accessibility sizes a
/// three-line position name ("Chest and shoulders at the wall", "Pecho y
/// hombros en la pared") plus the countdown outgrows the screen, and the one
/// thing a workout screen must never do is push its way out from under the
/// user — so the escapes stay put and the rest gives way. Below that size
/// nothing scrolls and nothing moved: the content is centred exactly as the
/// two Spacers used to centre it.
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

/// The name of the position, in the one size all three screens use. The long
/// Spanish and Portuguese names ("Estiramiento de los flexores de la cadera")
/// wrap to three lines at the largest Dynamic Type sizes; let them.
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
