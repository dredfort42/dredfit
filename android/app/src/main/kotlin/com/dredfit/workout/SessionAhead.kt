//
//  What is still ahead of the person in the session they are in — the live
//  half of the announced duration. Port of ios/Dredfit/SessionAhead.swift.
//

package com.dredfit.workout

import com.dredfit.core.Engine
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.estimatedMin
import com.dredfit.core.roundedAwayFromZero

object SessionAhead {

    /** The exercises still to be performed, ON THE PLAN ALONE. */
    fun remaining(exercises: List<SessionExercise>, exIndex: Int, setsBehind: Int): List<SessionExercise> =
        remaining(exercises, exIndex, setsBehind, facts = emptyMap(), declared = null)

    /**
     * The same list, built out of what the exercise UNDER WAY will actually
     * run at: the sets left are the LAST ones of the plan, each priced at
     * what its clock will be set to (`SetFacts.holdTarget`). Only the
     * exercise under way takes the facts and the declaration.
     */
    fun remaining(exercises: List<SessionExercise>, exIndex: Int, setsBehind: Int,
                  facts: Map<Pattern, List<Int>>, declared: Int?): List<SessionExercise> {
        if (exIndex !in exercises.indices) return emptyList()
        val current = exercises[exIndex]
        val left = maxOf(0, current.sets - maxOf(0, setsBehind))
        val ahead = mutableListOf<SessionExercise>()
        if (left > 0) {
            ahead += trimmed(current, left, facts, declared)
        } else if (current.probe != null) {
            // The probe is the LAST set and still ahead when every working
            // set is behind — exactly the rest that announces it by name.
            ahead += trimmed(current, 0, facts, declared)
        }
        ahead += exercises.drop(exIndex + 1)
        return ahead
    }

    /** Minutes still ahead, through the ENGINE'S OWN arithmetic. */
    fun minutes(exercises: List<SessionExercise>, exIndex: Int, setsBehind: Int, ends: Int): Int =
        minutes(remaining(exercises, exIndex, setsBehind), ends)

    fun minutes(ahead: List<SessionExercise>, ends: Int): Int =
        roundedAwayFromZero(Engine.estimatedMin(exercises = ahead, ends = maxOf(0, ends))).toInt()

    /** The same exercise with only its last `sets` sets left. */
    private fun trimmed(ex: SessionExercise, sets: Int, facts: Map<Pattern, List<Int>>, declared: Int?): SessionExercise =
        SessionExercise(
            pattern = ex.pattern, name = ex.name, variation = ex.variation, unit = ex.unit, load = ex.load,
            perSide = ex.perSide, sets = sets, restSetSec = ex.restSetSec, restExerciseSec = ex.restExerciseSec,
            loads = ((ex.sets - sets) until ex.sets).map { SetFacts.holdTarget(facts, ex, it, declared) },
            probe = ex.probe)
}
