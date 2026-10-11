//
//  The harness of every workout-flow suite: the spies and helpers that
//  ios/DredfitTests/WorkoutSessionTests.swift declares at its top and its
//  `+X` extensions share. Kotlin cannot add tests through an extension, so
//  each `WorkoutSessionTests+X.swift` is a class of its own
//  (`WorkoutSessionTestX`) on this base, as AppStoreTests+X are on
//  AppStoreTestCase.
//
//  The clock is the test's: a minute passes in a loop, an absence in one
//  assignment, and nothing sleeps.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionProbe
import com.dredfit.core.generateSession
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.workout.ActivityState
import com.dredfit.workout.WorkoutActivityDriving
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSignalling
import com.dredfit.workout.Words
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.startDeclaringHoldTime
import java.time.Instant
import kotlin.test.assertNotNull
import kotlin.test.fail

/** Every tone and announcement the flow would have made, in order. */
class SignalSpy : WorkoutSignalling {
    sealed interface Event {
        data object Tick : Event
        data object Go : Event
        data object SwitchSides : Event
        data object Done : Event
        data object WorkoutDone : Event
        data object Milestone : Event
        /** Compared by the English text — what `String(localized:)` gives
         *  the iOS suite, which runs in English. */
        data class Announce(val message: String) : Event
    }

    val events = mutableListOf<Event>()

    /** The tones alone — announcements are the screen reader's. */
    val tones: List<Event> get() = events.filter { it !is Event.Announce }

    /** Haptic primes, counted apart from `events`: a prime makes no tone. */
    var primes = 0

    override fun prime() { primes += 1 }
    override fun primeSounds() {}
    override fun tick(enabled: Boolean) { if (enabled) events += Event.Tick }
    override fun go(enabled: Boolean) { if (enabled) events += Event.Go }
    override fun switchSides(enabled: Boolean) { if (enabled) events += Event.SwitchSides }
    override fun done(enabled: Boolean) { if (enabled) events += Event.Done }
    override fun workoutDone(enabled: Boolean) { if (enabled) events += Event.WorkoutDone }
    override fun milestone(enabled: Boolean) { if (enabled) events += Event.Milestone }
    override fun announce(message: Words) { events += Event.Announce(message.english) }
}

/** What the tile would have shown. */
class TileSpy : WorkoutActivityDriving {
    var started: ActivityState? = null
    val updates = mutableListOf<ActivityState>()
    var ended = 0
    override fun start(sessionNumber: Int, state: ActivityState) { started = state }
    override fun update(state: ActivityState) { updates += state }
    override fun end() { ended += 1 }
}

abstract class WorkoutSessionTestCase : AppStoreTestCase() {

    var clock: Instant = Instant.ofEpochSecond(1_900_000_000)
    val signals = SignalSpy()
    val tile = TileSpy()

    /** Swift's `clock += seconds`. */
    fun advance(seconds: Double) {
        clock = clock.plusNanos((seconds * 1e9).toLong())
    }

    fun advance(seconds: Int) {
        clock = clock.plusSeconds(seconds.toLong())
    }

    /** A flow already on screen, on `session` or on the one the store hands
     *  out next. */
    fun makeFlow(store: AppStore, session: Session? = null, resume: WorkoutSnapshot? = null,
                 settle: Boolean = false): WorkoutSession {
        val flow = WorkoutSession(session = session ?: store.nextSession, store = store, resume = resume,
                                  settleImmediately = settle, liveActivity = tile, signals = signals,
                                  now = { clock })
        flow.appear()
        return flow
    }

    /** `seconds` pass one tick at a time, the way the screen's timer runs them. */
    fun run(flow: WorkoutSession, seconds: Int) {
        repeat(seconds) {
            advance(1)
            flow.tick()
        }
    }

    /** Ticks until `done` holds; fails if it never does. */
    fun run(flow: WorkoutSession, limit: Int = 3_600, done: () -> Boolean): Int {
        var seconds = 0
        while (!done()) {
            if (seconds >= limit) fail("the flow never got there in $limit s")
            advance(1)
            flow.tick()
            seconds += 1
        }
        return seconds
    }

    /** Session 2 carries the two hold movements: `coreAntiExt` on both sides
     *  at once and `coreRot` per side, three sets of 15 s each. */
    fun holdSession(): Session {
        val state = EngineState.initial.also { it.counter = 1 }
        return Engine.generateSession(state)
    }

    fun index(pattern: Pattern, flow: WorkoutSession): Int {
        val i = flow.exercises.indexOfFirst { it.pattern == pattern }
        if (i < 0) fail("${pattern.rawValue} must be in session ${flow.session.sessionNumber}")
        return i
    }

    /** A hold movement of `session` (session 2 by default) on screen, the
     *  warm-up declined — `WorkoutSessionTests+Holds.swift`'s helper, here
     *  because every hold suite shares it. */
    fun holdFlow(pattern: Pattern, session: Session? = null): Pair<WorkoutSession, AppStore> {
        val store = makeStore()
        val flow = makeFlow(store, session ?: holdSession())
        flow.declineWarmup()
        flow.exIndex = index(pattern, flow)
        signals.events.clear()
        return flow to store
    }

    /** A set at the plan is written as nothing at all, so a test that has to
     *  see what the clock ran declares a time off the plan first. */
    fun declare(seconds: Int, flow: WorkoutSession) {
        flow.startDeclaringHoldTime()
        flow.adjustValue = seconds
        flow.commitSetEdit()
    }

    /** Session 1 with a probe on its first movement: one set of the next
     *  variation in place of the last working set. */
    fun probeSession(): Session {
        val base = Engine.generateSession(EngineState.initial)
        val probe = SessionProbe(variation = 2, name = "Probe move", unit = LoadUnit.reps, load = 6, perSide = false)
        val first = assertNotNull(base.exercises.firstOrNull())
        return base.copy(exercises = listOf(first.copy(probe = probe, sets = 2)) + base.exercises.drop(1))
    }
}
