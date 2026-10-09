//
//  Holds: the count-in, the clock, the side switch, Stop, and the summary a
//  hold movement ends on. Port of ios/Dredfit/WorkoutSession+Holds.swift.
//

package com.dredfit.workout

import com.dredfit.core.LoadUnit
import com.dredfit.workout.WorkoutSession.Companion.countdownSignalSeconds
import com.dredfit.workout.WorkoutSession.Companion.holdMistapSeconds
import com.dredfit.workout.WorkoutSession.Phase
import java.time.Instant

/** The tile's copy of a running hold — `hold`, so it shows a countdown. */
fun WorkoutSession.showHoldActivity(until: Instant, detail: Words) {
    liveActivity.update(ActivityState(ActivityState.Phase.hold, Words.name(current.name), detail, until))
}

/** What the tile calls the set a hold is running — `activityWorkState`'s words. */
val WorkoutSession.holdActivityDetail: Words
    get() = if (current.isProbe) Words.of("Probe") else Words.of("set %lld of %lld", setIndex + 1, totalSets)

/**
 * The tap arms the set; the clock waits out a count-in first. A SET THE RUN
 * OPENS HAS NO COUNT-IN OF ITS OWN (`autoContinued`): the rest before it was
 * the lead-in, and its go starts the hold. A TAP still earns its beat.
 * (The UI suite's `--uitest-hold-short/long` seeds are not ported.)
 */
fun WorkoutSession.startHold(autoContinued: Boolean = false) {
    if (phase != Phase.Work) return
    editing = null
    val planned = targetInForce
    // The SECOND side re-armed through here keeps what the first side ran.
    holdTotal = SetFacts.holdSideSeconds(planned = planned, firstSideHeld = if (holdSecondSide) firstSideHeld else null)
    holdClock.show(holdTotal)
    if (autoContinued) {
        // Straight into the hold on the rest's own go.
        holdCountInClock.stand(at = 0)
        val end = holdClock.start(holdTotal, now())
        showHoldActivity(until = end, detail = holdActivityDetail)
        return
    }
    val countInEnd = holdCountInClock.start(GetReady.countInSeconds, now())
    // Started on its four, a second no tick reports — primed here.
    primeBeforeTheCount(showing = holdCountInClock.remaining)
    showHoldActivity(until = countInEnd, detail = Words.of("Get ready"))
}

/** 3-2-1 and then the go — here the ticks are wanted. */
fun WorkoutSession.tickHoldCountIn() {
    when (val reading = holdCountInClock.read(now())) {
        Countdown.Reading.Unchanged -> return
        is Countdown.Reading.Ended -> {
            // A signal nobody could hear cannot be what started a plank:
            // count them in again.
            if (reading.overshoot > SetFacts.restGoHeardWithinSec) {
                val again = holdCountInClock.start(GetReady.countInSeconds, now())
                primeBeforeTheCount(showing = holdCountInClock.remaining)
                showHoldActivity(until = again, detail = Words.of("Get ready"))
                return
            }
            holdCountInClock.freeze()
            playGo()
            announce(Words.name(current.name))
            // The total was fixed at the tap: a FULL set, not its remains.
            val holdEnd = holdClock.start(holdTotal, now())
            showHoldActivity(until = holdEnd, detail = holdActivityDetail)
        }
        is Countdown.Reading.Second -> {
            val second = reading.second
            if (holdCountInClock.signals(second, within = countdownSignalSeconds)) playTick()
            // Asked from both places, so a longer count-in is primed too.
            primeBeforeTheCount(showing = second)
            animate(WorkoutSession.Motion.countdown) { holdCountInClock.show(second) }
        }
    }
}

/** A hold that ran to the end of its clock is credited in full, however late
 *  the tick that noticed it. */
fun WorkoutSession.tickHold() {
    when (val reading = holdClock.read(now())) {
        Countdown.Reading.Unchanged -> return
        // Silent: `finishHold` sounds what comes next (#186).
        is Countdown.Reading.Ended -> finishHold(heldSeconds = holdTotal)
        is Countdown.Reading.Second -> {
            val second = reading.second
            if (holdClock.signals(second, within = countdownSignalSeconds)) playTick()
            primeBeforeTheCount(showing = second)
            animate(WorkoutSession.Motion.countdown) { holdClock.show(second) }
        }
    }
}

/**
 * "Stop" sits where "Start hold" was: inside the first seconds it is a
 * double tap and the set stays available. Past the grace the seconds are
 * read off the BUTTON (`holdStopRecords`), never the clock at the tap.
 */
fun WorkoutSession.stopHoldEarly() {
    if (!holding) return
    val records = holdStopRecords
    if (records == null) {
        holdClock.stand(at = holdTotal)
        liveActivity.update(activityWorkState())
        return
    }
    // An ESTIMATE, and the summary says so.
    holdApproxSets = holdApproxSets + setIndex
    // The side that ends the set takes the thumb's ceiling.
    if (!current.perSide || holdSecondSide) holdTapEndedSets = holdTapEndedSets + setIndex
    finishHold(heldSeconds = records)
}

/** Per-side holds run the pause and the second side by themselves; the
 *  recorded actual is the smaller of the two sides. */
fun WorkoutSession.finishHold(heldSeconds: Int) {
    holdClock.freeze()
    if (current.perSide && !holdSecondSide) {
        firstSideHeld = heldSeconds
        holdSecondSide = true
        startHoldSwitchPause()
        return
    }
    val held = minOf(heldSeconds, firstSideHeld ?: heldSeconds)
    holdSecondSide = false
    firstSideHeld = null
    recordHoldActual(heldSeconds = held)
    // Only the LAST set stops here; any other flows into its rest.
    if (!isLastSet) {
        completeSet()
        return
    }
    // HERE, where the effort actually stopped — eyes may be shut in a plank.
    playDone()
    // The PROBE keeps a settled screen of its own.
    if (current.isProbe) {
        holdSettled = true
        liveActivity.update(activityWorkState())
        persistProgress()
        return
    }
    startExerciseSummary()
}

/** Every set of the finished hold movement, on one screen. */
fun WorkoutSession.startExerciseSummary() {
    editing = null
    holdSettled = false
    holdAutoRun = false
    phase = Phase.ExerciseSummary
    liveActivity.update(ActivityState(ActivityState.Phase.work, Words.name(exercise.name), Words.of("Held"), null))
    persistProgress()
}

fun WorkoutSession.startHoldSwitchPause() {
    playSwitch()
    val end = holdSwitchClock.start(Cooldown.switchPauseSeconds, now())
    showHoldActivity(until = end, detail = Words.of("Switch sides"))
}

/** No 3-2-1 inside the pause: ticks would bury the switch tone. */
fun WorkoutSession.tickHoldSwitchPause() {
    when (val reading = holdSwitchClock.read(now())) {
        Countdown.Reading.Unchanged -> return
        is Countdown.Reading.Ended -> {
            // The count-in's rule: a go nobody heard does not start a side.
            if (reading.overshoot > SetFacts.restGoHeardWithinSec) {
                val again = holdSwitchClock.start(Cooldown.switchPauseSeconds, now())
                showHoldActivity(until = again, detail = Words.of("Switch sides"))
                return
            }
            holdSwitchClock.freeze()
            playGo()
            announce(SplitStageWords(WarmupHalves.sides).secondHalf)
            // BOTH SIDES OF ONE SET CARRY THE SAME LOAD — and `holdTotal`
            // itself moves, or an early stop would report more than was held.
            holdTotal = SetFacts.holdSideSeconds(planned = holdTotal, firstSideHeld = firstSideHeld)
            val holdEnd = holdClock.start(holdTotal, now())
            showHoldActivity(until = holdEnd, detail = SplitStageWords(WarmupHalves.sides).secondHalf)
        }
        is Countdown.Reading.Second -> {
            val second = reading.second
            animate(WorkoutSession.Motion.countdown) { holdSwitchClock.show(second) }
        }
    }
}

/** Snapped to a storable number, onto the set actually held. */
fun WorkoutSession.recordHoldActual(heldSeconds: Int) {
    val held = SetFacts.snap(heldSeconds.toDouble(), LoadUnit.hold)
    if (current.isProbe) {
        probeActuals = probeActuals + (exercise.pattern to held)
        return
    }
    actuals = SetFacts.recording(held, actuals, exercise, set = setIndex)
    // The clock's own word, kept apart from any later correction.
    holdMeasured = holdMeasured + (setIndex to held)
}

/**
 * Wakes the haptics one second before a 3-2-1. `second` is the one a
 * countdown has just come to show, by a tick or by a START: `Countdown.read`
 * never reports the second a countdown started on, so a caller asks from
 * both places — the count-in's prime died once when its length went 5 → 4.
 */
fun WorkoutSession.primeBeforeTheCount(showing: Int) {
    if (showing == countdownSignalSeconds + 1 && store.settings.soundsEnabled) signals.prime()
}

// Thin wrappers, gated by the one sounds toggle.
fun WorkoutSession.playTick() = signals.tick(store.settings.soundsEnabled)
fun WorkoutSession.playGo() = signals.go(store.settings.soundsEnabled)
fun WorkoutSession.playSwitch() = signals.switchSides(store.settings.soundsEnabled)
fun WorkoutSession.playDone() = signals.done(store.settings.soundsEnabled)
fun WorkoutSession.playWorkoutDone() = signals.workoutDone(store.settings.soundsEnabled)
fun WorkoutSession.playMilestone() = signals.milestone(store.settings.soundsEnabled)

/** "Start exercise": one tap buys every set of the hold. */
fun WorkoutSession.startHoldExercise() {
    holdAutoRun = true
    startHold()
}

/** The summary's own primary control is `completeSet` — the same flow past
 *  it as the tap that logs a set. */
fun WorkoutSession.leaveExerciseSummary() {
    if (phase != Phase.ExerciseSummary) return
    holdApproxSets = emptySet()
    holdMeasured = emptyMap()
    holdTapEndedSets = emptySet()
    completeSet()
}

/** The screen a hold exercise OPENS on: nothing running, nothing behind. */
val WorkoutSession.holdExerciseIntro: Boolean
    get() = current.unit == LoadUnit.hold && !current.isProbe && !holdAutoRun && setIndex == 0 && !holdSettled &&
        !holding && !holdCountingIn && !holdSwitchPausing

/** The clock is on the person — named once, so four things stand down alike. */
val WorkoutSession.holdUnderWay: Boolean get() = holding || holdCountingIn || holdSwitchPausing

/** What a Stop right now would RECORD — null inside the mis-tap grace.
 *  `>`, not `>=`: the rounded 3 covers a real 2.5 s. */
val WorkoutSession.holdStopRecords: Int?
    get() {
        val held = holdTotal - holdClock.remaining
        if (held.toDouble() <= holdMistapSeconds) return null
        return SetFacts.holdEndedByTap(heldSeconds = held)
    }

/** What the set under way runs at — one reading for the screen and the
 *  clock. The PROBE runs at the probe's own number. */
val WorkoutSession.targetInForce: Int
    get() = if (current.isProbe) probeActuals[exercise.pattern] ?: current.planned
    else SetFacts.holdTarget(actuals, exercise, set = setIndex, declared = holdDeclared)

/** The big number on the work screen — a promise the clock is held to. */
val WorkoutSession.workNumber: Int
    get() {
        if (holdCountingIn) return holdCountInClock.remaining
        if (holdSwitchPausing) return holdSwitchClock.remaining
        if (holding) return holdClock.remaining
        return SetFacts.holdSideSeconds(planned = targetInForce, firstSideHeld = if (holdSecondSide) firstSideHeld else null)
    }
