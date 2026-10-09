//
//  The athlete's handles: what the plan can be ASKED. The writes live in
//  AppStore proper (`makeEasier`, `makeSuspectEasier`), and every handle goes
//  through the ENGINE. Port of ios/Dredfit/AppStore+Handles.swift.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.LoadUnit
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.cutMax
import com.dredfit.core.easierPosition
import com.dredfit.core.easierVariation
import com.dredfit.core.generateSession
import com.dredfit.core.roundedAwayFromZero
import com.dredfit.core.setCut
import com.dredfit.journal.WorkoutSnapshot
import java.time.Instant

/** False on the first variation — there is nothing below it. */
fun AppStore.canMakeEasier(pattern: Pattern): Boolean =
    Engine.easierPosition(pattern = pattern, position = engineState.position(pattern),
                          shown = engineState.shown) != null

/**
 * The movement one step down the ladder, in pieces: on `pull_bar` 3 → 2 the
 * UNIT changes, which a glued "3×15" → "3×15 sec" would not say. `name` and
 * `dose` are the English base strings; the screen localizes `name` and prints
 * the dose from `exercise` in the reader's words (`displayOf`).
 */
data class EasierStep(
    val name: String,
    val dose: String,
    val unitChanged: Boolean,
    val variation: Int,
    val exercise: SessionExercise,
)

/** Asks the engine on a COPY and writes nothing, so what is shown is what
 *  the tap would deliver. */
fun AppStore.easierStep(pattern: Pattern): EasierStep? {
    if (!canMakeEasier(pattern)) return null
    val before: LoadUnit = Library.unit(pattern, engineState.position(pattern).variation)
    val after = Engine.easierVariation(state = engineState, pattern = pattern)
    return Engine.generateSession(after).exercises.firstOrNull { it.pattern == pattern }?.let {
        EasierStep(name = it.name, dose = it.display, unitChanged = it.unit != before, variation = it.variation,
                   exercise = it)
    }
}

/** True when flipping the bar to `on` would throw away a workout the athlete
 *  could still resume — asked by generating the session the switch WOULD give. */
fun AppStore.barToggleWouldDiscardWorkout(on: Boolean, now: Instant = clock.instant()): Boolean {
    val snap = resumableWorkout(now) ?: return false
    val after = engineState.copy().also { it.hasBar = on }
    return snap.fingerprint != WorkoutSnapshot.fingerprint(session(after))
}

/** The two ends of today's session — the full plan, and the same plan with
 *  every movement on the sets floor — both the engine's own estimate. The
 *  floor is a QUESTION put to the engine, never a state that is written. */
fun AppStore.sessionLengthRange(): Pair<Int, Int> {
    val full = nextSession.estimatedTotalMin
    var floored = engineState
    for (pattern in Pattern.allCases) {
        floored = Engine.setCut(state = floored, pattern = pattern,
                                cut = Engine.cutMax(sets = floored.position(pattern).sets))
    }
    val shortest = minOf(Engine.generateSession(floored).estimatedTotalMin, full)
    return swiftRounded(shortest) to swiftRounded(full)
}

/** `Int(x.rounded())` — ties away from zero. */
private fun swiftRounded(x: Double): Int = roundedAwayFromZero(x).toInt()
