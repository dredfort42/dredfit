//
//  Who keeps the flow's second, and what that costs (workout/WorkoutBeat.kt).
//  Android-only suite: on iOS the beat is the flow screen's timer and a
//  backgrounded app runs none. Here the ongoing notification keeps the beat
//  going off screen for the countdown's own seconds, while the accounting —
//  the time away, what an absence drops or freezes — stays iOS's. Every rule
//  runs on the test's clock with a fake timer: a beat is one call.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.store.nextSession
import com.dredfit.workout.BeatTimer
import com.dredfit.workout.Countdown
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.OngoingWorkout
import com.dredfit.workout.WorkoutBeat
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.WorkoutSessionStore
import com.dredfit.workout.beginWarmup
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.finishNow
import com.dredfit.workout.persistProgress
import com.dredfit.workout.restStartsTheNextSet
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.toggleBlockPause
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutBeatTest : WorkoutSessionTestCase() {

    /** The main-looper timer without the looper: `fire` is one second. */
    private class FakeTimer : BeatTimer {
        var beat: (() -> Unit)? = null
        val running: Boolean get() = beat != null

        override fun start(beat: () -> Unit) {
            this.beat = beat
        }

        override fun stop() {
            beat = null
        }
    }

    private val host = HostSpy()
    private val timer = FakeTimer()
    private lateinit var ongoing: OngoingWorkout

    private fun beatOn(accepts: Boolean = true, session: Session? = null): Pair<WorkoutSession, WorkoutBeat> {
        host.accepts = accepts
        val store = makeStore()
        val tile = OngoingWorkout(host) { clock }.also { ongoing = it }
        val flow = WorkoutSession(session = session ?: store.nextSession, store = store, resume = null,
                                  settleImmediately = false, liveActivity = tile, signals = signals, now = { clock })
        val beat = WorkoutBeat(flow, tile, timer) { change -> flow.change() }
        beat.screen(visible = true)
        flow.appear()
        return flow to beat
    }

    /** `seconds` beats of the timer, a second of the clock each. */
    private fun fire(seconds: Int) {
        repeat(seconds) {
            advance(1)
            checkNotNull(timer.beat) { "the beat is not running" }()
        }
    }

    /** Session 2's both-sides hold, its run begun and on the rest that
     *  starts its next set by itself. */
    private fun onTheRunsRest(): Pair<WorkoutSession, WorkoutBeat> {
        val (flow, beat) = beatOn(session = holdSession())
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreAntiExt, flow)
        flow.startHoldExercise()
        var guard = 0
        while (flow.phase !is Phase.Rest) {
            fire(1)
            check(++guard < 600) { "the run never reached its rest" }
        }
        assertTrue(flow.restStartsTheNextSet, "the premise: a rest that starts the next set")
        return flow to beat
    }

    // MARK: - Leaving is leaving, as on iOS

    @Test
    fun withoutTheTileLeavingStopsTheBeatAndIsAnAbsence() {
        val (flow, beat) = beatOn(accepts = false)
        assertTrue(timer.running, "on screen the flow beats")
        beat.screen(visible = false)
        assertFalse(timer.running, "off screen, with no notification, nothing beats — the iOS rule")
        assertTrue(flow.absence.isAway)
        advance(600)
        beat.screen(visible = true)
        assertTrue(timer.running)
        assertEquals(600, flow.awaySec)
    }

    @Test
    fun behindTheTileLeavingIsStillAnAbsence() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        beat.screen(visible = false)
        assertTrue(timer.running, "the notification keeps the beat")
        assertTrue(flow.absence.isAway, "but the person left, and iOS counts that")
    }

    @Test
    fun aRestThatEndsWhileAwaySoundsItsCountStandsAtItsEndAndAddsNoAwayTime() {
        val (flow, beat) = beatOn()
        val started = clock
        flow.declineWarmup()
        flow.completeSet()
        val rest = flow.phase as Phase.Rest
        signals.events.clear()
        beat.screen(visible = false)
        fire(rest.seconds + 5)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick), signals.tones,
                     "the 3-2-1 sounds behind the notification; the go waits for the person, as on iOS")
        assertEquals(rest, flow.phase, "the rest stands at its end until somebody is back")
        assertNull(host.shown.last().countdownTo, "and the tile drops a countdown that would run below zero")
        advance(600)
        beat.screen(visible = true)
        assertEquals(605, flow.awaySec, "everything past the rest's end is time away — iOS's rule")
        fire(1)
        assertEquals(Phase.Work, flow.phase, "the first tick back hands over the set")
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        val record = assertNotNull(flow.store.records.lastOrNull())
        assertEquals(Countdown.seconds(started, clock).toInt() - 605, record.durationSec,
                     "the workout's duration leaves the time away out")
    }

    @Test
    fun anAbsencePastTheThresholdDropsTheHandsFreeRunAsOnIOS() {
        val (flow, beat) = onTheRunsRest()
        val rest = flow.phase as Phase.Rest
        beat.screen(visible = false)
        fire(rest.seconds + 10)
        assertEquals(rest, flow.phase)
        beat.screen(visible = true)
        fire(1)
        assertFalse(flow.holdAutoRun, "ten seconds late: nobody was there for the go, so the run is dropped")
    }

    @Test
    fun theTileEndingOffScreenStopsTheBeat() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        beat.screen(visible = false)
        assertTrue(timer.running)
        flow.liveActivity.end()
        fire(1)
        assertFalse(timer.running, "no screen and no notification: nothing to beat for")
    }

    // MARK: - The CPU

    @Test
    fun theCpuIsHeldWhileACountdownRunsAndNotWhileTheFlowWaitsForATap() {
        val (flow, _) = beatOn()
        flow.declineWarmup()
        fire(1)
        assertFalse(host.awake, "a set waits for Done — only a tap moves it, and a tap comes with the screen on")
        flow.completeSet()
        fire(1)
        assertTrue(host.awake, "a rest runs: its 3-2-1 has to land with the screen off")
        val rest = flow.phase as Phase.Rest
        fire(rest.seconds)
        assertEquals(Phase.Work, flow.phase)
        assertFalse(host.awake, "released the second the rest handed over the set")
    }

    @Test
    fun offScreenARestHoldsTheCpuUntilItStandsAtItsEnd() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        flow.completeSet()
        val rest = flow.phase as Phase.Rest
        beat.screen(visible = false)
        fire(1)
        assertTrue(host.awake, "screen off, the count still has to land on its seconds")
        fire(rest.seconds)
        assertFalse(host.awake, "standing at its end, nothing more happens until somebody is back")
    }

    @Test
    fun aHoldsCountInAndTheHoldItselfHoldTheCpuOffScreen() {
        val (flow, beat) = beatOn(session = holdSession())
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreAntiExt, flow)
        flow.startHoldExercise()
        beat.screen(visible = false)
        fire(1)
        assertTrue(flow.holdCountingIn)
        assertTrue(host.awake, "the count-in")
        // On screen for the go — away, the count-in would stand at its end.
        beat.screen(visible = true)
        var guard = 0
        while (!flow.holding) {
            fire(1)
            check(++guard < 60) { "the hold never started" }
        }
        beat.screen(visible = false)
        fire(1)
        assertTrue(host.awake, "the hold")
    }

    @Test
    fun aWarmUpRunningHoldsTheCpu() {
        val (flow, _) = beatOn()
        flow.beginWarmup()
        fire(1)
        assertTrue(host.awake, "the warm-up's transitions and positions run by themselves")
    }

    @Test
    fun aHeldBlockLetsTheCpuGoAndItsWayBackInTakesItAgain() {
        val (flow, _) = beatOn()
        flow.beginWarmup()
        // Into a position: a frozen transition is its own way back in.
        var guard = 0
        while (flow.warmup.stage == GuidedStage.getReady) {
            fire(1)
            check(++guard < 60) { "the warm-up never left its first transition" }
        }
        flow.toggleBlockPause()
        fire(1)
        assertTrue(flow.blockPause.isHeld)
        assertFalse(host.awake, "a held block waits for Resume")
        flow.toggleBlockPause()
        fire(1)
        assertTrue(flow.blockPause.isReentering)
        assertTrue(host.awake, "the way back in counts")
    }

    @Test
    fun behindTheExitQuestionNothingIsHeld() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        flow.completeSet()
        fire(1)
        assertTrue(host.awake)
        beat.exitAlertShown = true
        val before = flow.restClock.remaining
        fire(3)
        assertFalse(host.awake, "nothing the clocks drive happens behind the question — no beat needs the CPU")
        assertEquals(before, flow.restClock.remaining, "the clocks were only primed, never ticked")
    }

    @Test
    fun closingStopsTheBeatAndReleasesTheCpu() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        flow.completeSet()
        fire(1)
        assertTrue(host.awake)
        beat.close()
        flow.disappear()
        assertFalse(timer.running)
        assertFalse(host.awake)
        assertEquals(HostSpy.Call.Hide, host.calls.last { it !is HostSpy.Call.Awake })
        beat.screen(visible = true)
        assertFalse(timer.running, "a closed flow never beats again")
    }

    // MARK: - A workout left for hours

    @Test
    fun aWorkoutLeftBehindRetiresTheTileAtTheResumeWindowAndNotBefore() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        beat.screen(visible = false)
        val window = WorkoutSessionStore.resumeWindow.seconds.toInt()
        // Waiting on a set: nothing runs, so a second passes per beat.
        fire(window - 1)
        assertTrue(ongoing.isShown, "a second short of the resume window")
        fire(1)
        assertEquals(HostSpy.Call.Hide, host.calls.last { it !is HostSpy.Call.Awake },
                     "past it Today no longer offers the workout as the same occasion")
        assertFalse(timer.running, "and with neither screen nor notification nothing beats")
    }

    @Test
    fun aWriteMovesTheLeftBehindClock() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        beat.screen(visible = false)
        advance(3_600)
        flow.persistProgress()
        val window = WorkoutSessionStore.resumeWindow.seconds.toInt()
        fire(window - 1)
        assertTrue(ongoing.isShown, "four hours since the tile went up, but under three since the last write")
        fire(1)
        assertFalse(ongoing.isShown)
    }
}
