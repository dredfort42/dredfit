//
//  A recorded position, stated the way a plan states one. Port of
//  ios/Dredfit/PlannedPosition.swift: the history and the summary of a
//  finished hold must not describe one position in two spellings.
//

package com.dredfit.workout

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe
import com.dredfit.core.cutMax
import com.dredfit.journal.RecordedPosition

/**
 * `cut` and `sub` are resolved first, the way `Engine.fit` resolves them (the
 * top-rung disable included); the probe takes the last of the standing sets.
 * Bounded by the SCALE, not by the record.
 */
fun RecordedPosition.asPlanned(pattern: Pattern, probe: SessionProbe?): SessionExercise {
    val unit = Library.unit(pattern, variation)
    val grid = Dose.grid(unit)
    val standing = sets - minOf(maxOf(cut ?: 0, 0), Engine.cutMax(sets = sets)) - (if (probe == null) 0 else 1)
    val planSets = minOf(maxOf(standing, 0), EngineConfig.setsMax)
    val planSub = if (dose >= grid.max) 0 else minOf(maxOf(sub ?: 0, 0), maxOf(planSets - 1, 0))
    val loads = if (planSub > 0) (0 until planSets).map { if (it < planSub) dose + grid.step else dose } else null
    return SessionExercise(
        pattern = pattern, name = Library.name(pattern, variation), variation = variation, unit = unit,
        load = dose, perSide = Library.sides(pattern, variation) == 2, sets = planSets,
        restSetSec = 0, restExerciseSec = 0, loads = loads, probe = probe)
}
