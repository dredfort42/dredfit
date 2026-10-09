//
//  The workout in progress as the journal sees it: whether a snapshot still
//  describes the plan ahead, the two windows that bound how long it is worth
//  picking up, and what settling a forgotten one records. Pure; the store
//  applies the windows, keeps the snapshot and writes what this decides.
//  Port of ios/Dredfit/WorkoutSessionStore.swift.
//

package com.dredfit.workout

import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.journal.WorkoutSnapshot
import java.time.Duration
import java.time.Instant

object WorkoutSessionStore {

    /** Older than this is a different training occasion, not an interrupted one. */
    val resumeWindow: Duration = Duration.ofHours(3)

    /** Past this the workout was FORGOTTEN — elapsed time, not calendar days. */
    val forgottenAfter: Duration = Duration.ofHours(12)

    /** A workout last written at `lastWrite` was forgotten by `now` — the
     *  settlement's rule, and the end of the ongoing notification (WorkoutBeat). */
    fun isForgotten(lastWrite: Instant, now: Instant): Boolean = Duration.between(lastWrite, now) >= forgottenAfter

    /** The snapshot is only worth anything while it still describes the plan
     *  the engine would hand out. */
    fun valid(snap: WorkoutSnapshot?, plan: Session, counter: Int): WorkoutSnapshot? {
        if (snap == null || snap.sessionNumber != counter + 1 ||
            snap.fingerprint != WorkoutSnapshot.fingerprint(plan) || !snap.hasProgress) return null
        return snap
    }

    /** What `completeWorkout` is handed for a workout nobody came back to. */
    data class Settlement(
        val overrides: Map<Pattern, Double>,
        val setActuals: Map<Pattern, List<Int>>,
        val skipped: Set<Pattern>,
        val setsSkipped: Map<Pattern, Int>,
        val skippedSets: Map<Pattern, Set<Int>>,
        val skippedWithNumber: Map<Pattern, Set<Int>>,
        val probes: Map<Pattern, Int>,
        val durationSec: Int,
        val warmupSec: Int?,
        val cooldownSec: Int?,
        val interrupted: Pattern?,
        val raised: Map<Pattern, Int>,
        val date: Instant,
    )

    /** What a workout nobody came back to records — dated from `savedAt`,
     *  never now. */
    fun settlement(snap: WorkoutSnapshot, session: Session): Settlement {
        val settled = SetFacts.settlement(
            session.exercises,
            exIndex = snap.exIndex,
            // In rest the set that just ended is still `setIndex`; capped
            // before the `+ 1`, the index comes off disk.
            setsBehind = if (snap.restEndDate != null) minOf(snap.setIndex, Int.MAX_VALUE - 1) + 1 else snap.setIndex,
            currentIsDone = snap.atFeedback == true || snap.atExerciseSummary == true,
            alreadySkipped = snap.skips)
        val skipped = settled.skipped + snap.skipped
        // A skip wins over an actual, the same way it does in the flow.
        val facts = snap.facts - skipped
        val probes = snap.probeFacts - skipped
        val skippedSets = snap.skippedSets - skipped
        val skippedWithNumber = snap.skippedWithNumber - skipped
        return Settlement(
            overrides = SetFacts.overrides(facts, skipping = SetFacts.leftOut(skippedSets, keeping = skippedWithNumber),
                                           exercises = session.exercises),
            setActuals = facts,
            skipped = skipped,
            setsSkipped = settled.setsSkipped,
            skippedSets = skippedSets,
            skippedWithNumber = skippedWithNumber,
            probes = probes,
            // Minus the measured absence, exactly as the flow's own path does.
            // In Long: both numbers come off disk, and Kotlin's Int is
            // Swift's Int32, not its Int.
            durationSec = maxOf(0L, Countdown.seconds(snap.workoutStart, snap.savedAt).toLong() - (snap.awaySec ?: 0))
                .coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            warmupSec = snap.warmupSec,
            // Short of the end of the work the cool-down was never reached.
            cooldownSec = if (snap.atFeedback == true) snap.cooldownSec else 0,
            interrupted = snap.interrupted ?: settled.interrupted,
            // A movement the settlement skips cannot carry a raise.
            raised = snap.raises.filterKeys { it !in skipped },
            // The END, as every record is dated.
            date = snap.savedAt)
    }
}
