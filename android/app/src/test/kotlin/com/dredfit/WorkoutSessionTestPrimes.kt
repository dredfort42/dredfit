//
//  Port of ios/DredfitTests/WorkoutSessionTests+Primes.swift: the haptic
//  prime before every 3-2-1.
//
//  About a second before its first tick, never with the sounds off and never
//  for a countdown that sounds no 3-2-1. A countdown passing its four is
//  primed once, by that tick. One that starts on its four is primed where it
//  starts, and one its ticks come back to — after a sheet, a pause or time
//  away — with its next signal less than a second away is primed where they
//  come back. Behind the exit alert, where the ticks are held back and the
//  clock is not, every beat that finds it on its four or inside its 3-2-1
//  primes it again.
//
//  Every Swift test is ported.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.setSounds
import com.dredfit.workout.BlockPause
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.beginCooldown
import com.dredfit.workout.beginWarmup
import com.dredfit.workout.completeSet
import com.dredfit.workout.countIn
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.enterStage
import com.dredfit.workout.freezeForPositionTechnique
import com.dredfit.workout.freezeRestForTechnique
import com.dredfit.workout.restStartsTheNextSet
import com.dredfit.workout.resumePositionCountdown
import com.dredfit.workout.resumeRestCountdown
import com.dredfit.workout.sceneCameBack
import com.dredfit.workout.sceneLeft
import com.dredfit.workout.startHold
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.toggleBlockPause
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WorkoutSessionTestPrimes : WorkoutSessionTestCase() {

    /** The second a countdown shows one second before its 3. */
    private val primedAt: Int get() = WorkoutSession.countdownSignalSeconds + 1

    /** The warm-up, standing on the first stage of its first position. */
    private fun warmupOnItsFirstPosition(): WorkoutSession {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        return flow
    }

    /** The warm-up, at the start of the first transition no tap opened. */
    private fun warmupOnItsSecondTransition(): WorkoutSession {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow) { flow.warmup.index == 1 }
        return flow
    }

    /** The warm-up, at the start of the first half of a split move. */
    private fun warmupOnASplitMove(): WorkoutSession {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow) { flow.warmup.stage == GuidedStage.firstHalf }
        return flow
    }

    /** An ordinary rest, left for the background with half a minute on it. */
    private fun restLeftAtThirty(store: AppStore): WorkoutSession {
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        run(flow) { flow.restClock.remaining == 30 }
        flow.sceneLeft()
        return flow
    }

    // MARK: - The way back into a paused position

    @Test
    fun theWayBackInIsPrimedOnceASecondBeforeItsFirstTick() {
        val flow = warmupOnItsFirstPosition()
        run(flow, 3)
        flow.toggleBlockPause()
        advance(120)
        signals.primes = 0
        signals.events.clear()

        flow.toggleBlockPause()
        assertTrue(flow.blockPause.isReentering, "the premise")
        assertEquals(1, signals.primes, "the way back in starts on its four, after a pause of any length")
        run(flow, BlockPause.reentrySeconds)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aLongerWayBackInIsPrimedAtItsFourNotAtItsStart() {
        val flow = warmupOnItsFirstPosition()
        flow.toggleBlockPause()
        signals.primes = 0
        // No path opens one: the way back in is the count-in's four seconds.
        // A longer one must not lose its prime to its length.
        flow.blockPause.beginReentry(seconds = primedAt + 3, now = clock)
        run(flow) { flow.blockPause.reentryRemaining == primedAt + 1 }
        assertEquals(0, signals.primes, "primed at its start, it would be cold by the 3")
        run(flow, 1)
        assertEquals(1, signals.primes)
        run(flow) { !flow.blockPause.isPaused }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    // MARK: - The guided blocks' own clocks

    @Test
    fun aStartTapOpensTheTransitionOnItsFourPrimed() {
        val flow = makeFlow(makeStore())
        signals.primes = 0
        flow.beginWarmup()
        assertEquals(GetReady.countInSeconds, flow.warmup.clock.remaining, "the premise")
        assertEquals(1, signals.primes, "no tick reports the second a countdown starts on")
        signals.events.clear()
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aTransitionNoTapOpenedIsPrimedAtItsFourAndOnlyThere() {
        val flow = warmupOnItsSecondTransition()
        assertEquals(GuidedStage.getReady, flow.warmup.stage, "the premise")
        signals.primes = 0
        run(flow) { flow.warmup.clock.remaining == primedAt + 1 }
        assertEquals(0, signals.primes, "opened on a done eight seconds out or more, it is cold by the 3")
        run(flow, 1)
        assertEquals(1, signals.primes)
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun imReadyCutsTheTransitionToItsFourPrimed() {
        val flow = warmupOnItsSecondTransition()
        run(flow) { flow.warmup.clock.remaining == primedAt + 2 }
        signals.primes = 0
        signals.events.clear()

        flow.countIn(GuidedBlock.warmup)
        assertEquals(GetReady.countInSeconds, flow.warmup.clock.remaining, "the premise")
        assertEquals(1, signals.primes, "no tick reports the second a countdown starts on")
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aPositionIsPrimedAtItsFourAndOnlyThere() {
        val flow = warmupOnItsFirstPosition()
        val stage = flow.warmup.stage
        signals.primes = 0
        run(flow) { flow.warmup.clock.remaining == primedAt + 1 }
        assertEquals(0, signals.primes, "opened on a go fifteen seconds out or more, it is cold by the 3")
        run(flow, 1)
        assertEquals(1, signals.primes)
        run(flow) { flow.warmup.stage != stage }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun theSwitchPauseIsNeverPrimed() {
        val flow = warmupOnASplitMove()
        run(flow) { flow.warmup.clock.remaining == 1 }
        signals.primes = 0
        run(flow) { flow.warmup.stage == GuidedStage.secondHalf }
        assertEquals(0, signals.primes, "the switch pause sounds no 3-2-1: its ticks would bury the switch tone")
    }

    @Test
    fun aLongerSwitchPauseIsNeverPrimedEither() {
        val flow = warmupOnASplitMove()
        // No split move pauses longer than the count-in; one that did would
        // pass its four with nothing to prime for.
        flow.enterStage(index = flow.warmup.index, stage = GuidedStage.switchPause, remaining = primedAt + 3,
                        block = GuidedBlock.warmup)
        signals.primes = 0
        run(flow) { flow.warmup.stage == GuidedStage.secondHalf }
        assertEquals(0, signals.primes)
    }

    // MARK: - The hold's own clock

    @Test
    fun aHoldsOwnLastSecondsArePrimedAtItsFour() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        run(flow) { flow.holding }
        signals.primes = 0
        signals.events.clear()
        run(flow) { flow.holdClock.remaining == primedAt + 1 }
        assertEquals(0, signals.primes, "the go a whole set earlier is the last impulse before it")
        run(flow, 1)
        assertEquals(1, signals.primes)
        run(flow) { !flow.holding }
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Done), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun theSecondSideIsPrimedAtItsOwnFour() {
        val (flow, _) = holdFlow(Pattern.coreRot)
        flow.startHold()
        run(flow) { flow.holdSwitchPausing }
        signals.primes = 0
        run(flow) { flow.holding }
        assertEquals(0, signals.primes, "the switch pause sounds no 3-2-1")
        run(flow) { flow.holdClock.remaining == primedAt + 1 }
        assertEquals(0, signals.primes)
        run(flow, 1)
        assertEquals(1, signals.primes)
        run(flow) { !flow.holding }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    // MARK: - A countdown that stood still

    @Test
    fun aRestReadAboutOnItsFourIsPrimedWhenTheSheetCloses() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow) { flow.restStartsTheNextSet }
        run(flow) { flow.restClock.remaining == primedAt }
        flow.freezeRestForTechnique()
        advance(120)
        signals.primes = 0
        signals.events.clear()

        flow.resumeRestCountdown()
        assertEquals(1, signals.primes, "two minutes on the technique page let the engine go cold")
        run(flow) { flow.phase == Phase.Work }
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aRestReadAboutWithTimeLeftIsPrimedOnlyAtItsFour() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow) { flow.restStartsTheNextSet }
        run(flow) { flow.restClock.remaining == 30 }
        flow.freezeRestForTechnique()
        advance(120)
        signals.primes = 0

        flow.resumeRestCountdown()
        assertEquals(0, signals.primes, "thirty seconds out, a prime would be cold again by the 3")
        run(flow) { flow.restClock.remaining == primedAt }
        assertEquals(1, signals.primes)
        run(flow) { flow.phase == Phase.Work }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aTransitionReadAboutInItsLastSecondsIsPrimedWhenTheSheetCloses() {
        val flow = warmupOnItsSecondTransition()
        run(flow) { flow.warmup.clock.remaining == 2 }
        flow.freezeForPositionTechnique()
        advance(120)
        signals.primes = 0
        signals.events.clear()

        flow.resumePositionCountdown()
        assertEquals(1, signals.primes)
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        assertEquals(listOf(Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun theWayBackInReadAboutIsPrimedWhenTheSheetCloses() {
        val flow = warmupOnItsFirstPosition()
        flow.toggleBlockPause()
        flow.toggleBlockPause()
        run(flow, 1)
        assertTrue(flow.blockPause.isReentering, "the premise")
        flow.freezeForPositionTechnique()
        advance(120)
        signals.primes = 0
        signals.events.clear()

        flow.resumePositionCountdown()
        assertEquals(1, signals.primes)
        run(flow) { !flow.blockPause.isPaused }
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aHeldBlockReadAboutPrimesNothing() {
        val flow = warmupOnItsFirstPosition()
        flow.toggleBlockPause()
        flow.freezeForPositionTechnique()
        advance(120)
        signals.primes = 0

        flow.resumePositionCountdown()
        assertTrue(flow.blockPause.isHeld, "the premise: the person's pause outranks the sheet")
        assertEquals(0, signals.primes, "a held block counts nothing down")
    }

    @Test
    fun aSwitchPauseReadAboutPrimesNothing() {
        val flow = warmupOnASplitMove()
        run(flow) { flow.warmup.stage == GuidedStage.switchPause }
        flow.freezeForPositionTechnique()
        advance(120)
        signals.primes = 0

        flow.resumePositionCountdown()
        assertEquals(0, signals.primes, "the switch pause sounds no 3-2-1")
    }

    @Test
    fun aTransitionPausedInItsLastSecondsIsPrimedWhenItResumes() {
        val flow = warmupOnItsSecondTransition()
        run(flow) { flow.warmup.clock.remaining == 2 }
        flow.toggleBlockPause()
        advance(120)
        signals.primes = 0
        signals.events.clear()

        flow.toggleBlockPause()
        assertFalse(flow.blockPause.isPaused, "the premise: a transition is its own way back in")
        assertEquals(1, signals.primes)
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        assertEquals(Event.Go, signals.tones.lastOrNull())
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aTransitionPausedASecondAboveItsFourIsPrimedOnlyThere() {
        val flow = warmupOnItsSecondTransition()
        run(flow) { flow.warmup.clock.remaining == primedAt + 1 }
        flow.toggleBlockPause()
        advance(120)
        signals.primes = 0

        flow.toggleBlockPause()
        assertEquals(0, signals.primes, "its four is still ahead, and its tick primes it")
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aCoolDownTransitionPausedInItsLastSecondsIsPrimedWhenItResumes() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow) { flow.cooldown.clock.remaining == 2 }
        flow.toggleBlockPause()
        advance(120)
        signals.primes = 0

        flow.toggleBlockPause()
        assertFalse(flow.blockPause.isPaused, "the premise: a transition is its own way back in")
        assertEquals(1, signals.primes)
    }

    // MARK: - Back from the background

    @Test
    fun aReturnIntoTheLastSecondsOfARestIsPrimed() {
        val flow = restLeftAtThirty(makeStore())
        advance(28)
        signals.primes = 0
        signals.events.clear()

        flow.sceneCameBack()
        assertEquals(1, signals.primes, "the time away let the engine go cold, and the next tick is inside the 3-2-1")
        flow.tick()   // the next tick, a return between two of them
        run(flow) { flow.phase == Phase.Work }
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun ticksHeldBackPastTheFourArePrimedBeforeTheyResume() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.completeSet()
        run(flow) { flow.restClock.remaining == 10 }
        // Behind the exit alert no tick runs, while the rest runs on; the
        // timer's beat there asks for the prime instead.
        advance(10 - primedAt)
        signals.primes = 0
        signals.events.clear()

        flow.primeComingBack()
        assertEquals(1, signals.primes, "on its four, and the first tick back may already be past it")
        advance(0.9)
        flow.tick()
        assertEquals(listOf<Event>(Event.Tick), signals.tones, "the timer kept its own beat: its next tick lands on the 3")
        run(flow) { flow.phase == Phase.Work }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aReturnASecondAboveTheFourIsPrimedOnlyByItsTick() {
        val flow = restLeftAtThirty(makeStore())
        advance(30 - primedAt - 1)
        signals.primes = 0

        flow.sceneCameBack()
        assertEquals(0, signals.primes, "its four is still ahead, and its tick primes it")
        run(flow) { flow.restClock.remaining == primedAt }
        assertEquals(1, signals.primes)
        run(flow) { flow.phase == Phase.Work }
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aGlanceAtControlCenterPrimesNothing() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.completeSet()
        run(flow) { flow.restClock.remaining == primedAt - 1 }
        signals.primes = 0
        // Control Center turns the scene inactive and active again without
        // it ever leaving: the rest went on ticking, and its ticks primed it.
        flow.sceneCameBack()
        assertEquals(0, signals.primes)
    }

    @Test
    fun aReturnIntoAHoldsLastSecondsIsPrimed() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        run(flow) { flow.holding }
        run(flow) { flow.holdClock.remaining == 10 }
        flow.sceneLeft()
        advance(8)
        signals.primes = 0

        flow.sceneCameBack()
        assertEquals(1, signals.primes)
    }

    @Test
    fun aReturnIntoACountInIsPrimed() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        flow.sceneLeft()
        advance(2)
        signals.primes = 0

        flow.sceneCameBack()
        assertEquals(1, signals.primes)
    }

    @Test
    fun aReturnAfterACountInRanOutPrimesItOnceWhenItStartsOver() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        flow.sceneLeft()
        advance(30)
        signals.primes = 0

        flow.sceneCameBack()
        assertEquals(0, signals.primes, "it ran out unheard: none of its 3-2-1 is left")
        flow.tick()
        assertTrue(flow.holdCountingIn, "the premise: a go nobody heard starts it over")
        assertEquals(1, signals.primes)
        run(flow, GetReady.countInSeconds)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aReturnWithTheSoundsOffPrimesNothing() {
        val store = makeStore()
        store.setSounds(false)
        val flow = restLeftAtThirty(store)
        advance(28)

        flow.sceneCameBack()
        assertEquals(0, signals.primes, "the haptic is half of a signal the switch has turned off")
    }
}
