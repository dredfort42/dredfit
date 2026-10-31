//
//  The cool-down block (issue #28): offered once the work is behind, composed
//  zone by zone for the session, run on the guided blocks' engine. Port of
//  ios/Dredfit/WorkoutSession+Cooldown.swift.
//

package com.dredfit.workout

import com.dredfit.core.Pattern
import com.dredfit.journal.BlockRun
import com.dredfit.workout.WorkoutSession.Phase
import kotlin.math.ceil

/** Rounded up: a promise the block overruns is worse than one it beats. */
val WorkoutSession.cooldownIntroMinutes: Int get() = WorkoutSession.cooldownMinutes(cooldownPositions)

/** What is LEFT of the block; the position on screen counts WHOLE. */
val WorkoutSession.cooldownMinutesLeft: Int?
    get() {
        if (phase != Phase.Cooldown || cooldown.index !in cooldownPositions.indices) return null
        return WorkoutSession.cooldownMinutes(cooldownPositions.drop(cooldown.index))
    }

/** One arithmetic for the offer and for what is left of it. */
fun WorkoutSession.Companion.cooldownMinutes(positions: List<CooldownPosition>): Int {
    val seconds = positions.sumOf { position ->
        GetReady.stageSeconds(needsSetup = position.needsSetup) + Cooldown.slotSeconds(position)
    }
    return maxOf(1, ceil(seconds.toDouble() / 60).toInt())
}

/** A position set aside or brought back: recompose from the same input the
 *  block started with, and restart the slot on its transition. WHICH slot is
 *  `cooldownLanding`'s rule: the warm-up's `rebaseLanding` with a floor at the
 *  level reached. A clamp of the ordinal would reopen a stretch already done:
 *  a zone emptied by the position on screen is refilled on the refill's own
 *  level, which can sort in above the slot, and "Bring back" puts a position
 *  back on its level — above the athlete, as often as not, in place of a
 *  stand-in they already did. */
fun WorkoutSession.rebaseCooldownOnComposition() {
    if (phase != Phase.Cooldown) return
    val recomposed = Cooldown.positions(sessionNumber = session.sessionNumber,
                                        hiding = store.settings.hiddenBlockMoveIDs)
    if (recomposed.isEmpty() || recomposed == cooldownPositions) return
    // Read BEFORE the new list is stored.
    val passed = cooldownPositions.take(maxOf(0, cooldown.index)).map { it.id }.toSet()
    // The level of the position on screen: where the athlete is, or is
    // getting to. The index is state, hence the check.
    val reached = cooldownPositions.getOrNull(cooldown.index)?.level ?: CooldownPosition.Level.standing
    val index = WorkoutSession.cooldownLanding(recomposed, after = passed, reached = reached)
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

/** `rebaseLanding` with the cool-down's floor: the first slot on the level
 *  the athlete has reached. The block only goes down, so a position brought
 *  back above it — the kneeling lunge while they kneel in the rest pose, whose
 *  standing twin is already behind them — waits for the next workout rather
 *  than getting them up, and the zone is not stretched twice. */
fun WorkoutSession.Companion.cooldownLanding(positions: List<CooldownPosition>, after: Set<String>,
                                             reached: CooldownPosition.Level): Int? {
    val floor = positions.indexOfFirst { it.level >= reached }.takeIf { it >= 0 } ?: positions.size
    return rebaseLanding(positions.map { it.id }, after = after, notBefore = floor)
}

/** The movements the workout actually performed — whether there is anything
 *  to cool down from at all. */
val WorkoutSession.performedPatterns: List<Pattern>
    get() = exercises.map { it.pattern }.filter { it !in skippedPatterns }

/** A workout of pure skips has nothing to stretch — straight to the rating. */
fun WorkoutSession.startCooldown() {
    cooldownPositions = if (performedPatterns.isEmpty()) {
        emptyList()
    } else {
        Cooldown.positions(sessionNumber = session.sessionNumber, hiding = store.settings.hiddenBlockMoveIDs)
    }
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
