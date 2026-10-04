//
//  The pause of the guided blocks (issue #61) and of a hands-free rest (R32).
//
//  The state machine is BlockPause.State; this is the flow's half — the frozen
//  stage's own clocks, the tones, and the way back in. Two blocks and one rest
//  share it: the rest of a hands-free hold run STARTS the next set when it
//  ends, so it is the one screen of the work phase where stepping away costs a
//  set.
//
//  The snapshot: the warm-up writes none by design, the cool-down keeps writing
//  at position boundaries, and a paused rest is persisted as the rest it will
//  be when the pause ends (`persistProgress`) — a process death outlives no
//  pause, and writing nil there would read back as "no rest was running".
//

import Foundation
import DredfitCore

extension WorkoutSession {

    var reentering: Bool { blockPause.isReentering }

    /// Held, the only way on is Resume; counting back in, the tap holds again.
    func toggleBlockPause() {
        if blockPause.isHeld { resumeBlock() } else { pauseBlock() }
    }

    /// Freezes the stage where it stands: the end date comes off, so every
    /// tick guard goes quiet and no tone can be reached, while the seconds on
    /// screen stay put and rebuild it later.
    ///
    /// The blocks' tick calls it too, when it finds a boundary that was crossed
    /// while the phone was elsewhere. That is the same fact this control
    /// states — nobody is training — reached without a tap, so it takes the
    /// same path rather than a second copy of it.
    func pauseBlock(absence: Int = 0) {
        blockPause.hold()
        // The seconds from here to Resume are not seconds of the block, and
        // neither is the absence that led here — `warmupSec`/`cooldownSec` are
        // wall clock, so both used to be billed to the stretching (UX review
        // 05.09.2026, see `blockPausedSec`).
        beginBlockFreeze(absence: absence)
        warmup.clock.freeze()
        cooldown.clock.freeze()
        if case .rest = phase {
            restClock.freeze()
            // The lock screen counts down to a date, so a frozen rest has to
            // take the date away — otherwise it keeps counting to zero and
            // then shows a rest that ended while the app is holding it.
            liveActivity.update(.init(phase: .rest, title: nextLabel,
                                      detail: String(localized: "Paused"),
                                      restEndDate: nil))
            persistProgress()
        }
        announce(String(localized: "Paused"))
    }

    func resumeBlock() {
        announce(String(localized: "Resumed"))
        // The block starts costing time again here, whichever way back in it
        // takes: the re-entry's own count-in IS the block — it is the time
        // spent getting back into the position.
        endBlockFreeze()
        guard needsReentry else {
            // A frozen transition is its own way back in: its count and its
            // go are still ahead of it (`BlockPause.stageAfterPause` keeps
            // them there), and a lead-in here would count one position down
            // twice.
            blockPause.clear()
            restartFrozenStage()
            return
        }
        blockPause.beginReentry(seconds: BlockPause.reentrySeconds, now: now())
    }

    var needsReentry: Bool {
        switch phase {
        case .warmup:   return BlockPause.needsReentry(warmup.stage)
        case .cooldown: return BlockPause.needsReentry(cooldown.stage)
        // A rest is not a position to be counted back into — it is time being
        // given, and its own 3-2-1 is still ahead of it. What it takes instead
        // is a floor on what is left (`BlockPause.restAfterPause`), so nobody
        // is dropped into a plank two seconds after walking back in.
        case .rest:     return false
        default:        return false
        }
    }

    /// Held there is no end date at all, so nothing moves — the whole point.
    func tickBlockPause() {
        var result = BlockPause.Tick.nothing
        animate(.countdown) {
            result = blockPause.tick(now: now(), signalSeconds: Self.countdownSignalSeconds)
        }
        switch result {
        case .signal:            playTick()
        case .over:              endBlockReentry()
        case .nothing, .redraw:  break
        }
    }

    /// The go marks the moment the position starts again — the signal a "Get
    /// ready" ends on, for the same reason.
    func endBlockReentry() {
        playGo()
        // `clearBlockPause()`, not `blockPause.clear()`: the re-entry is a way
        // out of a pause like any other. A freeze can be open here — the
        // technique sheet is reachable from the re-entry's screen, and
        // `resumePositionCountdown` closes nothing while the re-entry (which
        // is paused) runs — and left open it would bill the stage that follows
        // as time the block stood still. The block's measured length is
        // persisted and exported to Health.
        clearBlockPause()
        restartFrozenStage()
    }

    /// A position picks up the seconds it froze with, never its whole length:
    /// a pause must not quietly make the user hold a position twice. A
    /// transition picks up at least the count-in (`BlockPause.stageAfterPause`).
    ///
    /// Started, not resumed, so the screen shows that floor before counting
    /// down from it: resumed from the lower second still on screen, the next
    /// tick can read as a step UP, which `signals` refuses — and the 3-2-1
    /// loses its 3.
    func restartFrozenStage() {
        switch phase {
        case .warmup:
            warmup.clock.start(BlockPause.stageAfterPause(remaining: warmup.clock.remaining,
                                                          stage: warmup.stage),
                               now: now())
        case .cooldown:
            cooldown.clock.start(BlockPause.stageAfterPause(remaining: cooldown.clock.remaining,
                                                            stage: cooldown.stage),
                                 now: now())
        case .rest(let total):
            let end = restClock.start(BlockPause.restAfterPause(remaining: restClock.remaining,
                                                                total: total),
                                      now: now())
            // Paused in its last seconds, a rest comes back on its floor, the
            // count-in: the second before its 3-2-1, which it never ticks onto.
            primeBeforeTheCount(showing: restClock.remaining)
            liveActivity.update(.init(phase: .rest, title: nextLabel,
                                      detail: restActivityDetail,
                                      restEndDate: end))
            persistProgress()
        default:
            break
        }
    }

    /// Entering a stage, skipping a position and leaving a block all end the
    /// pause with it: one state serves both blocks and must never outlive the
    /// screen that froze.
    func clearBlockPause() {
        // Every OTHER way out of a pause — a position skipped while held, a
        // block left while held, a new stage entered — closes the freeze too,
        // or the seconds it opened would run to the end of the block.
        endBlockFreeze()
        blockPause.clear()
    }

    /// Opens the interval a guided block is standing still for. It counts an
    /// ABSENCE that has already happened as well, because that is how a tick
    /// discovers a pause: the block ran out while the phone was elsewhere, and
    /// the seconds between the boundary and the app coming back are the
    /// clearest case of time nobody spent stretching.
    ///
    /// Only inside the two blocks: a paused REST is the engine's time, and
    /// `restSetSec` is budgeted whether or not it is paused.
    func beginBlockFreeze(absence: Int = 0) {
        switch phase {
        case .warmup, .cooldown:
            blockPausedSec += max(0, absence)
            // Never restarted: pausing again while counting back in must not
            // throw away the interval already open.
            if blockFrozenAt == nil { blockFrozenAt = now() }
        default:
            break
        }
    }

    /// …and closes it. Idempotent, because the ways out of a pause outnumber
    /// the ways in and several of them run through one another.
    func endBlockFreeze() {
        guard let began = blockFrozenAt else { return }
        blockPausedSec += max(0, Int(now().timeIntervalSince(began)))
        blockFrozenAt = nil
    }

    /// VoiceOver stays on the control it has just used, so the state change
    /// has to be spoken; everyone else reads it under the countdown. The
    /// automatic boundaries of both blocks are the same problem in a harder
    /// form: the subtree the focus was in is replaced outright, so nothing is
    /// read at all.
    func announce(_ message: String) {
        signals.announce(message)
    }
}
