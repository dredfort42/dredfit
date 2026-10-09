//
//  The ongoing notification's rules: what the tile shows for each state the
//  flow sends (workout/RestLiveActivity.kt — the rules of iOS's
//  RestLiveActivity.swift) and the controller's start / update / end order
//  (workout/LiveActivityController.kt). Android-only suite: on iOS the tile
//  is drawn by the widget extension and no test reads it.
//

package com.dredfit

import com.dredfit.store.nextSession
import com.dredfit.workout.ActivityState
import com.dredfit.workout.OngoingContent
import com.dredfit.workout.OngoingHost
import com.dredfit.workout.OngoingWorkout
import com.dredfit.workout.Words
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.finishNow
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** What the device half was asked to do, in order. */
class HostSpy : OngoingHost {
    sealed interface Call {
        data class Show(val content: OngoingContent) : Call
        data object Hide : Call
        data class Awake(val awake: Boolean) : Call
    }

    val calls = mutableListOf<Call>()
    /** The system refusing the service, when false. */
    var accepts = true
    override var isUp: Boolean = false
        private set

    val shown: List<OngoingContent> get() = calls.filterIsInstance<Call.Show>().map { it.content }
    /** The lock as the device would hold it: whatever the last call said —
     *  `hide` releases nothing by itself. */
    val awake: Boolean get() = calls.filterIsInstance<Call.Awake>().lastOrNull()?.awake == true

    override fun show(content: OngoingContent) {
        calls += Call.Show(content)
        if (!isUp) isUp = accepts
    }

    override fun hide() {
        calls += Call.Hide
        isUp = false
    }

    override fun keepAwake(awake: Boolean) {
        calls += Call.Awake(awake)
    }

    /** The system stopped the service on its own (Task Manager's Stop). */
    fun stoppedBySystem() {
        isUp = false
    }
}

class OngoingNotificationTest : WorkoutSessionTestCase() {

    private val now = Instant.ofEpochSecond(1_900_000_000)
    private val title = Words.of("Workout rating")
    private val detail = Words.of("Next up")

    // MARK: - What the tile shows

    @Test
    fun aRestCountsDownToItsEnd() {
        val end = now.plusSeconds(90)
        val content = OngoingContent.of(ActivityState(ActivityState.Phase.rest, title, detail, end), now)
        assertEquals(OngoingContent(title, detail, end), content, "title bold, detail small, the countdown to the end")
    }

    @Test
    fun aHoldCountsDownToo() {
        val end = now.plusSeconds(30)
        val content = OngoingContent.of(ActivityState(ActivityState.Phase.hold, title, detail, end), now)
        assertEquals(end, content.countdownTo, "the phase that asks you to put the phone down must show its clock")
    }

    @Test
    fun workShowsNoCountdownEvenWithADate() {
        val content = OngoingContent.of(ActivityState(ActivityState.Phase.work, title, detail, now.plusSeconds(30)), now)
        assertNull(content.countdownTo, "a set is counted by the person, not by the tile")
    }

    @Test
    fun anEndAlreadyPastDrawsNoCountdown() {
        val content = OngoingContent.of(ActivityState(ActivityState.Phase.rest, title, detail, now), now)
        assertNull(content.countdownTo, "a system chronometer would count on below zero")
        val paused = OngoingContent.of(ActivityState(ActivityState.Phase.rest, title, Words.of("Paused"), null), now)
        assertNull(paused.countdownTo)
        assertEquals(Words.of("Paused"), paused.detail)
    }

    @Test
    fun theFlowsOwnStatesReadAsOnIOS() {
        val host = HostSpy()
        val flow = flowOn(host)
        assertEquals(OngoingContent(Words.of("WARM-UP"), null, null), host.shown.single(),
                     "the warm-up offer: the block's name, nothing to count")
        flow.declineWarmup()
        val work = host.shown.last()
        assertNull(work.countdownTo)
        assertEquals("set 1 of ${flow.totalSets}", assertNotNull(work.detail).english)
        flow.completeSet()
        val rest = host.shown.last()
        assertEquals("Next up", assertNotNull(rest.detail).english)
        assertEquals(flow.restClock.endDate, rest.countdownTo, "the rest's own end date, to the second")
    }

    // MARK: - The controller

    @Test
    fun anUpdateOrAnEndWithNoTileUpDoesNothing() {
        val host = HostSpy()
        val tile = OngoingWorkout(host) { now }
        val state = ActivityState(ActivityState.Phase.work, title, null, null)
        tile.update(state)
        tile.end()
        assertTrue(host.calls.isEmpty(), "nothing was started: ${host.calls}")
        tile.start(sessionNumber = 3, state = state)
        tile.end()
        tile.update(state)
        tile.end()
        assertEquals(listOf(HostSpy.Call.Show(OngoingContent(title, null, null)), HostSpy.Call.Hide), host.calls,
                     "ended once; a late update from a closing sheet must not bring it back")
    }

    @Test
    fun theCpuIsHeldOnlyWhileTheTileIsUpAndOnlyOnAChange() {
        val host = HostSpy()
        val tile = OngoingWorkout(host) { now }
        tile.keepAwake(true)
        assertTrue(host.calls.isEmpty(), "no tile, no lock")
        tile.start(sessionNumber = 1, state = ActivityState(ActivityState.Phase.work, title, null, null))
        tile.keepAwake(true)
        tile.keepAwake(true)
        tile.keepAwake(false)
        tile.keepAwake(false)
        assertEquals(listOf(true, false), host.calls.filterIsInstance<HostSpy.Call.Awake>().map { it.awake })
        tile.keepAwake(true)
        tile.end()
        assertFalse(host.awake, "the end releases what the tile held")
    }

    @Test
    fun aTileEndingDuringACountdownReleasesTheCpuBeforeTheServiceGoes() {
        val host = HostSpy()
        val tile = OngoingWorkout(host) { now }
        tile.start(sessionNumber = 1, state = ActivityState(ActivityState.Phase.rest, title, detail, now.plusSeconds(60)))
        tile.keepAwake(true)
        tile.end()
        assertEquals(listOf(HostSpy.Call.Awake(true), HostSpy.Call.Awake(false), HostSpy.Call.Hide),
                     host.calls.drop(1), "no beat comes after the end to let the lock go")
        tile.keepAwake(true)
        assertFalse(host.awake, "and nothing takes it back once the tile is down")
    }

    @Test
    fun aCountdownLeftPastItsEndIsRedrawnWithoutItOnce() {
        val host = HostSpy()
        var t = now
        val tile = OngoingWorkout(host) { t }
        tile.start(sessionNumber = 1, state = ActivityState(ActivityState.Phase.rest, title, detail, now.plusSeconds(60)))
        t = now.plusSeconds(59)
        tile.refresh()
        assertEquals(1, host.shown.size, "still ahead: the system's chronometer counts it")
        t = now.plusSeconds(61)
        tile.refresh()
        tile.refresh()
        assertEquals(listOf(now.plusSeconds(60), null), host.shown.map { it.countdownTo },
                     "past its end with no update: drawn once without it, never below zero")
    }

    @Test
    fun aRefusedServiceIsNoTile() {
        val host = HostSpy().also { it.accepts = false }
        val tile = OngoingWorkout(host) { now }
        tile.start(sessionNumber = 1, state = ActivityState(ActivityState.Phase.work, title, null, null))
        assertFalse(tile.isShown, "the system said no: the flow must fall back to the iOS rule")
        tile.keepAwake(true)
        assertTrue(host.calls.none { it is HostSpy.Call.Awake }, "and holds no CPU for a tile nobody sees")
    }

    @Test
    fun aServiceTheSystemStoppedIsNoTileEither() {
        val host = HostSpy()
        val tile = OngoingWorkout(host) { now }
        tile.start(sessionNumber = 1, state = ActivityState(ActivityState.Phase.work, title, null, null))
        assertTrue(tile.isShown)
        host.stoppedBySystem()
        assertFalse(tile.isShown)
    }

    @Test
    fun finishNowEndsTheTileAndTheRatingNeverStartsOne() {
        val host = HostSpy()
        val flow = flowOn(host)
        flow.declineWarmup()
        flow.finishNow()
        assertEquals(HostSpy.Call.Hide, host.calls.last(), "the rating has nothing for the tile to describe")
        val resumed = HostSpy()
        flowOn(resumed, settle = true)
        assertTrue(resumed.calls.isEmpty(), "opened straight on the rating: ${resumed.calls}")
    }

    private fun flowOn(host: OngoingHost, settle: Boolean = false): WorkoutSession {
        val store = makeStore()
        val flow = WorkoutSession(session = store.nextSession, store = store, resume = null, settleImmediately = settle,
                                  liveActivity = OngoingWorkout(host) { clock }, signals = signals, now = { clock })
        flow.appear()
        return flow
    }
}
