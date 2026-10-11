//
//  The work itself: a set ending, the adjuster, the note about an all-out set,
//  and every way from one exercise to the next. Port of
//  ios/Dredfit/WorkoutSession+Sets.swift.
//

package com.dredfit.workout

import com.dredfit.core.LoadUnit
import com.dredfit.store.markOwnNumberReported
import com.dredfit.workout.WorkoutSession.EditTarget
import com.dredfit.workout.WorkoutSession.Phase

/** What is left of the session, in minutes — on the work, rest and summary
 *  screens and inside the cool-down; null elsewhere. WITH THE FACTS: the
 *  clock on a hold runs from `SetFacts.holdTarget`. */
val WorkoutSession.minutesLeft: Int?
    get() {
        var index = exIndex
        var behind = setIndex
        when (phase) {
            Phase.Work -> Unit
            is Phase.Rest, Phase.ExerciseSummary -> {
                // The set the rest FOLLOWS is done; `totalSets`, so the probe
                // stays on the number on the rest that announces it.
                behind += 1
                if (behind >= totalSets) { index += 1; behind = 0 }
            }
            Phase.Cooldown -> return cooldownMinutesLeft
            else -> return null
        }
        // The declaration is the CURRENT exercise's, so it travels only while
        // `index` still points at it.
        val ahead = SessionAhead.remaining(exercises, exIndex = index, setsBehind = behind, facts = actuals,
                                           declared = if (index == exIndex) holdDeclared else null)
        return SessionAhead.minutes(ahead, ends = session.cooldownMin)
    }

/** The technique sheet of a guided block is open: the running countdown
 *  freezes, the way back in with it, and the block stops costing time. */
fun WorkoutSession.freezeForPositionTechnique() {
    warmup.clock.freeze()
    cooldown.clock.freeze()
    blockPause.freezeForSheet()
    beginBlockFreeze()
}

fun WorkoutSession.resumePositionCountdown() {
    // A way back in outlives the sheet; a pause outranks it (#34 vs #61).
    blockPause.thawAfterSheet(now())
    if (blockPause.isPaused) {
        primeComingBack()
        return
    }
    // After the guard: a PAUSED block goes on standing still.
    endBlockFreeze()
    when (phase) {
        Phase.Warmup -> warmup.clock.resume(now())
        Phase.Cooldown -> cooldown.clock.resume(now())
        else -> Unit
    }
    primeComingBack()
}

/** The tile's copy of the work screen. */
fun WorkoutSession.activityWorkState(): ActivityState {
    if (isWarmingUp) return ActivityState(ActivityState.Phase.work, Words.of("WARM-UP"), detail = null, restEndDate = null)
    // The probe is one set of the NEXT variation — the tile must not call it
    // by the old movement's name.
    if (current.isProbe) {
        return ActivityState(ActivityState.Phase.work, Words.name(current.name), Words.of("Probe"), restEndDate = null)
    }
    return ActivityState(ActivityState.Phase.work, Words.name(exercise.name),
                         Words.of("set %lld of %lld", setIndex + 1, totalSets), restEndDate = null)
}

fun WorkoutSession.completeSet() {
    // A second Done, landing after either screen has moved on, ends nothing.
    if (phase != Phase.Work && phase != Phase.ExerciseSummary) return
    // The probe records its target — only on its own screen.
    probeActuals = SetFacts.recordingProbe(probeActuals, exercise.pattern,
                                           isProbe = current.isProbe && phase == Phase.Work, target = current.planned)
    // A hold's LAST set gets its summary first; guarded on the phase, because
    // this is also the summary's own exit.
    if (phase != Phase.ExerciseSummary && isLastSet && exercise.unit == LoadUnit.hold &&
        exercise.pattern !in skippedPatterns) {
        startExerciseSummary()
        return
    }
    // A hold has already sounded its own ending (`finishHold`).
    if (!holdSettled && phase != Phase.ExerciseSummary) playDone()
    holdSettled = false
    editing = null
    when {
        // "Finish now" deliberately does not run the cool-down.
        isLastSet && isLastExercise -> startCooldown()
        isLastSet -> startRest(exercise.restExerciseSec)
        else -> startRest(exercise.restSetSec)
    }
}

/** A soft note when the person enters MORE than the plan on a set that is not
 *  the last one. Once per exercise; the entry stands either way. */
fun WorkoutSession.noteMaximumOutOfOrder() {
    val pattern = exercise.pattern
    if (pattern in maximumNoted) return
    if (!SetFacts.maximumOutOfOrder(adjustValue, exercise, set = setIndex)) return
    maximumNoted = maximumNoted + pattern
    animate(WorkoutSession.Motion.note) {
        maximumWarning = Words.of(
            "Going all out on one set weakens the ones after it. What counts is the whole exercise.")
    }
}

/** Leaving an exercise early is a skip and nothing more. */
fun WorkoutSession.leaveExercise() {
    if (phase != Phase.Work) return
    editing = null
    holdSwitchClock.freeze()
    holdCountInClock.freeze()
    val pattern = exercise.pattern
    actuals = actuals - pattern              // a skip wins over an actual
    probeActuals = probeActuals - pattern    // …and over the probe
    setsSkipped = setsSkipped - pattern      // …and over the sets skipped inside it
    skippedSetIndices = skippedSetIndices - pattern
    skippedWithNumber = skippedWithNumber - pattern
    skippedPatterns = skippedPatterns + pattern
    advancePastExercise()
}

/** The pair that makes ONE set of a per-side hold, and everything else scoped
 *  to the set: every way out of a set other than `finishHold` clears them, or
 *  a stale side caps the next set with the smaller-of-two rule. */
fun WorkoutSession.resetHoldSides() {
    holdSecondSide = false
    firstSideHeld = null
    // This set's mark only — it recorded nothing.
    holdApproxSets = holdApproxSets - setIndex
    editing = null
    holdSettled = false
    // Every call site is a departure, and a skip is a person wanting the phone.
    holdAutoRun = false
}

/** What belongs to the EXERCISE rather than to the set. A SET skip keeps it. */
fun WorkoutSession.resetHoldExercise() {
    holdDeclared = null
    holdApproxSets = emptySet()
    holdMeasured = emptyMap()
    holdTapEndedSets = emptySet()
}

/** Past the exercise in front of us, however it ended. */
fun WorkoutSession.advancePastExercise() {
    if (isLastExercise) {
        leaveExerciseState()
        startCooldown()
    } else {
        enterNextExercise()
        phase = Phase.Work
        liveActivity.update(activityWorkState())
        persistProgress()
    }
}

/** Onto the next exercise — the one place the flow moves to it. */
fun WorkoutSession.enterNextExercise() {
    leaveExerciseState()
    exIndex += 1
    setIndex = 0
}

/** Everything scoped to the exercise in front of us. */
fun WorkoutSession.leaveExerciseState() {
    resetHoldSides()
    resetHoldExercise()
    maximumWarning = null
}

/** Opens the adjuster on the DECLARATION — how long this hold will run. */
fun WorkoutSession.startDeclaringHoldTime() {
    adjustValue = targetInForce
    editing = EditTarget.HoldTime
}

/** OK on the work screen's panel: what it writes is decided by what the
 *  panel was opened on, never by what the screen shows now. */
fun WorkoutSession.commitSetEdit() {
    when {
        // A TARGET, not a record.
        editing == EditTarget.HoldTime -> holdDeclared = adjustValue
        current.isProbe -> {
            probeActuals = probeActuals + (exercise.pattern to adjustValue)
            store.markOwnNumberReported()
        }
        else -> {
            actuals = SetFacts.recording(adjustValue, actuals, exercise, set = setIndex)
            numbersEntered = numbersEntered + (exercise.pattern to ((numbersEntered[exercise.pattern] ?: emptySet()) + setIndex))
            noteMaximumOutOfOrder()
            // Spent HERE, on a number actually reported.
            store.markOwnNumberReported()
        }
    }
    editing = null
    persistProgress()   // an entered actual is worth keeping
}

fun WorkoutSession.startAdjusting() {
    adjustValue = targetInForce
    editing = EditTarget.Set
}
