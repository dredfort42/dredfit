//
//  What survives a backgrounded app or a process death, and the two ways out
//  of a workout that is not finished: "Finish now" and discarding it. Port of
//  ios/Dredfit/WorkoutSession+Snapshot.swift.
//
//  On Android this is THE mechanism for process death: the system kills a
//  backgrounded app, and the snapshot written on every phase transition is
//  what `restore` picks up — mid-rest, mid-hold (the set starts over) or on a
//  countdown's last half-second exactly as iOS does.
//

package com.dredfit.workout

import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.clearWorkoutSnapshot
import com.dredfit.store.saveWorkoutSnapshot
import com.dredfit.workout.WorkoutSession.Phase
import java.time.Instant

/** The app went to the background while the process lives on. No persist:
 *  the next transition writes the larger `awaySec`. */
fun WorkoutSession.sceneLeft() {
    absence.leave(now(), restEndDate = restClock.endDate)
}

fun WorkoutSession.sceneCameBack() {
    // Read before `comeBack` spends the stamp.
    val wasAway = absence.isAway
    awaySec += absence.comeBack(now())
    // Time away can outlast the prime.
    if (wasAway) primeComingBack()
}

/** Called on every phase transition and whenever an actual changes. */
fun WorkoutSession.persistProgress() {
    var restEnd: Instant? = null
    var restTotal: Int? = null
    var restPlan: Int? = null
    val p = phase
    if (p is Phase.Rest) {
        // A PAUSED rest has no end date; written as nil it would read back as
        // "no rest was running" and hand back the set just finished. The
        // seconds it froze with — at least one — counted from now.
        restEnd = restClock.endDate ?: now().plusSeconds(maxOf(restClock.remaining, 1).toLong())
        restTotal = p.seconds
        restPlan = restPlanned
    }
    store.saveWorkoutSnapshot(WorkoutSnapshot(
        sessionNumber = session.sessionNumber,
        exIndex = exIndex, setIndex = setIndex,
        restEndDate = restEnd, restTotalSec = restTotal, restPlannedSec = restPlan,
        setActuals = actuals, setsSkipped = setsSkipped,
        skippedSetIndices = SetFacts.stored(skippedSetIndices),
        skippedWithNumberIndices = SetFacts.stored(skippedWithNumber),
        probes = probeActuals,
        skipped = skippedPatterns,
        workoutStart = workoutStart ?: now(), savedAt = now(),
        fingerprint = WorkoutSnapshot.fingerprint(session),
        // With the work behind — the cool-down and its offer included — a
        // process death restores onto the rating.
        atFeedback = if (phase == Phase.Feedback || phase == Phase.Cooldown || phase == Phase.CooldownIntro) true else null,
        atExerciseSummary = if (phase == Phase.ExerciseSummary) true else null,
        holdDeclaredSec = holdDeclared,
        approxSets = if (holdApproxSets.isEmpty()) null else holdApproxSets.sorted(),
        tapEndedSets = if (holdTapEndedSets.isEmpty()) null else holdTapEndedSets.sorted(),
        holdMeasuredSec = holdMeasured.ifEmpty { null },
        interrupted = interruptedPattern,
        warmupSec = warmupSec,
        // From the offer the block can no longer begin: zero.
        cooldownSec = if (phase == Phase.CooldownIntro) 0 else cooldownSec,
        awaySec = if (awaySec == 0) null else awaySec,
        raisedSteps = raisedSteps.ifEmpty { null }))
}

/**
 * A rest still running resumes inside it; one that ran out lands on the set
 * it was leading into. Holds never restore mid-count — the set starts over.
 * Indices are clamped even though the snapshot was validated.
 */
fun WorkoutSession.restore(snap: WorkoutSnapshot) {
    exIndex = minOf(maxOf(snap.exIndex, 0), exercises.size - 1)
    // The probe is a set of this exercise too.
    setIndex = minOf(maxOf(snap.setIndex, 0), maxOf(0, totalSets - 1))
    actuals = snap.facts
    setsSkipped = snap.skips
    skippedSetIndices = snap.skippedSets
    skippedWithNumber = snap.skippedWithNumber
    probeActuals = snap.probeFacts
    skippedPatterns = snap.skipped
    workoutStart = snap.workoutStart
    // The absence begins where the workout stopped owing the athlete
    // anything — the END of a rest on schedule, not the last write.
    awaySec = (snap.awaySec ?: 0) +
        SetFacts.awayGained(savedAt = snap.savedAt, restEndDate = snap.restEndDate, now = now())
    interruptedPattern = snap.interrupted
    warmupSec = snap.warmupSec
    cooldownSec = snap.cooldownSec
    holdApproxSets = snap.approximateSets
    holdTapEndedSets = snap.endedByTapSets
    holdMeasured = snap.measuredHold
    // A declared time outlives a process death.
    holdDeclared = snap.holdDeclaredSec
    raisedSteps = snap.raises
    if (snap.atFeedback == true) {
        phase = Phase.Feedback
        return
    }
    if (snap.atExerciseSummary == true) {
        phase = Phase.ExerciseSummary
        return
    }
    val end = snap.restEndDate
    val total = snap.restTotalSec
    if (end != null && total != null && end > now()) {
        restClock.run(until = end, now = now())
        // An older snapshot has no planned value; the total stands in.
        restPlanned = snap.restPlannedSec ?: total
        phase = Phase.Rest(total)
    } else {
        if (end != null && !(isLastSet && isLastExercise)) {
            // The declaration and the marks belong to the movement behind.
            if (isLastSet) enterNextExercise() else setIndex += 1
        }
        phase = Phase.Work
    }
}

/** What a fresh tile opens with — a resumed workout can start mid-rest. */
fun WorkoutSession.currentActivityState(): ActivityState {
    if (phase == Phase.ExerciseSummary) {
        return ActivityState(ActivityState.Phase.work, Words.name(exercise.name), Words.of("Held"), null)
    }
    if (phase is Phase.Rest) {
        return ActivityState(ActivityState.Phase.rest, nextLabel, restActivityDetail, restClock.endDate)
    }
    return activityWorkState()
}

val WorkoutSession.hasProgress: Boolean
    get() {
        if (phase is Phase.Rest || phase == Phase.ExerciseSummary) return true
        return exIndex > 0 || setIndex > 0 || actuals.isNotEmpty() || skippedPatterns.isNotEmpty()
    }

/** Settles what is not finished (`SetFacts.settlement`) and proceeds to the
 *  rating. */
fun WorkoutSession.finishNow() {
    // The cool-down QUESTION is behind the work too.
    if (phase == Phase.Cooldown || phase == Phase.CooldownIntro) {
        finishCooldown()
        return
    }
    editing = null
    clearBlockPause()
    holdClock.freeze()
    holdCountInClock.freeze()
    holdSwitchClock.freeze()
    leaveExerciseState()
    // A movement is BEHIND US in two places: the rest after its last set and
    // the summary of a finished hold.
    val currentIsDone = (phase is Phase.Rest && isLastSet) || phase == Phase.ExerciseSummary
    // In rest the set that just ended is still `setIndex`.
    val setsBehind = if (phase is Phase.Rest) setIndex + 1 else setIndex
    val settled = SetFacts.settlement(exercises, exIndex = exIndex, setsBehind = setsBehind,
                                      currentIsDone = currentIsDone, alreadySkipped = setsSkipped)
    setsSkipped = settled.setsSkipped
    interruptedPattern = settled.interrupted
    for (pattern in settled.skipped) {
        actuals = actuals - pattern   // a skip wins over an actual
        probeActuals = probeActuals - pattern
        skippedSetIndices = skippedSetIndices - pattern
        skippedWithNumber = skippedWithNumber - pattern
        skippedPatterns = skippedPatterns + pattern
    }
    // The cool-down is never reached from here: zero, set before the persist
    // and only over nil.
    if (cooldownSec == null) cooldownSec = 0
    restClock.stand(at = 0)
    phase = Phase.Feedback
    liveActivity.end()
    persistProgress()
}

/** The workout is thrown away: nothing of it is kept for Today to offer. */
fun WorkoutSession.discard() {
    store.clearWorkoutSnapshot()
}
