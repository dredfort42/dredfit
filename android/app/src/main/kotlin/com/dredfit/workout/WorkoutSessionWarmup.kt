//
//  The warm-up block: offered, never required, composed live from the pool,
//  and run on the guided blocks' engine. Port of
//  ios/Dredfit/WorkoutSession+Warmup.swift.
//

package com.dredfit.workout

import com.dredfit.journal.BlockRun
import com.dredfit.workout.WorkoutSession.Phase

/** The six moves of THIS session (fourteen in the pool, six on screen): a
 *  function of the session — its number and its first exercise — and of the
 *  hidden set, read LIVE. */
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
    val index = WorkoutSession.rebaseLanding(moves.map { it.id }, after = passed, notBefore = 0)
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
 *  behind; null when nothing is left.
 *
 *  Never earlier than the number of slots already used, either. Bringing a
 *  move back can DROP one already done — the stand-in that ran in its place —
 *  and landing after the last survivor would then run one move more than the
 *  block promised. And never before `notBefore`: the cool-down passes the
 *  first slot on the level the athlete has reached (`cooldownLanding`),
 *  because a position brought back above it would get them up again. The
 *  warm-up stands throughout and passes 0.
 *
 *  The cost is that a move brought back mid-block may not appear until the
 *  next workout — and, when the block has no slot left for both, takes the
 *  place of the one on screen: the block keeps the length it promised and
 *  never runs a position twice. */
fun WorkoutSession.Companion.rebaseLanding(ids: List<String>, after: Set<String>, notBefore: Int): Int? {
    val last = ids.indexOfLast { it in after }
    val afterPassed = if (last >= 0) last + 1 else 0
    val index = maxOf(afterPassed, after.size, notBefore)
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
