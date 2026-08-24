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
    /// The
    /// warm-up is OFFERED, not started.
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
            Text("\(Warmup.moves.count) positions · about \(Self.warmupIntroMinutes) min")
                .dredfitFont(13.5)
                .foregroundStyle(Theme.ink3)
                .padding(.top, 6)
                .accessibilityIdentifier("warmup-intro-length")
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

    /// The block is fixed, so this is a constant — but it is DERIVED, because
    /// a hand-typed 5 would go stale the first time a move is added. Rounded
    /// up, like the cool-down's: a promise the block overruns is worse than
    /// one it beats.
    static var warmupIntroMinutes: Int {
        let seconds = Warmup.moves.indices.reduce(0) { total, index in
            total + Warmup.stageSeconds(.getReady, index: index)
                  + Warmup.stageSeconds(.move, index: index)
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    /// Both warm-up screens are the same beat as far as the rest of the view
    /// is concerned: not a step of the work, and WARM-UP on the lock screen.
    var isWarmingUp: Bool { phase == .warmup || phase == .warmupIntro }

    /// The person said yes. This is the start the view used to make for them
    /// on appear — nothing is persisted, exactly as before: there is no
    /// progress yet to survive anything.
    func beginWarmup() {
        phase = .warmup
        startWarmupPosition(0)
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
            GetReadyScreen(name: Warmup.moves[warmupIndex].name,
                           remaining: reentering ? blockPause.reentryRemaining : warmupRemaining,
                           index: warmupIndex, count: Warmup.moves.count,
                           countdownIdentifier: countdownIdentifier(reentering: reentering),
                           blockSkipTitle: String(localized: "Skip warm-up"),
                           paused: blockPause.isHeld,
                           onTechnique: { openWarmupTechnique() },
                           onStart: { reentering ? endBlockReentry() : startWarmupMoveNow() },
                           onPauseToggle: { toggleBlockPause() },
                           onSkipPosition: { skipWarmupPosition() },
                           onSkipBlock: { finishWarmup() })
        } else {
            warmupMoveView
        }
    }

    var warmupMoveView: some View {
        WarmupMoveScreen(name: Warmup.moves[warmupIndex].name,
                         remaining: warmupRemaining,
                         index: warmupIndex, count: Warmup.moves.count,
                         paused: blockPause.isHeld,
                         onTechnique: { openWarmupTechnique() },
                         onPauseToggle: { toggleBlockPause() },
                         onSkipPosition: { skipWarmupPosition() },
                         onSkipBlock: { finishWarmup() })
    }

    func openWarmupTechnique() {
        openPositionTechnique(PositionTechnique(warmup: Warmup.moves[warmupIndex]))
    }

    /// Skipping from the transition skips the move it was announcing.
    func skipWarmupPosition() {
        if warmupIndex + 1 < Warmup.moves.count {
            startWarmupPosition(warmupIndex + 1)
        } else {
            finishWarmup()
        }
    }

    func startWarmupPosition(_ index: Int) {
        enterWarmupStage(index: index, stage: .getReady,
                         remaining: Warmup.stageSeconds(.getReady, index: index))
    }

    /// The transition is a floor on the pause between positions, never a wait.
    func startWarmupMoveNow() {
        enterWarmupStage(index: warmupIndex, stage: .move,
                         remaining: Warmup.stageSeconds(.move, index: warmupIndex))
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
            if newRemaining <= Self.countdownSignalSeconds && newRemaining < warmupRemaining {
                playTick()
            }
            // Animated so contentTransition(.numericText) rolls the digits —
            // a bare mutation swaps them with no transaction.
            withAnimation(.linear(duration: 0.3)) { warmupRemaining = newRemaining }
            return
        }
        // Warmup.advance absorbs whatever a long absence already covered.
        guard let next = Warmup.advance(from: (warmupIndex, warmupStage),
                                        overshoot: Int(max(0, -end.timeIntervalSinceNow))) else {
            // The block is over: done, not go — a tap starts the first exercise (#186).
            playDone()
            finishWarmup()
            return
        }
        // A transition opening is the done of the position before it; the go
        // marks where a movement starts, the end of the transition. `entered`
        // names the first boundary crossed and `stage` where the overshoot
        // landed: a long absence crosses several, so anything but a landing on
        // the boundary that opened the run stays silent — the signal belongs
        // to what is on screen.
        if next.entered == .getReady, next.stage == .getReady {
            playDone()
        } else if next.entered != .getReady, next.stage != .getReady {
            playGo()
        }
        enterWarmupStage(index: next.index, stage: next.stage, remaining: next.remaining)
    }

    func finishWarmup() {
        clearBlockPause()
        warmupEndDate = nil
        phase = .work
        liveActivity.update(activityWorkState())
        persistProgress()
    }
}
