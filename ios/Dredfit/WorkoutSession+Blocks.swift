//
//  The run of a guided block — the warm-up's or the cool-down's — on the one
//  engine both share (GuidedBlock.swift). What differs between the two blocks
//  is how each begins, what it is composed of and where it ends; those live
//  in +Warmup and +Cooldown.
//

import Foundation
import DredfitCore

extension WorkoutSession {

    /// Where `block` stands.
    subscript(run block: GuidedBlock) -> GuidedBlockRun {
        get {
            switch block {
            case .warmup: return warmup
            case .cooldown: return cooldown
            }
        }
        set {
            switch block {
            case .warmup: warmup = newValue
            case .cooldown: cooldown = newValue
            }
        }
    }

    /// What `block` is composed of: the warm-up's list is read live, the
    /// cool-down's was drawn once when the work ended.
    func positions(of block: GuidedBlock) -> [any GuidedPosition] {
        switch block {
        case .warmup: return warmupMoves
        case .cooldown: return cooldownPositions
        }
    }

    func startPosition(_ index: Int, of block: GuidedBlock) {
        enterStage(index: index, stage: .getReady,
                   remaining: block.stageSeconds(.getReady, of: positions(of: block)[index]),
                   of: block)
    }

    /// The transition is a floor on the pause between positions, never a wait.
    ///
    /// "I'm ready" does not drop the position under the thumb, though: it cuts
    /// the transition down to a count-in and lets the SAME screen run that
    /// out, so the 3-2-1 and the go still arrive. The tap means "I'm in
    /// position", not "start the clock this instant".
    ///
    /// `min`, never a plain count-in: the reserve the two blocks are budgeted
    /// against is spent to the second (`GetReady.setupSupplementSec`), so a
    /// tap may only shorten what is already running. Tapped with less than
    /// the count-in left, it changes nothing — there was no jump to soften.
    func countIn(_ block: GuidedBlock) {
        let run = self[run: block]
        enterStage(index: run.index, stage: .getReady,
                   remaining: min(run.clock.remaining, GetReady.countInSeconds), of: block)
    }

    func enterStage(index: Int, stage: GuidedStage, remaining: Int, of block: GuidedBlock) {
        clearBlockPause()   // a new stage is never entered still frozen
        self[run: block].index = index
        self[run: block].stage = stage
        self[run: block].clock.start(remaining, now: now())
    }

    /// Skipping from the transition skips the position it was announcing.
    func skipPosition(of block: GuidedBlock) {
        let next = self[run: block].index + 1
        if next < positions(of: block).count {
            startPosition(next, of: block)
        } else {
            finish(block)
        }
    }

    func finish(_ block: GuidedBlock) {
        switch block {
        case .warmup: finishWarmup()
        case .cooldown: finishCooldown()
        }
    }

    func tick(_ block: GuidedBlock) {
        let overshoot: Int
        switch self[run: block].clock.read(now: now()) {
        case .unchanged:
            return
        case .second(let second):
            // No 3-2-1 inside the switch pause: the ticks would bury the tone
            // the pause opened with. The transition is the opposite — the
            // 3-2-1 IS its signal.
            if self[run: block].stage != .switchPause,
               self[run: block].clock.signals(second, within: Self.countdownSignalSeconds) {
                playTick()
            }
            // Animated so contentTransition(.numericText) rolls the digits —
            // a bare mutation swaps them with no transaction.
            animate(.countdown) { self[run: block].clock.show(second) }
            return
        case .ended(let late):
            overshoot = Int(max(0, late))
        }
        // A boundary crossed while the phone was elsewhere is not a boundary
        // the person was at (UX review 05.09.2026). A block that swallowed the
        // stages an absence covered would put someone into the first working
        // set cold, announced by a signal nobody could hear. The rest already
        // refuses that — `SetFacts.restHandsOverWithCountIn` hands the next set
        // a count-in when its go went nowhere — and a block needs no new screen
        // to do the same: freeze on the stage that was running, and the way
        // back in is Resume with the 3-2-1 it already has.
        if overshoot > BlockPause.absenceSeconds {
            // The absence itself is handed over: it is time the block stood
            // still, and the block's length is wall clock (`blockPausedSec`).
            pauseBlock(absence: overshoot)
            return
        }
        // `advance` absorbs whatever a short overrun already covered.
        let positions = positions(of: block)
        guard let next = block.advance(from: (self[run: block].index, self[run: block].stage),
                                       overshoot: overshoot, positions: positions) else {
            switch block {
            // Done, not go — a tap starts the first exercise (#186).
            case .warmup: playDone()
            // The whole workout is assembled — the finale, not another start
            // (#84). Skipping the cool-down stays silent: a tap is a tap.
            case .cooldown: playWorkoutDone()
            }
            finish(block)
            return
        }
        // A transition opening is the done of the position before it; the go
        // marks where a position starts, the end of the transition. `entered`
        // names the first boundary crossed and `stage` where the overshoot
        // landed: a long absence crosses several, so anything but a landing on
        // the boundary that opened the run stays silent — the signal belongs
        // to what is on screen. The switch is its own tone: a done only where
        // a whole position ended, never at the halfway point of a split one.
        //
        // Each audible boundary is SPOKEN as well (UX review 05.09.2026).
        // VoiceOver stays where it was and the subtree it was in has just been
        // replaced, so nothing is read: the tone was the only channel, and it
        // is behind the same switch as the haptic. The words are the ones the
        // new screen already shows — no string of their own to drift.
        let position = positions[next.index]
        switch (next.entered, next.stage) {
        case (.getReady, .getReady):
            playDone()
            announce(String(localized: "Get ready: \(position.name)"))
        case (.getReady, _), (_, .getReady):
            break
        case (.switchPause, _):
            playSwitch()
            // Only a split position has this stage, so `halves` is there —
            // and nothing is invented if it somehow is not.
            if let halves = position.halves { announce(SplitStageWords(halves: halves).switching) }
        default:
            playGo()
            if next.stage == .secondHalf, let halves = position.halves {
                announce(SplitStageWords(halves: halves).secondHalf)
            } else {
                announce(position.name)
            }
        }
        enterStage(index: next.index, stage: next.stage, remaining: next.remaining, of: block)
        // Re-stamped so a long cool-down keeps the session resumable — it
        // restores onto the rating, never into a stretch. The warm-up writes
        // no snapshot of its own (see +BlockPause).
        if block == .cooldown, next.entered == .getReady { persistProgress() }
    }
}
