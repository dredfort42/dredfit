//
//  WorkoutFlowView+Warmup.swift
//  Dredfit
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
