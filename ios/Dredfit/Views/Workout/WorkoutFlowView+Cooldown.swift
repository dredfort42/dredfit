//
//  The screens of the cool-down block (issue #28); the block itself is
//  WorkoutSession+Cooldown.swift.
//

import SwiftUI
import DredfitCore

// MARK: - Cool-down (issue #28)

extension WorkoutFlowView {
    /// The cool-down is OFFERED, not started.
    ///
    /// The tone is the wave's own: it is proposed, never required, and the
    /// screen carries no consequence for saying no. The warm-up keeps its
    /// footer skip and gains no confirmation of its own — the owner asked for
    /// this one only, and symmetry here would be a decision nobody made.
    var cooldownIntroView: some View {
        // Wrapped for the reason its warm-up twin states (UX review
        // 05.09.2026): these two were the only screens of the flow with no
        // scroll under them, and at the accessibility text sizes the decline
        // button goes off the bottom of a bare VStack.
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Cool-down")
                        .dredfitFont(32, weight: .heavy)
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                    // The third sentence says what the block already IS and
                    // never admitted (UX review 05.09.2026): three of the six
                    // positions are drawn from the movements actually
                    // performed today, so the person saying no knows what
                    // they are turning down. "Some", deliberately — two
                    // positions and the rest pose are fixed, and a short
                    // session tops the middle three up from a fixed pool.
                    Text("""
                        The work is done. A few minutes of stretching helps it settle. \
                        Some of the positions follow the movements you did today.
                        """)
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    // ink2, for the reason the warm-up offer states: ink3 is
                    // 2.35:1 in the light theme and does not carry small text
                    // (owner, UX review 05.09.2026).
                    Text("\(flow.cooldownPositions.count) positions · about \(flow.cooldownIntroMinutes) min")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    PrimaryButton(title: String(localized: "Start the cool-down")) { flow.beginCooldown() }
                        .accessibilityIdentifier("cooldown-start")
                    // No question here, unlike the escape inside the block:
                    // the offer's own "no" is the answer it asked for.
                    Button(GuidedBlock.cooldown.skipTitle) { flow.declineCooldown() }
                        .dredfitFont(14.5)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 4)
                        .accessibilityIdentifier("cooldown-intro-skip")
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height,
                       alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The way back in borrows the transition's screen here too — see
    /// `warmupView`.
    var cooldownView: some View {
        // Grouped for the reason `warmupView` states: the observer belongs to
        // the block, not to whichever of the two screens is up.
        Group {
            if flow.reentering || flow.cooldownStage == .getReady {
                GetReadyScreen(name: flow.cooldownPositions[flow.cooldownIndex].name,
                               remaining: flow.reentering ? flow.blockPause.reentryRemaining : flow.cooldownClock.remaining,
                               index: flow.cooldownIndex, count: flow.cooldownPositions.count,
                               countdownIdentifier: countdownIdentifier(reentering: flow.reentering),
                               block: .cooldown,
                               paused: flow.blockPause.isHeld,
                               countingIn: !flow.reentering
                                   && flow.cooldownClock.remaining <= GetReady.countInSeconds,
                               onTechnique: { openCooldownTechnique() },
                               onStart: { flow.reentering ? flow.endBlockReentry() : flow.countInCooldownPosition() },
                               onPauseToggle: { flow.toggleBlockPause() },
                               onSkipPosition: { flow.skipCooldownPosition() },
                               onSkipBlock: { flow.finishCooldown() })
            } else {
                cooldownPositionView
            }
        }
        .onChange(of: store.settings.hiddenBlockMoveIDs) { _, _ in
            flow.rebaseCooldownOnComposition()
        }
    }

    var cooldownPositionView: some View {
        CooldownPositionScreen(position: flow.cooldownPositions[flow.cooldownIndex],
                               stage: flow.cooldownStage,
                               remaining: flow.cooldownClock.remaining,
                               index: flow.cooldownIndex, count: flow.cooldownPositions.count,
                               paused: flow.blockPause.isHeld,
                               onTechnique: { openCooldownTechnique() },
                               onPauseToggle: { flow.toggleBlockPause() },
                               onSkipPosition: { flow.skipCooldownPosition() },
                               onSkipBlock: { flow.finishCooldown() })
    }

    func openCooldownTechnique() {
        openPositionTechnique(PositionTechnique(cooldown: flow.cooldownPositions[flow.cooldownIndex]))
    }

}
