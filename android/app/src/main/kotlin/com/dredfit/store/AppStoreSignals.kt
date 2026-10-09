//
//  Facts the plan's rows and the history read off the store. Port of the parts
//  of ios/Dredfit/AppStore+Signals.swift the store itself needs: the push rows
//  the pulls held back (stamped into every record), the weak link the trainee
//  never names (#135), and who moved the plan (`PlanMoves`). The row-level
//  signals arrive with the plan screen.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.easierPosition
import com.dredfit.core.pullCap
import com.dredfit.journal.WorkoutRecord

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
