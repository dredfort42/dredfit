//
//  Port of ios/DredfitTests/WorkoutSessionTests+DoubleTaps.swift: the second
//  tap of a double tap. The settle window keeps it off the next screen; these
//  pin the other half — a transition reached a second time from a screen
//  that has already moved on does nothing.
//
//  Every Swift test is ported.
//

package com.dredfit

import com.dredfit.core.Pattern
import com.dredfit.workout.GetReady
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.advanceAfterRest
import com.dredfit.workout.beginCooldown
import com.dredfit.workout.beginWarmup
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineCooldown
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.finishCooldown
import com.dredfit.workout.finishWarmup
import com.dredfit.workout.leaveExercise
import com.dredfit.workout.leaveExerciseSummary
import com.dredfit.workout.pauseBlock
import com.dredfit.workout.skipRest
import com.dredfit.workout.skipRestOfExercise
import com.dredfit.workout.skipSet
import com.dredfit.workout.startHold
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WorkoutSessionTestDoubleTaps : WorkoutSessionTestCase() {

    @Test
    fun aSecondSkipRestDoesNotSkipASet() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipRest()
        flow.skipRest()
        assertEquals(1, flow.setIndex)
        assertEquals(Phase.Work, flow.phase)
    }

    @Test
    fun aSecondDoneDoesNotRestartTheRest() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        val end = flow.restClock.endDate
        advance(1)
        flow.completeSet()
        assertEquals(end, flow.restClock.endDate)
        assertEquals(0, flow.setIndex)
    }

    @Test
    fun startingTheWarmUpTwiceDoesNotStartItOver() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        val began = flow.warmupBeganAt
        run(flow, 2)
        flow.beginWarmup()
        assertEquals(began, flow.warmupBeganAt)
        assertEquals(GetReady.countInSeconds - 2, flow.warmup.clock.remaining)
    }

    @Test
    fun decliningTheWarmUpTwiceLeavesTheWorkAlone() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.declineWarmup()
        assertEquals(Phase.Rest(60), flow.phase, "a stale decline must not pull the flow out of a rest")
    }

    @Test
    fun skippingTheCoolDownTwiceEndsItOnce() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        flow.finishCooldown()
        flow.finishCooldown()
        flow.declineCooldown()
        assertEquals(Phase.Feedback, flow.phase)
        assertEquals(1, tile.ended)
    }

    @Test
    fun theSummarysDoneTwiceDoesNotTouchTheRestAfterIt() {
        val store = makeStore()
        val flow = makeFlow(store, holdSession())
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreAntiExt, flow)
        flow.setIndex = 2
        flow.startHold()
        run(flow, GetReady.countInSeconds + 15)
        assertEquals(Phase.ExerciseSummary, flow.phase)
        flow.leaveExerciseSummary()
        val end = flow.restClock.endDate
        advance(1)
        flow.leaveExerciseSummary()
        assertEquals(end, flow.restClock.endDate)
        assertEquals(Phase.Rest(flow.exercise.restExerciseSec), flow.phase)
    }

    @Test
    fun aStaleStartHoldDoesNotStartOneInsideTheRest() {
        val store = makeStore()
        val flow = makeFlow(store, holdSession())
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreAntiExt, flow)
        flow.startHold()
        run(flow, GetReady.countInSeconds + 15)
        assertEquals(Phase.Rest(60), flow.phase)
        flow.startHold()
        assertFalse(flow.holdCountingIn || flow.holding)
    }

    @Test
    fun aStaleSkipLandsOnNothingOnceTheSetHasMovedOn() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipSet()
        flow.skipRestOfExercise()
        flow.leaveExercise()
        assertEquals(Phase.Rest(60), flow.phase)
        assertTrue(flow.setsSkipped.isEmpty())
        assertTrue(flow.skippedPatterns.isEmpty())
    }

    // Each guard on its own. The pairs above (skipRest → advanceAfterRest,
    // declineWarmup → finishWarmup, leaveExerciseSummary → completeSet,
    // declineCooldown → finishCooldown) stop a second tap with either guard
    // alone; these reach each one where its partner cannot.

    @Test
    fun aSkipRestOutsideARestLeavesAPausedBlockPaused() {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        flow.pauseBlock()
        assertTrue(flow.blockPause.isPaused, "the premise")
        flow.skipRest()
        assertTrue(flow.blockPause.isPaused)
    }

    @Test
    fun anAdvanceOutsideARestLeavesTheSetWhereItIs() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.advanceAfterRest(countIn = true)
        assertEquals(0, flow.setIndex)
        assertEquals(Phase.Work, flow.phase)
    }

    @Test
    fun aDeclineDuringTheWarmUpDoesNotEndIt() {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        flow.declineWarmup()
        assertEquals(Phase.Warmup, flow.phase)
    }

    @Test
    fun aStaleWarmUpEndingLeavesTheRestAlone() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.completeSet()
        flow.finishWarmup()
        assertEquals(Phase.Rest(60), flow.phase)
    }

    @Test
    fun theSummarysDoneOnTheWorkScreenLogsNoSet() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.leaveExerciseSummary()
        assertEquals(Phase.Work, flow.phase)
        assertEquals(0, flow.setIndex)
    }

    @Test
    fun startingTheCoolDownTwiceDoesNotStartItOver() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        val began = flow.cooldownBeganAt
        run(flow, 2)
        flow.beginCooldown()
        assertEquals(began, flow.cooldownBeganAt)
        assertEquals(GetReady.countInSeconds - 2, flow.cooldown.clock.remaining)
    }

    @Test
    fun aDeclineDuringTheCoolDownDoesNotEndIt() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        flow.declineCooldown()
        assertEquals(Phase.Cooldown, flow.phase)
    }

    @Test
    fun aStaleSkipOfTheRestOfAMovementTakesNoSetsOff() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.setIndex = 2
        flow.completeSet()
        assertEquals(Phase.Rest(flow.exercise.restExerciseSec), flow.phase, "the premise")
        flow.skipRestOfExercise()
        assertTrue(flow.setsSkipped.isEmpty())
    }
}
