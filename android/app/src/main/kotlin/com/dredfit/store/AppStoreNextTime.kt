//
//  What the next plan will be for one movement, read before the rating
//  lands. Read-only: the store answers by DRY-RUNNING the engine.
//  Port of ios/Dredfit/AppStore+NextTime.swift.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.applyFeedback
import com.dredfit.core.probe
import com.dredfit.core.raiseDose
import com.dredfit.workout.asPlanned

/**
 * The plan a movement will get after this session, computed the way
 * `completeWorkout` will compute it — the same entry point and arguments,
 * the rating assumed "on plan" and the gap measured now — with the probe the
 * next session would hand it, stated the way a plan states one. Null when the
 * session is not the one this state generated.
 */
@Suppress("LongParameterList")
fun AppStore.previewPlan(after: Session, pattern: Pattern, overrides: Map<Pattern, Double>, skipped: Set<Pattern>,
                         setsSkipped: Map<Pattern, Int>, probes: Map<Pattern, Int>,
                         raised: Map<Pattern, Int>): SessionExercise? {
    if (after.sessionNumber != engineState.counter + 1) return null
    val next = Engine.applyFeedback(state = engineState, session = after, result = FeedbackResult.plan,
                                    overrides = overrides, skipped = skipped, setsSkipped = setsSkipped,
                                    gapDays = gapFraction(), probes = probes, raised = raised)
    val position = positions(next)[pattern] ?: return null
    val probe = Engine.probe(pattern, at = next.position(pattern), lastHard = next.lastHard, shown = next.shown)
    return position.asPlanned(pattern, probe = probe)
}

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
