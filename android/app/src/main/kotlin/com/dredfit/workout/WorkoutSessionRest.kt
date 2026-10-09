//
//  The rest between sets and exercises — and the one rest that starts the
//  next set by itself, on a hands-free hold run. Port of
//  ios/Dredfit/WorkoutSession+Rest.swift.
//

package com.dredfit.workout

import com.dredfit.workout.WorkoutSession.Companion.countdownSignalSeconds
import com.dredfit.workout.WorkoutSession.Companion.restExtensionSeconds
import com.dredfit.workout.WorkoutSession.Phase

/** What the tile calls the rest it counts down: the one rest that STARTS the
 *  next set must not look like the one that waits for a tap. */
val WorkoutSession.restActivityDetail: Words
    get() = if (restStartsTheNextSet) Words.of("Starts by itself") else Words.of("Next up")

private fun WorkoutSession.restTile(end: java.time.Instant?, detail: Words = restActivityDetail) =
    ActivityState(ActivityState.Phase.rest, nextLabel, detail, end)

/** Reading about what comes next must not cost the set it describes: on the
 *  rest that starts the next hold, the technique sheet freezes the clock. An
 *  ordinary rest runs on. */
fun WorkoutSession.freezeRestForTechnique() {
    if (!restStartsTheNextSet || blockPause.isPaused) return
    restClock.freeze()
    // The tile counts down to a DATE, so a frozen rest takes the date away.
    liveActivity.update(restTile(end = null))
    persistProgress()
}

/** "Skip rest": the set it leads into earns its count-in. */
fun WorkoutSession.skipRest() {
    if (phase !is Phase.Rest) return
    clearBlockPause()
    restClock.stand(at = 0)
    advanceAfterRest(countIn = true)
}

/** Closing the sheet hands the frozen rest back floored at the count-in.
 *  STARTED, not resumed: a resumed countdown keeps the lower second on screen
 *  and the 3-2-1 would lose its 3. A rest held by the PAUSE stays held. */
fun WorkoutSession.resumeRestCountdown() {
    val rest = phase as? Phase.Rest ?: return
    if (restClock.isRunning || blockPause.isPaused) return
    restClock.start(BlockPause.restAfterPause(remaining = restClock.remaining, total = rest.seconds), now())
    primeComingBack()
    liveActivity.update(restTile(end = restClock.endDate))
    persistProgress()
}

/** The cap is twice the rest this transition planned. */
val WorkoutSession.canExtendRest: Boolean
    get() {
        val rest = phase as? Phase.Rest ?: return false
        if (restPlanned <= 0) return false
        return rest.seconds + restExtensionSeconds <= restPlanned * 2
    }

/** Moves the end date, not a counter; the new total goes into the phase,
 *  because the ring divides by it. The 3-2-1 needs no "already played" flag:
 *  an extension raises the second shown, and the way down signals again. */
fun WorkoutSession.extendRest() {
    val rest = phase as? Phase.Rest ?: return
    if (!restClock.isRunning || !canExtendRest) return
    restClock.extend(by = restExtensionSeconds, now = now())
    phase = Phase.Rest(rest.seconds + restExtensionSeconds)
    liveActivity.update(restTile(end = restClock.endDate))
    persistProgress()
}

val WorkoutSession.nextLabel: Words
    get() {
        if (isLastSet) {
            if (isLastExercise) return Words.of("Workout rating")
            val next = exercises[exIndex + 1]
            return Words.join("%@ · %@", Words.name(next.name), Words.display(next))
        }
        val probe = exercise.probe
        if (probe != null && setIndex + 1 == exercise.sets) {
            return Words.of("Probe: %@ · %@", Words.name(probe.name), Words.display(probe))
        }
        return Words.of("%@ · set %lld of %lld", Words.name(exercise.name), setIndex + 2, totalSets)
    }

/** The technique offered during a rest is that of what comes NEXT — the
 *  probe's movement after the last working set of a probing exercise. */
val WorkoutSession.restTechniqueTarget: TechniqueTarget
    get() {
        if (isLastSet && !isLastExercise) return TechniqueTarget(exercises[exIndex + 1])
        val probe = exercise.probe
        if (probe != null && setIndex + 1 == exercise.sets) return TechniqueTarget(probe, of = exercise.pattern)
        return TechniqueTarget(exercise)
    }

fun WorkoutSession.startRest(planned: Int) {
    // The UI suite's fast flag: the full-flow walk must never depend on the
    // runner tapping Skip in time (UITestFlags.kt).
    val seconds = if (UITestFlags.fast) 1 else planned
    restClock.start(seconds, now())
    restPlanned = seconds
    phase = Phase.Rest(seconds)
    liveActivity.update(restTile(end = restClock.endDate))
    persistProgress()
}

fun WorkoutSession.tickRest() {
    when (val reading = restClock.read(now())) {
        Countdown.Reading.Unchanged -> return
        is Countdown.Reading.Ended -> {
            val overshoot = reading.overshoot
            restClock.stand(at = 0)
            // A suspended app comes back to a rest that ended unheard.
            val countIn = SetFacts.restHandsOverWithCountIn(endedByTap = false, overshootSec = overshoot)
            // THE RUN IS A PROMISE TO SOMEBODY WHO IS HERE: past the absence
            // threshold the run is dropped, and one tap buys what is left.
            if (restStartsTheNextSet && overshoot > BlockPause.absenceSeconds.toDouble()) {
                holdAutoRun = false
            }
            // Read AFTER the clearing above, so a dropped run takes its
            // count-in — and this suppression — with it.
            val countInFollows = countIn && restStartsTheNextSet
            if (!countInFollows) playGo()
            announce(nextLabel)
            advanceAfterRest(countIn = countIn)
        }
        is Countdown.Reading.Second -> {
            val second = reading.second
            // no tick spam after backgrounding
            if (restClock.signals(second, within = countdownSignalSeconds)) playTick()
            primeBeforeTheCount(showing = second)
            animate(WorkoutSession.Motion.countdown) { restClock.show(second) }
        }
    }
}

/** `countIn` is what `SetFacts.restHandsOverWithCountIn` decided. */
fun WorkoutSession.advanceAfterRest(countIn: Boolean) {
    // Only a rest ends into the next set.
    if (phase !is Phase.Rest) return
    // One tap bought ONE exercise: the next movement is a decision of its own.
    if (isLastSet) enterNextExercise() else setIndex += 1
    phase = Phase.Work
    liveActivity.update(activityWorkState())
    persistProgress()
    if (runOpensSet(setIndex)) startHold(autoContinued = !countIn)
}

/** The run opens this set by itself — asked of the rule, not restated. */
fun WorkoutSession.runOpensSet(index: Int): Boolean = SetFacts.runOpensSet(index, of = exercise, running = holdAutoRun)

/** The rest on screen will START the next set when it runs out — the only
 *  rest a pause has anything to stop. */
val WorkoutSession.restStartsTheNextSet: Boolean
    get() {
        if (phase !is Phase.Rest || isLastSet) return false
        return runOpensSet(setIndex + 1)
    }
