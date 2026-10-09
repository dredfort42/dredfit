//
//  The seconds a planned session spends in each state it can be in — the
//  segmentation half of ios/Dredfit/EnergyEstimate.swift. The history sheet
//  holds its wall clock against this plan ("Took N min in the app"); the
//  calorie half (METs, the resting ladder) arrives with health/, which is its
//  only reader.
//

package com.dredfit.workout

import com.dredfit.core.EngineConfig
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise

data class SessionSegments(
    val warmupSec: Double = 0.0,
    val repWorkSec: Double = 0.0,
    val holdWorkSec: Double = 0.0,
    val restSec: Double = 0.0,
    val cooldownSec: Double = 0.0,
) {
    val totalSec: Double get() = warmupSec + repWorkSec + holdWorkSec + restSec + cooldownSec

    /** The journal is an input: a hand-edited record can produce a negative
     *  rest or an infinity here. */
    val isPlausible: Boolean
        get() {
            val all = listOf(warmupSec, repWorkSec, holdWorkSec, restSec, cooldownSec)
            if (!all.all { it.isFinite() && it >= 0 }) return false
            return totalSec > 0 && totalSec <= 24 * 3600
        }
}

object EnergyEstimate {

    /** Seconds one repetition is under way — the engine's own figure. */
    const val secondsPerRep = 2.5

    /** Null when there is nothing to segment. `warmupSec`/`cooldownSec` are
     *  what the blocks ACTUALLY ran; null falls back to the plan, zero means
     *  declined. Neither carries a default, as in Swift. */
    fun segments(exercises: List<SessionExercise>, skipped: Set<Pattern>,
                 warmupSec: Int?, cooldownSec: Int?): SessionSegments? {
        if (exercises.isEmpty()) return null
        var repWork = 0.0
        var holdWork = 0.0
        var rest = 0.0
        for (ex in exercises) {
            if (ex.pattern in skipped) continue
            val sides = if (ex.perSide) 2.0 else 1.0
            val sets = ex.sets.toDouble()
            // In Double throughout: these come back out of the journal
            // unclamped.
            if (ex.unit == LoadUnit.reps) repWork += sets * ex.load.toDouble() * sides * secondsPerRep
            else holdWork += sets * ex.load.toDouble() * sides
            rest += (sets - 1) * ex.restSetSec.toDouble() + ex.restExerciseSec.toDouble()
        }
        return SessionSegments(
            warmupSec = performed(warmupSec, planned = EngineConfig.warmupMin * 60),
            repWorkSec = repWork, holdWorkSec = holdWork, restSec = rest,
            cooldownSec = performed(cooldownSec, planned = EngineConfig.cooldownMin * 60))
    }

    /** The plan is a CEILING: a block cut short was shorter, a declined one
     *  is zero, an unmeasured one is charged its plan. */
    private fun performed(measured: Int?, planned: Int): Double {
        if (measured == null) return planned.toDouble()
        return minOf(maxOf(measured, 0), planned).toDouble()
    }
}
