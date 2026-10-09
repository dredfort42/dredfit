//
//  What the next plan will be for one movement. Read-only.
//  Port of ios/Dredfit/AppStore+NextTime.swift, without `previewPlan`: it
//  states a position the way a plan does (PlannedPosition.swift), which
//  arrives with the workout's summary screens that read it.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.core.raiseDose

/**
 * Steps the LAST workout added to a movement "for next time", while the plan
 * on screen is the one that addition shaped and nothing else has moved the
 * movement since. The landed share, not the taps.
 */
fun AppStore.raisedForNextPlan(pattern: Pattern): Int {
    val last = records.lastOrNull() ?: return 0
    if (last.sessionNumber != engineState.counter ||
        last.positionsAfter?.get(pattern) != currentPositions[pattern]) return 0
    return last.raisedShare(pattern).coerceIn(0, EngineConfig.raiseStepsMax)
}

/**
 * The share of `raised` that MOVED a position: the raise replayed one step
 * at a time over the state the rating alone would have left. Step by step,
 * not by the total move: under a cut the step that completes a rung moves
 * the measure by more than one, and a step burned on the ceiling after it
 * would hide inside that jump (#277).
 */
fun landed(raised: Map<Pattern, Int>, unraised: EngineState): Map<Pattern, Int> {
    val out = LinkedHashMap<Pattern, Int>()
    for ((pattern, steps) in raised) {
        if (steps <= 0) continue
        var before = Engine.progress(unraised, pattern)
        var moved = 0
        for (k in 1..minOf(steps, EngineConfig.raiseStepsMax)) {
            val after = Engine.progress(Engine.raiseDose(state = unraised, pattern = pattern, steps = k), pattern)
            if (after > before) moved += 1
            before = after
        }
        if (moved > 0) out[pattern] = moved
    }
    return out
}
