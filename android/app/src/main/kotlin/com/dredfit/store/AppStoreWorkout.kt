//
//  The lifecycle of a workout in progress, as the store keeps it.
//  Port of ios/Dredfit/AppStore+Workout.swift. WorkoutSessionStore holds the
//  windows and decides what a settlement records; the store measures against
//  them and writes the result.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Session
import com.dredfit.core.generateSession
import com.dredfit.core.sessionWithoutTheOneTimeRelease
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.workout.WorkoutSessionStore
import java.time.Duration
import java.time.Instant

/** The plan the store hands out for `state`: the one the engine draws —
 *  unless the workout in progress was started on the plan a build without
 *  the pull-cap memory drew; that workout carries on as it was started. */
fun AppStore.session(state: EngineState): Session {
    val drawn = Engine.generateSession(state)
    val snap = pendingWorkout
    if (snap == null || WorkoutSessionStore.valid(snap, drawn, state.counter) != null) return drawn
    val started = Engine.sessionWithoutTheOneTimeRelease(state)
    return if (WorkoutSessionStore.valid(snap, started, state.counter) == null) drawn else started
}

private fun AppStore.validPendingWorkout(): WorkoutSnapshot? =
    WorkoutSessionStore.valid(pendingWorkout, nextSession, engineState.counter)

/** Fresh enough to be the same occasion, and nothing completed today. */
fun AppStore.resumableWorkout(now: Instant = clock.instant()): WorkoutSnapshot? {
    val snap = validPendingWorkout() ?: return null
    if (doneToday || Duration.between(snap.savedAt, now) >= WorkoutSessionStore.resumeWindow) return null
    return snap
}

/** Past the occasion but not yet forgotten — the band where the athlete is
 *  ASKED rather than answered for. */
fun AppStore.unfinishedWorkoutAwaitingAnswer(now: Instant = clock.instant()): WorkoutSnapshot? {
    val snap = validPendingWorkout() ?: return null
    if (doneToday) return null
    val age = Duration.between(snap.savedAt, now)
    if (age < WorkoutSessionStore.resumeWindow || age >= WorkoutSessionStore.forgottenAfter) return null
    return snap
}

/**
 * The automatic path, and the ONLY one that decides for the athlete: a
 * workout nobody came back to for twelve hours. A flow on screen OWNS the
 * snapshot — settling underneath it would advance the counter and drop the
 * rating the athlete then gave (`completeWorkout`'s replay guard).
 */
fun AppStore.settleAbandonedWorkout(now: Instant = clock.instant()): Boolean {
    if (workoutIsOnScreen) return false
    val snap = pendingWorkout ?: return false
    if (!WorkoutSessionStore.isForgotten(snap.savedAt, now)) return false
    return settlePendingWorkout()
}

/** Writes what was done and clears the snapshot either way: one that can no
 *  longer be recorded honestly must not linger to be asked about tomorrow. */
private fun AppStore.settlePendingWorkout(): Boolean {
    if (pendingWorkout == null) return false
    val session = nextSession
    val snap = WorkoutSessionStore.valid(pendingWorkout, session, engineState.counter)
    if (snap == null) {
        update { it.copy(pendingWorkout = null) }
        return false
    }
    // `completeWorkout` clears the snapshot in the same write that records it.
    val settled = WorkoutSessionStore.settlement(snap, session)
    completeWorkout(
        session = session,
        // The regulator's neutral answer stands in for a rating nobody gave.
        result = FeedbackResult.plan,
        overrides = settled.overrides,
        setActuals = settled.setActuals,
        skipped = settled.skipped,
        setsSkipped = settled.setsSkipped,
        skippedSets = settled.skippedSets,
        skippedWithNumber = settled.skippedWithNumber,
        probes = settled.probes,
        durationSec = settled.durationSec,
        warmupSec = settled.warmupSec, cooldownSec = settled.cooldownSec,
        interrupted = settled.interrupted,
        raised = settled.raised,
        date = settled.date)
    return true
}

/** Called on every phase transition of the flow. */
fun AppStore.saveWorkoutSnapshot(snapshot: WorkoutSnapshot) {
    update { it.copy(pendingWorkout = snapshot) }
}

fun AppStore.clearWorkoutSnapshot() {
    if (pendingWorkout == null) return
    update { it.copy(pendingWorkout = null) }
}
