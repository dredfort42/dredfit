//
//  The screens of the warm-up block; the block itself is
//  WorkoutSession+Warmup.swift.
//

import SwiftUI
import DredfitCore

// MARK: - Warm-up

extension WorkoutFlowView {
    /// The warm-up is OFFERED, not started.
    ///
    /// Same two answers as the cool-down and the same tone: no consequence
    /// attaches to saying no. The one difference is the reason on offer —
    /// arriving already warm is ordinary, and the screen says so rather than
    /// making the person justify a skip by walking out of a countdown.
    var warmupIntroView: some View {
        // The scroll of `BlockLayout`, for the reason stated there and one
        // more of its own (UX review 05.09.2026): this screen and its
        // cool-down twin were the only ones of the flow NOT wrapped, and they
        // now carry two lines more. At the accessibility text sizes a bare
        // VStack overflows both ends and takes the decline button off the
        // bottom with it. Below that size nothing scrolls and nothing moved.
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Warm-up")
                        .dredfitFont(32, weight: .heavy)
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text("A few easy minutes to get the body ready. Skip it if you are already warm.")
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    // ink3 → ink2: this is small TEXT, and ink3 is 2.35:1 on
                    // the light background — under the 4.5:1 small text needs.
                    // Owner's call, UX review 05.09.2026: the low-contrast ink3
                    // text across the app was an oversight, and ink3 is a
                    // graphics tone from here on.
                    Text("\(flow.warmupMoves.count) positions · about \(flow.warmupIntroMinutes) min")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 6)
                    warmupCompositionLines
                    Spacer(minLength: 0)
                    PrimaryButton(title: String(localized: "Start the warm-up")) { flow.beginWarmup() }
                        .accessibilityIdentifier("warmup-start")
                    // No question on THIS one, unlike the escape inside the
                    // block: the offer's own "no" is the answer it asked for.
                    Button(GuidedBlock.warmup.skipTitle) { flow.declineWarmup() }
                        .dredfitFont(14.5)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 4)
                        .accessibilityIdentifier("warmup-intro-skip")
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height,
                       alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// What the offer is actually offering.
    ///
    /// UX review 05.09.2026: the only screen where "do it or not" is decided
    /// named no movement at all, while the composition changes from session to
    /// session (six compositions of six out of a pool of nine) and could be
    /// read only one name at a time INSIDE the block being decided about. The
    /// names are already localized — they are the same strings the running
    /// screen shows — and the list needs no separator of its own: the locale's
    /// own list format has one.
    ///
    /// The second line is the mechanic that has existed since 1.7 and lived
    /// behind the very decision it should be changing: someone with twenty
    /// minutes instead of thirty cut the whole block because the screen
    /// offered nothing smaller.
    ///
    /// ink2, like every other word on the screen: at 2.35:1 in the light
    /// theme ink3 does not carry small text (owner, 05.09.2026 — the
    /// low-contrast ink3 text was an oversight, not a decision).
    @ViewBuilder
    private var warmupCompositionLines: some View {
        Text(flow.warmupMoves.map(\.name).formatted(.list(type: .and)))
            .dredfitFont(13.5)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        Text("Any position can be skipped as you go.")
            .dredfitFont(13.5)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    /// The way back in from a pause wears the transition's screen, because it
    /// is the same beat: the name of the position, the 3-2-1, then the
    /// position. Only the seconds it counts and what "I'm ready" cuts short
    /// differ.
    var warmupView: some View {
        // The Group is what carries the observer below: the two branches are
        // different screens and swap as the stage does, and a modifier applied
        // inside either of them would be torn down with it.
        Group {
            if flow.reentering || flow.warmupStage == .getReady {
                GetReadyScreen(name: flow.warmupMove.name,
                               remaining: flow.reentering ? flow.blockPause.reentryRemaining : flow.warmupClock.remaining,
                               index: flow.warmupIndex, count: flow.warmupMoves.count,
                               countdownIdentifier: countdownIdentifier(reentering: flow.reentering),
                               block: .warmup,
                               paused: flow.blockPause.isHeld,
                               // The way back in is not a transition to cut: its
                               // "I'm ready" ends it outright, so it keeps one.
                               countingIn: !flow.reentering
                                   && flow.warmupClock.remaining <= GetReady.countInSeconds,
                               onTechnique: { openWarmupTechnique() },
                               onStart: { flow.reentering ? flow.endBlockReentry() : flow.countInWarmupMove() },
                               onPauseToggle: { flow.toggleBlockPause() },
                               onSkipPosition: { flow.skipWarmupPosition() },
                               onSkipBlock: { flow.finishWarmup() })
            } else {
                warmupMoveView
            }
        }
        // The OLD list is what the rebase needs and the only place it still
        // exists: `warmupMoves` is computed, so by the time this runs it
        // already answers with the new composition (review 06.09.2026).
        .onChange(of: flow.warmupMoves.map(\.id)) { previous, _ in
            flow.rebaseWarmupOnComposition(was: previous)
        }
    }

    var warmupMoveView: some View {
        WarmupMoveScreen(move: flow.warmupMove,
                         stage: flow.warmupStage,
                         remaining: flow.warmupClock.remaining,
                         index: flow.warmupIndex, count: flow.warmupMoves.count,
                         paused: flow.blockPause.isHeld,
                         onTechnique: { openWarmupTechnique() },
                         onPauseToggle: { flow.toggleBlockPause() },
                         onSkipPosition: { flow.skipWarmupPosition() },
                         onSkipBlock: { flow.finishWarmup() })
    }

    func openWarmupTechnique() {
        openPositionTechnique(PositionTechnique(warmup: flow.warmupMove))
    }

}
