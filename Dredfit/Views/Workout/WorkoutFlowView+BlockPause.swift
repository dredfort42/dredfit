//
//  The pause of the guided blocks, moved out of WorkoutFlowView when that
//  file neared the lint's hard ceiling. Both blocks share one pause, so it
//  belongs to neither block's file; the code moved unchanged.
//

import SwiftUI
import DredfitCore

// MARK: - The pause of the guided blocks (issue #61) and of a hands-free rest (R32)
//
// The state machine is BlockPause.State; this is the flow's half — the frozen
// screen's own end dates, the tones, and the way back in. Two blocks and one
// rest share it: the rest of a hands-free hold run STARTS the next set when it
// ends, so it is the one screen of the work phase where stepping away costs a
// set.
//
// The snapshot: the warm-up writes none by design, the cool-down keeps writing
// at position boundaries, and a paused rest is persisted as the rest it will
// be when the pause ends (`persistProgress`) — a process death outlives no
// pause, and writing nil there would read back as "no rest was running".
extension WorkoutFlowView {

    var reentering: Bool { blockPause.isReentering }

    func countdownIdentifier(reentering: Bool) -> String {
        reentering ? "reentry-countdown" : "getready-countdown"
    }

    /// Held, the only way on is Resume; counting back in, the tap holds again.
    func toggleBlockPause() {
        if blockPause.isHeld { resumeBlock() } else { pauseBlock() }
    }

    /// Freezes the stage where it stands: the end date comes off, so every
    /// tick guard goes quiet and no tone can be reached, while the seconds on
    /// screen stay put and rebuild it later.
    ///
    /// Not private since 05.09.2026: the two block ticks call it when they
    /// find a boundary that was crossed while the phone was elsewhere. That is
    /// the same fact this control states — nobody is training — reached
    /// without a tap, so it takes the same path rather than a second copy of
    /// it (UX review 05.09.2026).
    func pauseBlock(absence: Int = 0) {
        blockPause.hold()
        // The seconds from here to Resume are not seconds of the block, and
        // neither is the absence that led here — `warmupSec`/`cooldownSec` are
        // wall clock, so both used to be billed to the stretching (UX review
        // 05.09.2026, see `blockPausedSec`).
        beginBlockFreeze(absence: absence)
        warmupEndDate = nil
        cooldownEndDate = nil
        if case .rest = phase {
            restEndDate = nil
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

    private func resumeBlock() {
        announce(String(localized: "Resumed"))
        // The block starts costing time again here, whichever way back in it
        // takes: the re-entry's own count-in IS the block — it is the time
        // spent getting back into the position.
        endBlockFreeze()
        guard needsReentry else {
            // A frozen transition is its own way back in: its 3-2-1 and its
            // go are still ahead of it, and a lead-in here would count one
            // position down twice.
            blockPause.clear()
            restartFrozenStage()
            return
        }
        blockPause.beginReentry(seconds: BlockPause.reentrySeconds, now: .now)
    }

    private var needsReentry: Bool {
        switch phase {
        case .warmup:   return BlockPause.needsReentry(warmupStage)
        case .cooldown: return BlockPause.needsReentry(cooldownStage)
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
        withAnimation(countdownAnimation) {
            result = blockPause.tick(now: .now, signalSeconds: Self.countdownSignalSeconds)
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
        // out of a pause like any other, and the comment on that method states
        // the invariant this line used to break — a freeze left open runs to
        // the end of the block.
        //
        // It is reachable: the technique button is drawn on the "Get ready"
        // screen of a re-entry with no gate, and `openPositionTechnique`
        // opens a freeze there. Closing it again is `resumePositionCountdown`,
        // which returns early while `blockPause.isPaused` — and a re-entry IS
        // paused. In the cool-down nothing else would close it before
        // `finishCooldown`, because `tickCooldown` writes its stage inline
        // instead of going through `enterWarmupStage`'s equivalent, so the
        // measured length of the block came out as the few seconds before the
        // sheet rather than the five minutes actually stretched — and that
        // number is persisted and exported to Health (self-review 05.09.2026).
        clearBlockPause()
        restartFrozenStage()
    }

    /// The stage picks up the seconds it froze with, never its whole length:
    /// a pause must not quietly make the user hold a position twice.
    private func restartFrozenStage() {
        switch phase {
        case .warmup:
            warmupEndDate = Date.now.addingTimeInterval(TimeInterval(warmupRemaining))
        case .cooldown:
            cooldownEndDate = Date.now.addingTimeInterval(TimeInterval(cooldownRemaining))
        case .rest(let total):
            restRemaining = BlockPause.restAfterPause(remaining: restRemaining, total: total)
            restEndDate = Date.now.addingTimeInterval(TimeInterval(restRemaining))
            liveActivity.update(.init(phase: .rest, title: nextLabel,
                                      detail: restActivityDetail,
                                      restEndDate: restEndDate))
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
            if blockFrozenAt == nil { blockFrozenAt = .now }
        default:
            break
        }
    }

    /// …and closes it. Idempotent, because the ways out of a pause outnumber
    /// the ways in and several of them run through one another.
    func endBlockFreeze() {
        guard let began = blockFrozenAt else { return }
        blockPausedSec += max(0, Int(Date.now.timeIntervalSince(began)))
        blockFrozenAt = nil
    }

    /// VoiceOver stays on the control it has just used, so the state change
    /// has to be spoken; everyone else reads it under the countdown.
    ///
    /// Not private since 05.09.2026 either: the automatic boundaries of both
    /// blocks are the same problem in a harder form — the subtree the focus
    /// was in is replaced outright, so nothing is read at all — and this was
    /// the one place in the tree that already solved it (UX review
    /// 05.09.2026).
    func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
