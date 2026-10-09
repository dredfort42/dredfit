//
//  The pause of the guided blocks (issue #61) and of a hands-free rest: the
//  flow's half — the frozen stage's own clocks, the tones, and the way back
//  in. Port of ios/Dredfit/WorkoutSession+BlockPause.swift.
//
//  The snapshot: the warm-up writes none by design, the cool-down writes at
//  position boundaries, and a paused rest is persisted as the seconds it froze
//  with (`persistProgress`) — a process death outlives no pause.
//

package com.dredfit.workout

import com.dredfit.workout.WorkoutSession.Companion.countdownSignalSeconds
import com.dredfit.workout.WorkoutSession.Phase

val WorkoutSession.reentering: Boolean get() = blockPause.isReentering

/** Held, the only way on is Resume; counting back in, the tap holds again. */
fun WorkoutSession.toggleBlockPause() {
    if (blockPause.isHeld) resumeBlock() else pauseBlock()
}

/** Freezes the stage where it stands. The blocks' tick calls it too, when it
 *  finds a boundary crossed while the phone was elsewhere — the same fact,
 *  reached without a tap. */
fun WorkoutSession.pauseBlock(absence: Int = 0) {
    blockPause.hold()
    beginBlockFreeze(absence = absence)
    warmup.clock.freeze()
    cooldown.clock.freeze()
    if (phase is Phase.Rest) {
        restClock.freeze()
        // The tile counts down to a date: a frozen rest takes it away.
        liveActivity.update(ActivityState(ActivityState.Phase.rest, nextLabel, Words.of("Paused"), null))
        persistProgress()
    }
    announce(Words.of("Paused"))
}

fun WorkoutSession.resumeBlock() {
    announce(Words.of("Resumed"))
    // The re-entry's own count-in IS the block.
    endBlockFreeze()
    if (!needsReentry) {
        // A frozen transition is its own way back in.
        blockPause.clear()
        restartFrozenStage()
        return
    }
    blockPause.beginReentry(seconds = BlockPause.reentrySeconds, now = now())
    // Starts on its four, which no tick reports.
    primeBeforeTheCount(showing = blockPause.reentryRemaining)
}

val WorkoutSession.needsReentry: Boolean
    get() = when (phase) {
        Phase.Warmup -> BlockPause.needsReentry(warmup.stage)
        Phase.Cooldown -> BlockPause.needsReentry(cooldown.stage)
        // A rest is time being given: a floor, not a re-entry.
        else -> false
    }

/** Held there is no end date at all, so nothing moves — the whole point. */
fun WorkoutSession.tickBlockPause() {
    var result = BlockPause.Tick.nothing
    animate(WorkoutSession.Motion.countdown) {
        result = blockPause.tick(now(), signalSeconds = countdownSignalSeconds)
    }
    when (result) {
        BlockPause.Tick.signal -> playTick()
        // A longer way back in reaches its four here.
        BlockPause.Tick.redraw -> primeBeforeTheCount(showing = blockPause.reentryRemaining)
        BlockPause.Tick.over -> endBlockReentry()
        BlockPause.Tick.nothing -> Unit
    }
}

/** The go marks the moment the position starts again. `clearBlockPause`,
 *  not `blockPause.clear()`: a freeze can be open here. */
fun WorkoutSession.endBlockReentry() {
    playGo()
    clearBlockPause()
    restartFrozenStage()
}

/**
 * A position picks up the seconds it froze with; a transition at least the
 * count-in. STARTED, not resumed: resumed from the lower second still on
 * screen, the next tick reads as a step UP, `signals` refuses it, and the
 * 3-2-1 loses its 3 (#289).
 */
fun WorkoutSession.restartFrozenStage() {
    when (val p = phase) {
        Phase.Warmup -> {
            warmup.clock.start(BlockPause.stageAfterPause(remaining = warmup.clock.remaining, stage = warmup.stage), now())
            primeComingBack()
        }
        Phase.Cooldown -> {
            cooldown.clock.start(BlockPause.stageAfterPause(remaining = cooldown.clock.remaining, stage = cooldown.stage), now())
            primeComingBack()
        }
        is Phase.Rest -> {
            val end = restClock.start(BlockPause.restAfterPause(remaining = restClock.remaining, total = p.seconds), now())
            // Comes back on its floor — the second before its 3-2-1.
            primeBeforeTheCount(showing = restClock.remaining)
            liveActivity.update(ActivityState(ActivityState.Phase.rest, nextLabel, restActivityDetail, end))
            persistProgress()
        }
        else -> Unit
    }
}

/** Every way out of a pause ends it — and closes the freeze with it. */
fun WorkoutSession.clearBlockPause() {
    endBlockFreeze()
    blockPause.clear()
}

/** Opens the interval a guided block stands still for, an absence that has
 *  already happened included. Only inside the two blocks: a paused REST is
 *  the engine's time. */
fun WorkoutSession.beginBlockFreeze(absence: Int = 0) {
    when (phase) {
        Phase.Warmup, Phase.Cooldown -> {
            blockPausedSec += maxOf(0, absence)
            // Never restarted: the interval already open stands.
            if (blockFrozenAt == null) blockFrozenAt = now()
        }
        else -> Unit
    }
}

/** …and closes it. Idempotent. */
fun WorkoutSession.endBlockFreeze() {
    val began = blockFrozenAt ?: return
    blockPausedSec += maxOf(0, Countdown.seconds(began, now()).toInt())
    blockFrozenAt = null
}

/** The screen reader stays on the control it used, so a state change is
 *  spoken. */
fun WorkoutSession.announce(message: Words) {
    signals.announce(message)
}
