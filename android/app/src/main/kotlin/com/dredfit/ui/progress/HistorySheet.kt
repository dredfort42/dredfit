//
//  The history line's numbers — the statics `setFacts` and `setsSkipped` of
//  ios/Dredfit/Views/Progress/HistorySheet.swift, where they live on the
//  SwiftUI view. Here they are plain Kotlin (no Compose import), so a JVM
//  unit test reaches the rule; the sheet composable, when it is written,
//  prints them. HistorySheet.swift says why each step is the way it is.
//

package com.dredfit.ui.progress

import com.dredfit.core.SessionExercise
import com.dredfit.journal.WorkoutRecord
import com.dredfit.workout.SetFacts

object HistorySheet {

    /** The numbers of `ex`'s sets in `record`, and the one the rating
     *  reported — null when the record says nothing beyond the plan. A record
     *  naming its skipped sets leaves out the ones with no number of their
     *  own and cuts the sets a workout ended before reaching; an older one is
     *  cut to the sets that ran, never below what was recorded. */
    fun setFacts(ex: SessionExercise, record: WorkoutRecord): Pair<List<Int>, Int>? {
        val reported = record.actuals?.get(ex.pattern)
        val facts = record.setActuals
        val known = facts?.get(ex.pattern)?.size
        val named = record.skippedSets[ex.pattern]
        if (facts != null && known != null && named != null) {
            val unreached = maxOf(setsSkipped(ex, record) - named.size, 0)
            val ran = maxOf(ex.sets - unreached, known)
            val done = SetFacts.performed(facts, ex, skipping = record.leftOutSets[ex.pattern] ?: emptySet())
                .filter { it.first < ran }
            val first = done.firstOrNull()?.second ?: return null
            if (done.none { it.second != ex.plannedLoad(set = it.first) }) return null
            return done.map { it.second } to (reported ?: first)
        }
        val values = when {
            facts != null && known != null -> {
                val performed = maxOf(ex.sets - setsSkipped(ex, record), 0)
                SetFacts.allSets(facts, ex).take(maxOf(performed, known))
            }
            reported != null -> listOf(reported)
            else -> return null
        }
        val first = values.firstOrNull() ?: return null
        if (!SetFacts.differs(values, from = ex)) return null
        return values to (reported ?: first)
    }

    /** Sets dropped from a movement that WAS trained; a movement nobody
     *  reached is skipped whole and counts none here. */
    fun setsSkipped(ex: SessionExercise, record: WorkoutRecord): Int {
        if (record.skipped?.contains(ex.pattern) == true) return 0
        return maxOf(record.setsSkipped?.get(ex.pattern) ?: 0, 0)
    }
}
