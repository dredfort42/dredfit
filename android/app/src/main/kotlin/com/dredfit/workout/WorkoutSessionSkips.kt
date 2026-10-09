//
//  The skip that happens DURING the workout: one set, the rest of the sets,
//  or the movement. Port of ios/Dredfit/WorkoutSession+Skips.swift.
//

package com.dredfit.workout

import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.workout.WorkoutSession.Phase

/** Whether a skip still leaves a trained movement behind (`SetFacts.skipFits`). */
fun WorkoutSession.skipsLeaveAMovement(count: Int): Boolean =
    SetFacts.skipFits(count, of = exercise.sets, alreadySkipped = setsSkipped[exercise.pattern] ?: 0)

/** Sets of this exercise already behind and actually performed. */
val WorkoutSession.setsPerformedHere: Int get() = setIndex - (setsSkipped[exercise.pattern] ?: 0)

/** The person entered a number for the set in front of them — read at the
 *  skip, because later it cannot be. A record at this index says so too: it
 *  is what is left of an OK after a process death. */
private val WorkoutSession.setInFrontHasANumber: Boolean
    get() = numbersEntered[exercise.pattern]?.contains(setIndex) == true ||
        (actuals[exercise.pattern]?.size ?: 0) > setIndex

private fun Map<Pattern, Set<Int>>.adding(pattern: Pattern, indices: Iterable<Int>): Map<Pattern, Set<Int>> =
    this + (pattern to ((this[pattern] ?: emptySet()) + indices))

/** "Skip this set": not performed, the next one is up — no rest on the way. */
fun WorkoutSession.skipSet() {
    if (phase != Phase.Work) return
    // Skipping the PROBE takes no volume off anything; unresolved, it comes
    // back next time.
    if (onProbeSet) {
        editing = null
        probeActuals = probeActuals - exercise.pattern
        // A hold's working sets are still owed their summary.
        if (exercise.unit == LoadUnit.hold) {
            resetHoldSides()
            startExerciseSummary()
            return
        }
        advancePastExercise()
        return
    }
    if (!skipsLeaveAMovement(1)) { leaveExercise(); return }
    editing = null
    val pattern = exercise.pattern
    setsSkipped = setsSkipped + (pattern to (setsSkipped[pattern] ?: 0) + 1)
    skippedSetIndices = skippedSetIndices.adding(pattern, listOf(setIndex))
    if (setInFrontHasANumber) skippedWithNumber = skippedWithNumber.adding(pattern, listOf(setIndex))
    if (isLastSet) {
        advancePastExercise()
    } else {
        resetHoldSides()   // this path skips it otherwise
        setIndex += 1
        phase = Phase.Work
        liveActivity.update(activityWorkState())
        persistProgress()
    }
}

/** "Skip the remaining sets": one tap for the whole movement. */
fun WorkoutSession.skipRestOfExercise() {
    if (phase != Phase.Work) return
    // Only the WORKING sets can be taken off.
    val left = maxOf(0, exercise.sets - setIndex)
    if (!skipsLeaveAMovement(left)) { leaveExercise(); return }
    editing = null
    val pattern = exercise.pattern
    setsSkipped = setsSkipped + (pattern to (setsSkipped[pattern] ?: 0) + left)
    if (left > 0) {
        skippedSetIndices = skippedSetIndices.adding(pattern, setIndex until exercise.sets)
        if (setInFrontHasANumber) skippedWithNumber = skippedWithNumber.adding(pattern, listOf(setIndex))
    }
    advancePastExercise()
}
