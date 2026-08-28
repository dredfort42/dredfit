//
//  The pause of the guided blocks, moved out of WorkoutFlowView when that
//  file neared the lint's hard ceiling. Both blocks share one pause, so it
//  belongs to neither block's file; the code moved unchanged.
//

import SwiftUI
import DredfitCore

// MARK: - The pause of the guided blocks (issue #61)
//
// The state machine is BlockPause.State; this is the flow's half — the block's
// own end dates, the tones, and the screen. The snapshot is untouched: the
// warm-up writes none by design, the cool-down keeps writing at position
// boundaries, and process death while paused restores by the rules it had.
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
    private func pauseBlock() {
        blockPause.hold()
        warmupEndDate = nil
        cooldownEndDate = nil
        announce(String(localized: "Paused"))
    }

    private func resumeBlock() {
        announce(String(localized: "Resumed"))
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
        default:        return false
        }
    }

    /// Held there is no end date at all, so nothing moves — the whole point.
    func tickBlockPause() {
        var result = BlockPause.Tick.nothing
        withAnimation(.linear(duration: 0.3)) {
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
        blockPause.clear()
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
        default:
            break
        }
    }

    /// Entering a stage, skipping a position and leaving a block all end the
    /// pause with it: one state serves both blocks and must never outlive the
    /// screen that froze.
    func clearBlockPause() { blockPause.clear() }

    /// VoiceOver stays on the control it has just used, so the state change
    /// has to be spoken; everyone else reads it under the countdown.
    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
