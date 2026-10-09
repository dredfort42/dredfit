//
//  Who keeps the flow's second, and what that costs (workout/WorkoutBeat.kt).
//  Android-only suite: on iOS the beat is the flow screen's timer and a
//  backgrounded app is simply left. Here the ongoing notification keeps the
//  flow — and its signals — going off screen, and every rule of that runs on
//  the test's clock with a fake timer: a beat is one call.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.store.nextSession
import com.dredfit.workout.BeatTimer
import com.dredfit.workout.OngoingWorkout
import com.dredfit.workout.WorkoutBeat
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.WorkoutSessionStore
import com.dredfit.workout.beginWarmup
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.persistProgress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WorkoutBeatTest : WorkoutSessionTestCase() {

    /** The main-looper timer without the looper: `fire` is one second. */
    private class FakeTimer : BeatTimer {
        var beat: (() -> Unit)? = null
        val running: Boolean get() = beat != null
        var starts = 0

        override fun start(beat: () -> Unit) {
            starts += 1
            this.beat = beat
        }

        override fun stop() {
            beat = null
        }
    }

    private val host = HostSpy()
    private val timer = FakeTimer()
    private lateinit var ongoing: OngoingWorkout

    private fun beatOn(accepts: Boolean = true): Pair<WorkoutSession, WorkoutBeat> {
        host.accepts = accepts
        val store = makeStore()
        val tile = OngoingWorkout(host) { clock }.also { ongoing = it }
        val flow = WorkoutSession(session = store.nextSession, store = store, resume = null, settleImmediately = false,
                                  liveActivity = tile, signals = signals, now = { clock })
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

    // MARK: - Who is present

    @Test
    fun withoutTheTileLeavingTheScreenIsLeavingAsOnIOS() {
        val (flow, beat) = beatOn(accepts = false)
        assertTrue(timer.running, "on screen the flow beats")
        beat.screen(visible = false)
        assertFalse(timer.running, "off screen, with no notification, nothing beats — the iOS rule")
        assertTrue(flow.absence.isAway, "and the absence is stamped")
        advance(600)
        beat.screen(visible = true)
        assertTrue(timer.running)
        assertEquals(600, flow.awaySec, "the time away is charged, as on iOS")
    }

    @Test
    fun behindTheTileTheRestsCountdownStillSoundsOnItsSeconds() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        flow.completeSet()
        val rest = flow.phase as Phase.Rest
        signals.events.clear()
        beat.screen(visible = false)
        assertTrue(timer.running, "the notification holds the flow: the beat goes on")
        assertFalse(flow.absence.isAway, "a workout running behind its notification is no absence")
        fire(rest.seconds)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones,
                     "the 3-2-1 and the go, with the app in the background")
        assertEquals(Phase.Work, flow.phase)
        beat.screen(visible = true)
        assertEquals(0, flow.awaySec, "nothing of it is charged to an absence")
    }

    @Test
    fun theTileEndingOffScreenLeavesTheFlowThere() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        beat.screen(visible = false)
        assertTrue(timer.running)
        flow.liveActivity.end()
        fire(1)
        assertFalse(timer.running, "no screen and no notification: the beat stops")
        assertTrue(flow.absence.isAway, "and from here the absence is measured, as iOS measures it")
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
    fun aWarmUpRunningHoldsTheCpu() {
        val (flow, _) = beatOn()
        flow.beginWarmup()
        fire(1)
        assertTrue(host.awake, "the warm-up's transitions and positions run by themselves")
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
    fun aForgottenWorkoutRetiresTheTileByTheSettlementsRuleAndNotBefore() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        beat.screen(visible = false)
        val hours = WorkoutSessionStore.forgottenAfter.seconds.toInt()
        // Waiting on a set: nothing runs, so a second passes per beat.
        fire(hours - 1)
        assertTrue(ongoing.isShown, "a second short of twelve hours")
        fire(1)
        assertEquals(HostSpy.Call.Hide, host.calls.last { it !is HostSpy.Call.Awake },
                     "twelve hours without a write: the settlement would call it forgotten")
        assertFalse(timer.running, "and with neither screen nor notification nothing beats")
        assertTrue(flow.absence.isAway)
    }

    @Test
    fun aWriteMovesTheForgottenWorkoutsClock() {
        val (flow, beat) = beatOn()
        flow.declineWarmup()
        beat.screen(visible = false)
        advance(6 * 3_600)
        flow.persistProgress()
        val hours = WorkoutSessionStore.forgottenAfter.seconds.toInt()
        fire(hours - 1)
        assertTrue(ongoing.isShown,
                   "eighteen hours since the tile went up, but under twelve since the last write")
        fire(1)
        assertFalse(ongoing.isShown)
    }
}
