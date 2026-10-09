//
//  The workout in progress as the journal sees it: whether a snapshot still
//  describes the plan ahead, and the two windows that bound how long it is
//  worth picking up. Port of the parts of ios/Dredfit/WorkoutSessionStore.swift
//  the store reads; the settlement of a forgotten workout arrives with the
//  workout flow, which is the only writer of a snapshot.
//

package com.dredfit.workout

import com.dredfit.core.Session
import com.dredfit.journal.WorkoutSnapshot
import java.time.Duration

object WorkoutSessionStore {

    /** Older than this is a different training occasion, not an interrupted one. */
    val resumeWindow: Duration = Duration.ofHours(3)

    /** Past this the workout was FORGOTTEN — elapsed time, not calendar days. */
    val forgottenAfter: Duration = Duration.ofHours(12)

    /** The snapshot is only worth anything while it still describes the plan
     *  the engine would hand out. */
    fun valid(snap: WorkoutSnapshot?, plan: Session, counter: Int): WorkoutSnapshot? {
        if (snap == null || snap.sessionNumber != counter + 1 ||
            snap.fingerprint != WorkoutSnapshot.fingerprint(plan) || !snap.hasProgress) return null
        return snap
    }
}
