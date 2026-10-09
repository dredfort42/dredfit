//
//  Facts the plan's rows and the history read off the store. Port of
//  ios/Dredfit/AppStore+Signals.swift: the run of training days (#98), why a
//  card shows the number of sets it does, the push rows the pulls held back
//  (stamped into every record), the weak link the trainee never names (#135),
//  and who moved the plan (`PlanMoves`). Facts, not lines: the words are
//  `ui/today/ExerciseRow.kt`'s. Not ported yet: `aVariationJustDropped`,
//  which only the Today row reads.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.easierPosition
import com.dredfit.core.pullCap
import com.dredfit.journal.WorkoutRecord
import java.time.Instant

// MARK: - A run of training days (#98)

/** The rest offer appears when today's workout would be at least the
 *  (threshold + 1)-th consecutive training day. */
const val LONG_RUN_THRESHOLD = 3

/** Consecutive calendar days with a completed workout, counting back from
 *  (and including) `day` — local-midnight days, the same day math `gapDays`
 *  uses. Two workouts on one day count once. */
fun AppStore.consecutiveTrainingDays(endingOn: Instant): Int {
    val trained = records.mapTo(HashSet()) { localDay(it.date, zone) }
    var probe = localDay(endingOn, zone)
    var run = 0
    while (probe in trained) {
        run += 1
        probe = probe.minusDays(1)
    }
    return run
}

/** The day number today's workout would get: yesterday's run plus one. */
val AppStore.wouldBeConsecutiveDay: Int
    get() = consecutiveTrainingDays(today.atZone(zone).minusDays(1).toInstant()) + 1

/** Starting today's workout would make it at least the fourth training day in
 *  a row. Never once today's workout is done: an offer before the fact. */
val AppStore.todayWouldExtendALongRun: Boolean
    get() = !doneToday && wouldBeConsecutiveDay > LONG_RUN_THRESHOLD

/** Working sets plus the probe — what the person actually walks through. */
val SessionExercise.totalSets: Int get() = sets + (if (probe == null) 0 else 1)

/** The push rows of a session that showed fewer sets than their own positions
 *  stood on, read against the state the session was BUILT from. Null when
 *  nothing was held back, so such a record keeps its old shape. */
fun pushesHeldBack(session: Session, builtFrom: EngineState): Set<Pattern>? {
    val held = session.exercises.filter { ex ->
        val gate = Engine.pullCap(on = ex.pattern, state = builtFrom) ?: return@filter false
        ex.totalSets < gate.own
    }
    return if (held.isEmpty()) null else held.map { it.pattern }.toSet()
}

// MARK: - Why the card shows the number it does

/**
 * A set came back to this card. The hold armed by the transition that handed
 * the set back says so — but only over a card that showed fewer: the
 * journal's last card for the movement has the last word. A push also gets a
 * set back when the pull slot's cap lifts: the record behind its last card
 * says that card was held back (`heldBack`), on the same variation, and the
 * sets grew with a probe's slot counted. A record without the stamp claims
 * nothing.
 */
fun AppStore.aSetJustCameBack(exercise: SessionExercise): Boolean {
    val pattern = exercise.pattern
    val last = lastCard(pattern) ?: return false
    if (exercise.sets <= last.first.sets) return false
    if (engineState.setsHold[pattern] == EngineConfig.setsBackHold) return true
    return exercise.variation == last.first.variation &&
        exercise.totalSets > last.first.totalSets &&
        last.second.heldBack?.contains(pattern) == true
}

/** A push shows fewer sets than its last card because the pull slot's cap
 *  binds it right now. A drop the push made itself leaves the cap at or above
 *  its own sets; a working set a probe took did not drop with the probe's
 *  slot counted. */
fun AppStore.setsJustHeldBackByThePulls(exercise: SessionExercise): Boolean {
    val gate = Engine.pullCap(on = exercise.pattern, state = engineState) ?: return false
    if (gate.cap >= gate.own) return false
    val last = lastCard(exercise.pattern)?.first ?: return false
    return exercise.sets < last.sets && exercise.totalSets < last.totalSets
}

/** A push on its top variation below the top band whose next band the pull
 *  cap does not reach yet: a count of steps to it would promise a set the
 *  pulls decide. */
fun AppStore.nextSetWaitsForThePulls(pattern: Pattern): Boolean {
    val position = engineState.position(pattern)
    if (!Library.isTop(pattern, position.variation) || position.sets >= EngineConfig.setsMax) return false
    val gate = Engine.pullCap(on = pattern, state = engineState) ?: return false
    return gate.cap <= position.sets
}

/** The card this movement carried at its last appearance, and its record —
 *  what the person saw. A record too old to know its exercises ends the walk:
 *  a gap in the journal is not evidence of anything. */
private fun AppStore.lastCard(pattern: Pattern): Pair<SessionExercise, WorkoutRecord>? {
    for (record in records.asReversed()) {
        val exercises = record.exercises ?: return null
        exercises.firstOrNull { it.pattern == pattern }?.let { return it to record }
    }
    return null
}

// MARK: - The weak link the trainee never names (#135)

/** A movement the journal keeps finding under an unnamed "tough" — 3 of its
 *  last 4 appearances — and that has an easier variation to offer. */
fun AppStore.unnamedLessSuspect(): Pattern? {
    var best: Pattern? = null
    var bestHits = 0
    for (pattern in Pattern.allCases) {
        var hits = 0
        var seen = 0
        for (record in records.asReversed()) {
            val exercises = record.exercises ?: break
            if (exercises.none { it.pattern == pattern }) continue
            seen += 1
            if (record.result == FeedbackResult.less && namesNothing(record)) hits += 1
            if (seen == EngineConfig.chronicWindow) break
        }
        if (seen != EngineConfig.chronicWindow || hits < EngineConfig.chronicHits) continue
        // A tie goes to the one first in `Pattern.allCases`.
        if (hits > bestHits) {
            bestHits = hits
            best = pattern
        }
    }
    val suspect = best ?: return null
    // Nothing to suggest when the one handle the prompt offers would do nothing.
    if (Engine.easierPosition(pattern = suspect, position = engineState.position(suspect),
                              shown = engineState.shown) == null) return null
    return suspect
}

/** "Tough", and no number entered for any movement. */
private fun namesNothing(record: WorkoutRecord): Boolean = record.actuals.isNullOrEmpty()

/** At most one prompt per session: a question, not a campaign. */
fun AppStore.shouldAskAboutSuspect(): Boolean {
    if (settings.weakLinkPromptAnsweredFor == records.lastOrNull()?.sessionNumber) return false
    return unnamedLessSuspect() != null
}

// MARK: - Who moved the plan

/** The stamped facts, only while they still describe the session asked about. */
fun AppStore.planMoves(session: Int): PlanMoves? = settings.planMoves?.takeIf { it.session == session }

/** The same question of the slot the rating owns. */
fun AppStore.ratingMoves(session: Int): PlanMoves? = settings.ratingMoves?.takeIf { it.session == session }

/** Movements lowered by hand for the plan STILL AHEAD. */
val AppStore.easedByHandAhead: List<Pattern> get() = planMoves(engineState.counter + 1)?.byHand ?: emptyList()

/** Which movements a finished workout's rating eased — THE LAST WORKOUT ONLY,
 *  identified by `id`, because `sessionNumber` restarts at a reset. */
fun AppStore.easedByRating(record: WorkoutRecord): List<Pattern> = moves(record)?.byRating ?: emptyList()

fun AppStore.easedByHand(record: WorkoutRecord): List<Pattern> = moves(record)?.byHand ?: emptyList()

private fun AppStore.moves(record: WorkoutRecord): PlanMoves? {
    if (records.lastOrNull()?.id != record.id) return null
    return ratingMoves(record.sessionNumber)
}
