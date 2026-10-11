//
//  The two escapes the work screen offers for a skip DURING the workout — one
//  set, the rest of the sets, or the movement — and which question each asks.
//  Port of ios/Dredfit/Views/Workout/WorkoutFlowView+Skips.swift. On iOS the
//  choice sits on the view; here it is plain Kotlin, so a JVM test reaches it
//  (WorkoutFlowSkipsTest). The skips themselves are WorkoutSessionSkips.kt.
//

package com.dredfit.ui.workout

import com.dredfit.core.EngineConfig
import com.dredfit.ui.workout.SkipConfirmation.Kind
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.Words
import com.dredfit.workout.leaveExercise
import com.dredfit.workout.setsPerformedHere
import com.dredfit.workout.skipRestOfExercise
import com.dredfit.workout.skipSet
import com.dredfit.workout.skipsLeaveAMovement

/** The exercise-level escape: its words, its identifier and its question. */
data class ExerciseEscape(val title: Words, val identifier: String, val kind: Kind)

/**
 * The set-level skip's question, or null when it would take the movement
 * with it — then the escape beside it says so in its own label instead of
 * doing it quietly under a word that promises less. The probe can ALWAYS be
 * skipped: it takes no volume off anything and comes back next appearance.
 */
fun WorkoutSession.setSkipKind(): Kind? = when {
    onProbeSet -> Kind.probeSet
    !skipsLeaveAMovement(1) -> null
    else -> Kind.workingSet
}

/**
 * The exercise-level escape, and the landing its label names. The two
 * controls collapse into one wherever they would do the same thing: on the
 * floor both take the movement, and on the last set "the remaining sets" ARE
 * this set. None on the probe set: the working sets are behind, and "skip
 * the exercise" would throw away a movement that was trained.
 */
fun WorkoutSession.exerciseEscape(): ExerciseEscape? {
    if (onProbeSet) return null
    val leave = ExerciseEscape(Words.of("Skip exercise"), "exercise-skip", Kind.exercise)
    if (!skipsLeaveAMovement(1)) return leave
    if (isLastSet) return null
    if (setsPerformedHere < EngineConfig.setsFloor) return leave
    return ExerciseEscape(Words.of("Skip remaining sets"), "exercise-skip-rest", Kind.restOfSets)
}

/** What a confirmed question does. */
fun WorkoutSession.perform(kind: Kind) = when (kind) {
    Kind.probeSet, Kind.workingSet -> skipSet()
    Kind.restOfSets -> skipRestOfExercise()
    Kind.exercise -> leaveExercise()
}
