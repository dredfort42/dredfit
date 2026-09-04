//
//  The warm-up block of the workout flow, split out of WorkoutFlowView the
//  way the cool-down already was — one file per guided block, and this one
//  stays clear of the lint's ceiling. The code moved unchanged.
//

import SwiftUI
import DredfitCore

// MARK: - Warm-up
//
// A same-file extension so the view struct stays within the linter's size for
// a type body. @State storage stays in the struct; only behaviour here.
extension WorkoutFlowView {
    /// The warm-up is OFFERED, not started.
    ///
    /// Same two answers as the cool-down and the same tone: no consequence
    /// attaches to saying no. The one difference is the reason on offer —
    /// arriving already warm is ordinary, and the screen says so rather than
    /// making the person justify a skip by walking out of a countdown.
    var warmupIntroView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("Warm-up")
                .dredfitFont(32, weight: .heavy)
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
            Text("A few easy minutes to get the body ready. Skip it if you are already warm.")
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text("\(warmupMoves.count) positions · about \(warmupIntroMinutes) min")
                .dredfitFont(13.5)
                .foregroundStyle(Theme.ink3)
                .padding(.top, 6)
            Spacer()
            PrimaryButton(title: String(localized: "Start the warm-up")) { beginWarmup() }
                .accessibilityIdentifier("warmup-start")
            Button(String(localized: "Skip the warm-up")) { declineWarmup() }
                .dredfitFont(14.5)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 4)
                .accessibilityIdentifier("warmup-intro-skip")
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The six moves of THIS session (§40.1: nine in the pool, six on
    /// screen). A pure function of the session number, so a restored snapshot
    /// recomputes the same list rather than carrying it.
    var warmupMoves: [WarmupMove] { Warmup.moves(for: session) }

    /// What the offer screen promises for THIS session's composition.
    var warmupIntroMinutes: Int { Warmup.introMinutes(warmupMoves) }

    /// Both warm-up screens are the same beat as far as the rest of the view
    /// is concerned: not a step of the work, and WARM-UP on the lock screen.
    var isWarmingUp: Bool { phase == .warmup || phase == .warmupIntro }

    /// The person said yes. This is the start the view used to make for them
    /// on appear — nothing is persisted, exactly as before: there is no
    /// progress yet to survive anything.
    func beginWarmup() {
        phase = .warmup
        warmupBeganAt = .now
        startWarmupPosition(0)
        // "Start the warm-up" is a start tap like "I'm ready", so the block
        // opens on the count-in, not on the full travel time between two
        // positions: the person is standing at their mat with a thumb on the
        // glass, not walking to the next one. Only the AUTOMATIC transitions
        // — the ones no tap opened — keep `GetReady.seconds`.
        countInWarmupMove()
    }

    /// …or no. The same ending the footer's "Skip warm-up" already had, and
    /// the same one taking every move in turn arrives at: straight to the
    /// work, with nothing recorded about the block either way.
    func declineWarmup() {
        finishWarmup()
    }

    /// The way back in from a pause wears the transition's screen, because it
    /// is the same beat: the name of the position, the 3-2-1, then the
    /// position. Only the seconds it counts and what "I'm ready" cuts short
    /// differ.
    @ViewBuilder
    var warmupView: some View {
        if reentering || warmupStage == .getReady {
            GetReadyScreen(name: warmupMove.name,
                           remaining: reentering ? blockPause.reentryRemaining : warmupRemaining,
                           index: warmupIndex, count: warmupMoves.count,
                           countdownIdentifier: countdownIdentifier(reentering: reentering),
                           blockSkipTitle: String(localized: "Skip warm-up"),
                           // Stated for the same reason `skip-cooldown` states it
                           // on the cool-down twin below: the default is
                           // `identifier ?? title`, and `title` is already
                           // localized, so an omitted argument makes the
                           // accessibility identifier move with the display
                           // language. The warm-up side was the only one of the
                           // two that never said it.
                           blockSkipIdentifier: "skip-warmup",
                           paused: blockPause.isHeld,
                           // The way back in is not a transition to cut: its
                           // "I'm ready" ends it outright, so it keeps one.
                           countingIn: !reentering
                               && warmupRemaining <= GetReady.countInSeconds,
                           onTechnique: { openWarmupTechnique() },
                           onStart: { reentering ? endBlockReentry() : countInWarmupMove() },
                           onPauseToggle: { toggleBlockPause() },
                           onSkipPosition: { skipWarmupPosition() },
                           onSkipBlock: { finishWarmup() })
        } else {
            warmupMoveView
        }
    }

    var warmupMoveView: some View {
        WarmupMoveScreen(move: warmupMove,
                         stage: warmupStage,
                         remaining: warmupRemaining,
                         index: warmupIndex, count: warmupMoves.count,
                         paused: blockPause.isHeld,
                         onTechnique: { openWarmupTechnique() },
                         onPauseToggle: { toggleBlockPause() },
                         onSkipPosition: { skipWarmupPosition() },
                         onSkipBlock: { finishWarmup() })
    }

    /// The move on screen. Clamped: the index is state, and a composition
    /// that changed under a restored snapshot must not index out of bounds.
    var warmupMove: WarmupMove {
        warmupMoves[min(max(warmupIndex, 0), warmupMoves.count - 1)]
    }

    func openWarmupTechnique() {
        openPositionTechnique(PositionTechnique(warmup: warmupMove))
    }

    /// Skipping from the transition skips the move it was announcing.
    func skipWarmupPosition() {
        if warmupIndex + 1 < warmupMoves.count {
            startWarmupPosition(warmupIndex + 1)
        } else {
            finishWarmup()
        }
    }

    func startWarmupPosition(_ index: Int) {
        enterWarmupStage(index: index, stage: .getReady,
                         remaining: Warmup.stageSeconds(.getReady, of: warmupMoves[index]))
    }

    /// The transition is a floor on the pause between positions, never a wait.
    ///
    /// "I'm ready" no longer drops the move under the thumb, though: it cuts
    /// the transition down to a count-in and lets the SAME screen run that
    /// out, so the 3-2-1 and the go still arrive. The tap means "I'm in
    /// position", not "start the clock this instant".
    ///
    /// `min`, never a plain five: the reserve the two blocks are budgeted
    /// against is spent to the second (`GetReady.setupSupplementSec`), so a
    /// tap may only shorten what is already running. Tapped with less than
    /// the count-in left, it changes nothing — there was no jump to soften.
    func countInWarmupMove() {
        enterWarmupStage(index: warmupIndex, stage: .getReady,
                         remaining: min(warmupRemaining, GetReady.countInSeconds))
    }

    func enterWarmupStage(index: Int, stage: Warmup.Stage, remaining: Int) {
        clearBlockPause()   // a new stage is never entered still frozen
        warmupIndex = index
        warmupStage = stage
        warmupRemaining = remaining
        warmupEndDate = Date.now.addingTimeInterval(TimeInterval(remaining))
    }

    func tickWarmup() {
        guard let end = warmupEndDate else { return }
        let newRemaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        guard newRemaining != warmupRemaining else { return }
        if newRemaining > 0 {
            // No 3-2-1 inside the switch pause, for the reason `tickCooldown`
            // gives: the ticks would bury the tone the pause opened with.
            if warmupStage != .switchPause,
               newRemaining <= Self.countdownSignalSeconds && newRemaining < warmupRemaining {
                playTick()
            }
            // Animated so contentTransition(.numericText) rolls the digits —
            // a bare mutation swaps them with no transaction.
            withAnimation(.linear(duration: 0.3)) { warmupRemaining = newRemaining }
            return
        }
        // Warmup.advance absorbs whatever a long absence already covered.
        guard let next = Warmup.advance(from: (warmupIndex, warmupStage),
                                        overshoot: Int(max(0, -end.timeIntervalSinceNow)),
                                        moves: warmupMoves) else {
            // The block is over: done, not go — a tap starts the first exercise (#186).
            playDone()
            finishWarmup()
            return
        }
        // A transition opening is the done of the move before it; the go marks
        // where a movement starts, the end of the transition. `entered` names
        // the first boundary crossed and `stage` where the overshoot landed: a
        // long absence crosses several, so anything but a landing on the
        // boundary that opened the run stays silent — the signal belongs to
        // what is on screen.
        //
        // The switch of §41.12 is its own tone, and it is chosen the way the
        // cool-down chooses it (`tickCooldown`): a done only where a whole
        // move ended, never at the halfway point of a unilateral one.
        switch (next.entered, next.stage) {
        case (.getReady, .getReady):         playDone()
        case (.getReady, _), (_, .getReady): break
        case (.switchPause, _):              playSwitch()
        default:                             playGo()
        }
        enterWarmupStage(index: next.index, stage: next.stage, remaining: next.remaining)
    }

    func finishWarmup() {
        clearBlockPause()
        // Resolved here because every ending arrives here: declined, skipped
        // from the footer, or every move taken in turn. Written once — this
        // runs again on a re-entry and a second span would be the whole
        // detour, not the block.
        if warmupSec == nil {
            warmupSec = BlockRun.seconds(began: warmupBeganAt, ended: .now)
        }
        warmupEndDate = nil
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
    }
}
