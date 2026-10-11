//
//  Port of ios/DredfitTests/WorkoutSessionTests.swift: the workout flow
//  without its screens — every rule a tap, a tick, a backgrounded phone or a
//  process death runs into. The spies and helpers are WorkoutSessionTestCase.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.core.FeedbackResult
import com.dredfit.store.AppStore
import com.dredfit.workout.TechniqueTarget
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.EditTarget
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.canExtendRest
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.extendRest
import com.dredfit.workout.finishNow
import com.dredfit.workout.leaveExercise
import com.dredfit.workout.restTechniqueTarget
import com.dredfit.workout.sceneCameBack
import com.dredfit.workout.sceneLeft
import com.dredfit.workout.skipRest
import com.dredfit.workout.skipRestOfExercise
import com.dredfit.workout.skipSet
import com.dredfit.workout.startAdjusting
import com.dredfit.workout.startDeclaringHoldTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSessionTest : WorkoutSessionTestCase() {

    private fun started(store: AppStore = makeStore(), session: com.dredfit.core.Session? = null): Pair<AppStore, WorkoutSession> {
        val flow = makeFlow(store, session)
        flow.declineWarmup()
        return store to flow
    }

    // MARK: - Sets and rests

    @Test
    fun doneOnASetRestsAndTheRestHandsOverTheNextSet() {
        val (store, flow) = started()
        signals.events.clear()

        flow.completeSet()
        assertEquals(Phase.Rest(60), flow.phase)
        assertEquals(60, flow.restClock.remaining)
        assertEquals(clock.plusSeconds(60), store.pendingWorkout?.restEndDate,
                     "a rest is written down the moment it starts")
        assertEquals(clock.plusSeconds(60), tile.updates.last().restEndDate)

        run(flow, 60)
        assertEquals(Phase.Work, flow.phase)
        assertEquals(1, flow.setIndex)
        assertEquals(listOf(Event.Done, Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones,
                     "the set's done, the rest's 3-2-1 and its go — nothing twice")
    }

    @Test
    fun aRestIsPrimedOnceASecondBeforeItsFirstTick() {
        val (_, flow) = started()
        signals.primes = 0
        flow.completeSet()
        signals.events.clear()

        val primedAt = WorkoutSession.countdownSignalSeconds + 1
        run(flow) { flow.restClock.remaining == primedAt + 1 }
        assertEquals(0, signals.primes, "primed at the top of the rest, it would be cold by the 3")
        run(flow, 1)
        assertEquals(1, signals.primes)
        assertEquals(emptyList(), signals.tones)
        run(flow, primedAt)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aRestIsExtendedUpToTwiceWhatItPlannedAndNoFurther() {
        val (_, flow) = started()
        flow.completeSet()
        repeat(10) { flow.extendRest() }
        assertEquals(Phase.Rest(120), flow.phase)
        assertEquals(120, flow.restClock.remaining)
        assertFalse(flow.canExtendRest)
    }

    @Test
    fun theLastSetRestsForTheExerciseAndOpensTheNextOneWithoutItsDeclaration() {
        val (_, flow) = started()
        flow.setIndex = 2
        flow.holdDeclared = 30
        flow.completeSet()
        assertEquals(Phase.Rest(flow.exercise.restExerciseSec), flow.phase)

        run(flow) { flow.phase == Phase.Work }
        assertEquals(1, flow.exIndex)
        assertEquals(0, flow.setIndex)
        assertNull(flow.holdDeclared, "a time declared for one movement does not set the next one's clock")
    }

    // MARK: - The adjuster

    @Test
    fun okWritesWhatThePanelWasOpenedOnNotWhatWasOpenBefore() {
        val (store, flow) = started()
        flow.startDeclaringHoldTime()
        assertEquals(EditTarget.HoldTime, flow.editing)
        flow.startAdjusting()
        assertEquals(EditTarget.Set, flow.editing, "the panel's mode is set by whoever opens it")
        flow.adjustValue = 6
        flow.commitSetEdit()
        assertNull(flow.editing)
        assertNull(flow.holdDeclared)
        assertEquals(6, assertNotNull(flow.actuals[flow.exercise.pattern]).first())
        assertEquals(6, store.pendingWorkout?.setActuals?.get(flow.exercise.pattern)?.first(),
                     "an entered number is written down at once")
    }

    @Test
    fun theProbesNumberGoesToItsOwnChannel() {
        val (_, flow) = started(session = probeSession())
        flow.setIndex = flow.exercise.sets
        assertTrue(flow.onProbeSet)
        flow.startAdjusting()
        assertEquals(6, flow.adjustValue, "the probe's own target, not the working sets'")
        flow.adjustValue = 7
        flow.commitSetEdit()
        assertEquals(7, flow.probeActuals[flow.exercise.pattern])
        assertNull(flow.actuals[flow.exercise.pattern],
                   "folding the probe into the working sets would average two variations")
    }

    @Test
    fun doneOnAProbeNobodyCorrectedRecordsItsTarget() {
        val (_, flow) = started(session = probeSession())
        flow.setIndex = flow.exercise.sets
        flow.completeSet()
        assertEquals(6, flow.probeActuals[flow.exercise.pattern])
        assertNull(flow.actuals[flow.exercise.pattern])
    }

    @Test
    fun theRestBeforeAProbeOffersTheProbesTechnique() {
        val (_, flow) = started(session = probeSession())
        flow.setIndex = flow.exercise.sets - 1
        flow.completeSet()
        assertEquals(Phase.Rest(flow.exercise.restSetSec), flow.phase)
        val probe = assertNotNull(flow.exercise.probe)
        assertEquals(TechniqueTarget(probe, of = flow.exercise.pattern), flow.restTechniqueTarget,
                     "the one movement on this screen nobody has done before")
    }

    // MARK: - Skips

    @Test
    fun skippingASetCountsItAndOpensTheNext() {
        val (store, flow) = started()
        flow.skipSet()
        assertEquals(1, flow.setsSkipped[flow.exercise.pattern])
        assertEquals(1, flow.setIndex)
        assertEquals(Phase.Work, flow.phase, "no rest after a set nobody did")
        assertEquals(1, store.pendingWorkout?.setIndex)
    }

    @Test
    fun skippingTheLastSetLeftTakesItAndMovesOn() {
        val (_, flow) = started()
        val pattern = flow.exercise.pattern
        flow.setIndex = 2
        flow.skipRestOfExercise()
        assertEquals(1, flow.setsSkipped[pattern])
        assertFalse(pattern in flow.skippedPatterns, "two sets were done: the movement was trained")
        assertEquals(1, flow.exIndex)
    }

    @Test
    fun aSkipThatWouldLeaveTooFewSetsTakesTheWholeMovement() {
        val (_, flow) = started()
        val pattern = flow.exercise.pattern
        flow.setIndex = 1
        flow.skipRestOfExercise()
        assertTrue(pattern in flow.skippedPatterns)
        assertNull(flow.setsSkipped[pattern])
        assertEquals(1, flow.exIndex)
    }

    @Test
    fun leavingAnExerciseErasesWhatItRecorded() {
        val (_, flow) = started()
        val pattern = flow.exercise.pattern
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.leaveExercise()
        assertNull(flow.actuals[pattern], "a skip wins over an actual")
        assertTrue(pattern in flow.skippedPatterns)
        assertEquals(1, flow.exIndex)
        assertEquals(Phase.Work, flow.phase)
    }

    @Test
    fun leavingTheLastExerciseOffersTheCoolDown() {
        val (store, flow) = started()
        flow.exIndex = flow.exercises.size - 1
        flow.leaveExercise()
        assertEquals(Phase.CooldownIntro, flow.phase)
        assertEquals(true, store.pendingWorkout?.atFeedback,
                     "with the work behind, a process death restores onto the rating")
    }

    // MARK: - Finish now

    @Test
    fun finishNowInsideAMovementCallsItNotFinished() {
        val (_, flow) = started()
        val first = flow.exercise.pattern
        flow.completeSet()
        flow.skipRest()
        flow.finishNow()
        assertEquals(Phase.Feedback, flow.phase)
        assertEquals(first, flow.interruptedPattern)
        assertEquals(flow.exercises.map { it.pattern }.toSet(), flow.skippedPatterns,
                     "the half-done movement is a skip to the engine too; the label is the difference")
        assertEquals(1, tile.ended)
    }

    @Test
    fun finishNowInTheRestAfterALastSetCountsThatMovementDone() {
        val (_, flow) = started()
        val first = flow.exercise.pattern
        flow.setIndex = 2
        flow.completeSet()
        flow.finishNow()
        assertNull(flow.interruptedPattern)
        assertFalse(first in flow.skippedPatterns)
        assertEquals(flow.exercises.size - 1, flow.skippedPatterns.size)
    }

    // MARK: - The rating

    @Test
    fun theRatingIsToldTheWorkoutLessTheTimeAway() {
        val (store, flow) = started()
        advance(600)
        flow.sceneLeft()
        advance(1_200)
        flow.sceneCameBack()
        assertEquals(1_200, flow.awaySec)
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        assertEquals(600, assertNotNull(store.records.lastOrNull()).durationSec)
        assertNull(store.pendingWorkout, "a rated workout leaves nothing to resume")
    }
}
