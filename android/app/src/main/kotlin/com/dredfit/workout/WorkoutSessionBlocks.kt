//
//  The run of a guided block — the warm-up's or the cool-down's — on the one
//  engine both share (GuidedBlock.kt). Port of
//  ios/Dredfit/WorkoutSession+Blocks.swift.
//

package com.dredfit.workout

import com.dredfit.workout.WorkoutSession.Companion.countdownSignalSeconds

/** Where `block` stands — Swift's `self[run: block]`, the live run. */
fun WorkoutSession.run(block: GuidedBlock): GuidedBlockRun = when (block) {
    GuidedBlock.warmup -> warmup
    GuidedBlock.cooldown -> cooldown
}

/** What `block` is composed of: the warm-up's list is read live, the
 *  cool-down's was drawn once when the work ended. */
fun WorkoutSession.positions(block: GuidedBlock): List<GuidedPosition> = when (block) {
    GuidedBlock.warmup -> warmupMoves
    GuidedBlock.cooldown -> cooldownPositions
}

fun WorkoutSession.startPosition(index: Int, block: GuidedBlock) {
    enterStage(index = index, stage = GuidedStage.getReady,
               remaining = block.stageSeconds(GuidedStage.getReady, positions(block)[index]), block = block)
}

/** "I'm ready" cuts the transition down to a count-in — `min`, never a plain
 *  count-in: a tap may only shorten what is running. */
fun WorkoutSession.countIn(block: GuidedBlock) {
    val run = run(block)
    enterStage(index = run.index, stage = GuidedStage.getReady,
               remaining = minOf(run.clock.remaining, GetReady.countInSeconds), block = block)
}

fun WorkoutSession.enterStage(index: Int, stage: GuidedStage, remaining: Int, block: GuidedBlock) {
    clearBlockPause()   // a new stage is never entered still frozen
    val run = run(block)
    run.index = index
    run.stage = stage
    run.clock.start(remaining, now())
    // Started on its four, which no tick reports. The switch pause sounds no 3-2-1.
    if (stage != GuidedStage.switchPause) primeBeforeTheCount(showing = remaining)
}

/** Skipping from the transition skips the position it was announcing. */
fun WorkoutSession.skipPosition(block: GuidedBlock) {
    val next = run(block).index + 1
    if (next < positions(block).size) startPosition(next, block) else finish(block)
}

fun WorkoutSession.finish(block: GuidedBlock) = when (block) {
    GuidedBlock.warmup -> finishWarmup()
    GuidedBlock.cooldown -> finishCooldown()
}

fun WorkoutSession.tick(block: GuidedBlock) {
    val late = when (val reading = run(block).clock.read(now())) {
        Countdown.Reading.Unchanged -> return
        is Countdown.Reading.Second -> {
            show(reading.second, block)
            return
        }
        is Countdown.Reading.Ended -> maxOf(0.0, reading.overshoot)
    }
    val overshoot = late.toInt()
    // A boundary crossed while the phone was elsewhere is not a boundary the
    // person was at: freeze, and the way back in is Resume. Compared to the
    // FRACTION — rounded down first, 4.9 s away would read as 4.
    if (late > BlockPause.absenceSeconds.toDouble()) {
        pauseBlock(absence = overshoot)
        return
    }
    val positions = positions(block)
    val current = run(block)
    val next = block.advance(GuidedBlock.Step(current.index, current.stage), overshoot, positions)
    if (next == null) {
        endByItself(block)
        return
    }
    signal(next, landingOn = positions[next.index])
    enterStage(index = next.index, stage = next.stage, remaining = next.remaining, block = block)
    // Re-stamped so a long cool-down stays resumable — onto the rating.
    if (block == GuidedBlock.cooldown && next.entered == GuidedStage.getReady) persistProgress()
}

/** A second of a running stage, shown. */
private fun WorkoutSession.show(second: Int, block: GuidedBlock) {
    val run = run(block)
    // No 3-2-1 inside the switch pause; the transition's 3-2-1 IS its signal.
    if (run.stage != GuidedStage.switchPause) {
        if (run.clock.signals(second, within = countdownSignalSeconds)) playTick()
        primeBeforeTheCount(showing = second)
    }
    animate(WorkoutSession.Motion.countdown) { run.clock.show(second) }
}

/** The block ran out on its own clock. */
private fun WorkoutSession.endByItself(block: GuidedBlock) {
    when (block) {
        // Done, not go — a tap starts the first exercise (#186).
        GuidedBlock.warmup -> playDone()
        // The finale (#84). Skipping the cool-down stays silent.
        GuidedBlock.cooldown -> playWorkoutDone()
    }
    finish(block)
}

/** The signal belongs to what is on screen: anything but a landing on the
 *  boundary that opened the run stays silent. Each audible boundary is
 *  SPOKEN as well, in the words the new screen shows. */
private fun WorkoutSession.signal(next: GuidedBlock.Advance, landingOn: GuidedPosition) {
    when {
        next.entered == GuidedStage.getReady && next.stage == GuidedStage.getReady -> {
            playDone()
            announce(Words.of("Get ready: %@", landingOn.name))
        }
        next.entered == GuidedStage.getReady || next.stage == GuidedStage.getReady -> Unit
        next.entered == GuidedStage.switchPause -> {
            playSwitch()
            landingOn.halves?.let { announce(SplitStageWords(it).switching) }
        }
        else -> {
            playGo()
            val halves = landingOn.halves
            if (next.stage == GuidedStage.secondHalf && halves != null) {
                announce(SplitStageWords(halves).secondHalf)
            } else {
                announce(landingOn.name)
            }
        }
    }
}
