//
//  The warm-up block: offered, never required, composed live from the pool,
//  and run on the guided blocks' engine. Port of
//  ios/Dredfit/WorkoutSession+Warmup.swift.
//

package com.dredfit.workout

import com.dredfit.journal.BlockRun
import com.dredfit.workout.WorkoutSession.Phase

/** The six moves of THIS session, the hidden set read LIVE. */
val WorkoutSession.warmupMoves: List<WarmupMove>
    get() = Warmup.moves(session, hiding = store.settings.hiddenBlockMoveIDs)

val WorkoutSession.warmupIntroMinutes: Int get() = Warmup.introMinutes(warmupMoves)

/** Both warm-up screens: not a step of the work, WARM-UP on the tile. */
val WorkoutSession.isWarmingUp: Boolean get() = phase == Phase.Warmup || phase == Phase.WarmupIntro

/** The person said yes. Nothing persisted: no progress yet. */
fun WorkoutSession.beginWarmup() {
    if (phase != Phase.WarmupIntro) return
    phase = Phase.Warmup
    warmupBeganAt = now()
    // The pair is per BLOCK.
    blockPausedSec = 0
    blockFrozenAt = null
    startPosition(0, GuidedBlock.warmup)
    // A start tap opens on the count-in, not the full travel time.
    countIn(GuidedBlock.warmup)
}

/** …or no: straight to the work, the block recorded as zero. */
fun WorkoutSession.declineWarmup() {
    if (phase != Phase.WarmupIntro) return
    finishWarmup()
}

/** The composition changed under the running block (a move set aside or
 *  brought back): the slot restarts on its own transition, at the landing
 *  `rebaseLanding` names. `previous` is the composition the block was
 *  running. */
fun WorkoutSession.rebaseWarmupOnComposition(previous: List<String>) {
    if (phase != Phase.Warmup) return
    val moves = warmupMoves
    if (moves.isEmpty()) { finishWarmup(); return }
    val passed = previous.take(maxOf(0, warmup.index)).toSet()
    val index = WorkoutSession.rebaseLanding(moves.map { it.id }, after = passed)
    if (index == null) {
        finishWarmup()
        return
    }
    warmup.index = index
    warmup.stage = GuidedStage.getReady
    // NOT through `enterStage`: the sheet that got us here is still open.
    warmup.clock.reset(to = GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, moves[index]), now = now())
}

/** Where a recomposed block picks up — AFTER the last slot already left
 *  behind; null when nothing is left. */
fun WorkoutSession.Companion.rebaseLanding(ids: List<String>, after: Set<String>): Int? {
    val last = ids.indexOfLast { it in after }
    val index = if (last >= 0) last + 1 else 0
    return if (index < ids.size) index else null
}

/** The move on screen, clamped: the index is state. */
val WorkoutSession.warmupMove: WarmupMove
    get() {
        val moves = warmupMoves
        return moves[minOf(maxOf(warmup.index, 0), moves.size - 1)]
    }

fun WorkoutSession.finishWarmup() {
    if (phase != Phase.Warmup && phase != Phase.WarmupIntro) return
    clearBlockPause()
    // Written once; minus what the block stood still for.
    if (warmupSec == null) {
        warmupSec = maxOf(0, BlockRun.seconds(began = warmupBeganAt, ended = now()) - blockPausedSec)
    }
    warmup.clock.freeze()
    phase = Phase.Work
    liveActivity.update(activityWorkState())
    persistProgress()
}
