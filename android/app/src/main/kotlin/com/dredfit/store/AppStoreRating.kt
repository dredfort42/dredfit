//
//  Taking the last rating back: whether it can be. The change itself,
//  `changeLastRating`, is in AppStore.kt where the state is set.
//  Port of ios/Dredfit/AppStore+Rating.swift.
//

package com.dredfit.store

import com.dredfit.journal.WorkoutRecord

val AppStore.canChangeLastRating: Boolean get() = ratingRedo() != null

/** The undo and the record it belongs to. */
data class RatingRedo(val undo: RatingUndo, val record: WorkoutRecord)

/**
 * The whole guard in one place: an undo that belongs to the last record, a
 * state still standing exactly where that record left it, no second workout
 * since — and no workout already under way, which none of the other guards
 * can see and which re-applying the rating would take down silently.
 */
fun AppStore.ratingRedo(): RatingRedo? {
    val undo = settings.lastRatingUndo ?: return null
    val record = records.lastOrNull() ?: return null
    if (record.sessionNumber != undo.session.sessionNumber ||
        undo.state.counter + 1 != undo.session.sessionNumber ||
        engineState.counter != record.sessionNumber ||
        record.positionsAfter != currentPositions ||
        pendingWorkout?.hasProgress == true) return null
    return RatingRedo(undo, record)
}
