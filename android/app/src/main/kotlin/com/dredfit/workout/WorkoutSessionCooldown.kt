//
//  The cool-down block (issue #28): offered once the work is behind, composed
//  from the movements actually performed, run on the guided blocks' engine.
//  Port of ios/Dredfit/WorkoutSession+Cooldown.swift.
//

package com.dredfit.workout

import com.dredfit.core.Pattern
import com.dredfit.journal.BlockRun
import com.dredfit.workout.WorkoutSession.Phase
import kotlin.math.ceil

/** Rounded up: a promise the block overruns is worse than one it beats. */
val WorkoutSession.cooldownIntroMinutes: Int get() = cooldownMinutes(cooldownPositions)

/** What is LEFT of the block; the position on screen counts WHOLE. */
val WorkoutSession.cooldownMinutesLeft: Int?
    get() {
        if (phase != Phase.Cooldown || cooldown.index !in cooldownPositions.indices) return null
        return cooldownMinutes(cooldownPositions.drop(cooldown.index))
    }

/** One arithmetic for the offer and for what is left of it. */
fun WorkoutSession.cooldownMinutes(positions: List<CooldownPosition>): Int {
    val seconds = positions.sumOf { position ->
        val hold = if (position.perSide) {
            Cooldown.sideSeconds + Cooldown.sideSwitchPauseSec + Cooldown.sideSeconds
        } else {
            Cooldown.positionSeconds
        }
        GetReady.stageSeconds(needsSetup = position.needsSetup) + hold
    }
    return maxOf(1, ceil(seconds.toDouble() / 60).toInt())
}

/** A position set aside or brought back: recompose from the same input the
 *  block started with, and restart the slot on its transition. */
fun WorkoutSession.rebaseCooldownOnComposition() {
    if (phase != Phase.Cooldown) return
    val recomposed = Cooldown.positions(performed = performedPatterns, hiding = store.settings.hiddenBlockMoveIDs)
    if (recomposed.isEmpty() || recomposed == cooldownPositions) return
    // Read BEFORE the new list is stored.
    val passed = cooldownPositions.take(maxOf(0, cooldown.index)).map { it.id }.toSet()
    val index = WorkoutSession.rebaseLanding(recomposed.map { it.id }, after = passed)
    if (index == null) {
        finishCooldown()
        return
    }
    cooldownPositions = recomposed
    cooldown.index = index
    cooldown.stage = GuidedStage.getReady
    cooldown.clock.reset(to = GuidedBlock.cooldown.stageSeconds(GuidedStage.getReady, recomposed[index]), now = now())
    persistProgress()
}

/** What the cool-down is composed FROM — one spelling for both callers. */
val WorkoutSession.performedPatterns: List<Pattern>
    get() = exercises.map { it.pattern }.filter { it !in skippedPatterns }

/** A workout of pure skips has nothing to stretch — straight to the rating. */
fun WorkoutSession.startCooldown() {
    cooldownPositions = Cooldown.positions(performed = performedPatterns, hiding = store.settings.hiddenBlockMoveIDs)
    if (cooldownPositions.isEmpty()) {
        // Never offered, so never begun: zero.
        cooldownSec = 0
        phase = Phase.Feedback
        liveActivity.end()
        persistProgress()
        return
    }
    // Ask first.
    phase = Phase.CooldownIntro
    liveActivity.update(ActivityState(ActivityState.Phase.work, Words.of("COOL-DOWN"), detail = null, restEndDate = null))
    persistProgress()
}

/** The person said yes on the intro screen. */
fun WorkoutSession.beginCooldown() {
    if (phase != Phase.CooldownIntro) return
    phase = Phase.Cooldown
    cooldownBeganAt = now()
    blockPausedSec = 0
    blockFrozenAt = null
    startPosition(0, GuidedBlock.cooldown)
    countIn(GuidedBlock.cooldown)
    persistProgress()
}

/** …or no: straight to the rating. */
fun WorkoutSession.declineCooldown() {
    if (phase != Phase.CooldownIntro) return
    finishCooldown()
}

fun WorkoutSession.finishCooldown() {
    if (phase != Phase.Cooldown && phase != Phase.CooldownIntro) return
    clearBlockPause()
    if (cooldownSec == null) {
        cooldownSec = maxOf(0, BlockRun.seconds(began = cooldownBeganAt, ended = now()) - blockPausedSec)
    }
    cooldown.clock.freeze()
    phase = Phase.Feedback
    liveActivity.end()
    persistProgress()
}
