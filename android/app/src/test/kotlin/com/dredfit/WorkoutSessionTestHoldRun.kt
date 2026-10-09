//
//  Port of ios/DredfitTests/WorkoutSessionTests+HoldRun.swift: the
//  hands-free run of a hold movement — the rest that opens the next set on
//  its own go, when it drops the run, what a tap, a pause and the technique
//  sheet do to that rest, and the prime before its 3-2-1.
//
//  Every test is ported.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.core.Pattern
import com.dredfit.workout.BlockPause
import com.dredfit.workout.GetReady
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.freezeRestForTechnique
import com.dredfit.workout.restStartsTheNextSet
import com.dredfit.workout.resumeRestCountdown
import com.dredfit.workout.skipRest
import com.dredfit.workout.startHold
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.startRest
import com.dredfit.workout.toggleBlockPause
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSessionTestHoldRun : WorkoutSessionTestCase() {

    // MARK: - The hands-free run

    @Test
    fun aHandsFreeRunOpensTheNextSetOnTheRestsOwnGo() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        assertTrue(flow.restStartsTheNextSet)
        run(flow, 60)
        assertEquals(1, flow.setIndex)
        assertTrue(flow.holding, "no second count-in: the rest's 3-2-1 was the lead-in")
        assertFalse(flow.holdCountingIn)
    }

    @Test
    fun aRunStopsWhenItsRestRanOutWithNobodyThere() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        advance(600)
        flow.tick()
        assertFalse(flow.holdAutoRun)
        assertEquals(1, flow.setIndex)
        assertEquals(Phase.Work, flow.phase)
        assertFalse(flow.holding || flow.holdCountingIn,
                    "the work screen comes back with its own button")
    }

    /** The same threshold as the blocks', to the fraction
     *  (`testAWarmUpBoundaryMissedByAFractionPastTheThresholdFreezes`). */
    @Test
    fun aRestMissedByAFractionPastTheThresholdDropsTheRun() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        val end = assertNotNull(flow.restClock.endDate, "the premise: a rest is running")
        clock = end
        advance(BlockPause.absenceSeconds + 0.6)
        flow.tick()
        assertFalse(flow.holdAutoRun)
    }

    @Test
    fun aRestMissedByExactlyTheThresholdKeepsTheRun() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        val end = assertNotNull(flow.restClock.endDate, "the premise: a rest is running")
        clock = end.plusSeconds(BlockPause.absenceSeconds.toLong())
        flow.tick()
        assertTrue(flow.holdAutoRun)
    }

    @Test
    fun skippingTheRestOfARunCountsTheNextSetIn() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        flow.skipRest()
        assertTrue(flow.holdCountingIn)
        assertEquals(GetReady.countInSeconds, flow.holdCountInClock.remaining)
    }

    @Test
    fun theCountInAfterSkipRestIsPrimedOnceASecondBeforeItsFirstTick() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        signals.primes = 0
        flow.startHoldExercise()
        assertEquals(1, signals.primes, "a tap on Start opens the same count-in")
        run(flow, GetReady.countInSeconds + 15)
        assertTrue(flow.restStartsTheNextSet, "the premise")
        signals.primes = 0
        signals.events.clear()

        flow.skipRest()
        assertTrue(flow.holdCountingIn, "the premise")
        assertEquals(1, signals.primes, "Skip rest sounds nothing, and the count-in opens on the second before its 3")
        run(flow, 1)
        assertEquals(listOf(Event.Tick), signals.tones)
        run(flow, GetReady.countInSeconds - 1)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aRunsRestResumedInItsLastSecondsIsPrimedOnceASecondBeforeItsFirstTick() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        assertTrue(flow.restStartsTheNextSet, "the premise")
        run(flow) { flow.restClock.remaining == 2 }
        flow.toggleBlockPause()
        advance(120)
        signals.primes = 0
        signals.events.clear()

        flow.toggleBlockPause()
        assertEquals(BlockPause.reentrySeconds, flow.restClock.remaining,
                     "the premise: a resumed rest picks up at no less than the count-in")
        assertEquals(1, signals.primes, "two minutes paused let the engine go cold")
        run(flow, 1)
        assertEquals(listOf(Event.Tick), signals.tones)
        run(flow, BlockPause.reentrySeconds - 1)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aRunsRestResumedWithTimeLeftIsPrimedOnlyAtItsFour() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        assertTrue(flow.restStartsTheNextSet, "the premise")
        run(flow) { flow.restClock.remaining == 30 }
        flow.toggleBlockPause()
        advance(120)
        signals.primes = 0

        flow.toggleBlockPause()
        assertEquals(30, flow.restClock.remaining, "the premise: a rest with time left keeps it")
        assertEquals(0, signals.primes, "thirty seconds out, a prime would be cold again by the 3")
        run(flow) { flow.restClock.remaining == BlockPause.reentrySeconds }
        assertEquals(1, signals.primes)
        run(flow, BlockPause.reentrySeconds)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun nothingIsPrimedWithTheSoundsOff() {
        val (flow, store) = holdFlow(Pattern.coreAntiExt)
        store.update { it.copy(settings = it.settings.copy(soundsEnabled = false)) }
        signals.primes = 0
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        assertTrue(flow.restStartsTheNextSet, "the premise")
        flow.skipRest()
        assertTrue(flow.holdCountingIn, "the premise")
        run(flow, GetReady.countInSeconds)
        assertEquals(0, signals.primes, "the haptic is half of a signal the switch has turned off")
    }

    @Test
    fun readingTheTechniqueFreezesOnlyTheRestThatStartsASet() {
        val (flow, store) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15)
        run(flow, 20)
        flow.freezeRestForTechnique()
        assertFalse(flow.restClock.isRunning)
        assertNull(tile.updates.lastOrNull()?.restEndDate)
        assertEquals(clock.plusSeconds(40), store.pendingWorkout?.restEndDate,
                     "a frozen rest is written as the seconds it froze with")
        advance(300)
        flow.tick()
        assertEquals(Phase.Rest(60), flow.phase, "nothing runs out under the sheet")
        flow.resumeRestCountdown()
        assertEquals(clock.plusSeconds(40), flow.restClock.endDate)
    }

    @Test
    fun aRunsRestReadAboutInItsLastSecondsComesBackWithTheWholeCountIn() {
        val (flow, store) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow) { flow.restStartsTheNextSet }
        run(flow) { flow.restClock.remaining == 2 }
        flow.freezeRestForTechnique()
        advance(60)
        signals.primes = 0
        signals.events.clear()

        flow.resumeRestCountdown()
        val end = clock.plusSeconds(BlockPause.reentrySeconds.toLong())
        assertEquals(BlockPause.reentrySeconds, flow.restClock.remaining,
                     "the end of this rest starts a plank: not two seconds after the page closes")
        assertEquals(end, flow.restClock.endDate)
        assertEquals(end, tile.updates.lastOrNull()?.restEndDate, "the lock screen counts to the same moment")
        assertEquals(end, store.pendingWorkout?.restEndDate)
        assertEquals(1, signals.primes, "a minute on the page let the engine go cold")
        run(flow) { flow.phase == Phase.Work }
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones,
                     "the whole 3-2-1, then the go the hold starts on")
        assertTrue(flow.holding)
    }

    @Test
    fun theSheetsFloorStopsAtTheRestsOwnLength() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow) { flow.restStartsTheNextSet }
        // No planned rest is shorter than the count-in, so one is started
        // here: the floor must not stretch a rest past its own length.
        flow.startRest(BlockPause.reentrySeconds - 1)
        run(flow, 1)
        flow.freezeRestForTechnique()
        advance(60)

        flow.resumeRestCountdown()
        assertEquals(BlockPause.reentrySeconds - 1, flow.restClock.remaining)
        assertEquals(clock.plusSeconds((BlockPause.reentrySeconds - 1).toLong()), flow.restClock.endDate)
    }

    @Test
    fun anOrdinaryRestRunsOnUnderTheSheetAndClosingItMovesNothing() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        run(flow) { flow.phase != Phase.Work }
        assertFalse(flow.restStartsTheNextSet, "the premise: this rest hands the screen back and waits")
        run(flow) { flow.restClock.remaining == 2 }
        val end = flow.restClock.endDate
        flow.freezeRestForTechnique()
        assertTrue(flow.restClock.isRunning)

        flow.resumeRestCountdown()
        assertEquals(end, flow.restClock.endDate, "its end starts nothing, so it takes no floor")
    }

    @Test
    fun aPausedRunsRestStaysHeldAndSaysSoUnderTheSheet() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow) { flow.restStartsTheNextSet }
        run(flow) { flow.restClock.remaining == 2 }
        flow.toggleBlockPause()
        assertEquals("Paused", tile.updates.lastOrNull()?.detail?.english, "the premise")
        flow.freezeRestForTechnique()
        assertEquals("Paused", tile.updates.lastOrNull()?.detail?.english,
                     "the lock screen must not promise that a held rest starts by itself")
        advance(60)

        flow.resumeRestCountdown()
        assertTrue(flow.blockPause.isHeld, "the person's own stop outranks the sheet's")
        assertFalse(flow.restClock.isRunning)
        assertNull(tile.updates.lastOrNull()?.restEndDate)
        assertEquals("Paused", tile.updates.lastOrNull()?.detail?.english)
    }
}
