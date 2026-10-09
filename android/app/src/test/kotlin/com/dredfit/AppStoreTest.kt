//
//  Port of ios/DredfitTests/AppStoreTests.swift: the store's initial state,
//  a workout through to the file, and the guards around `completeWorkout`.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.roundedAwayFromZero
import com.dredfit.store.currentPositions
import com.dredfit.store.doneToday
import com.dredfit.store.nextSession
import com.dredfit.store.totalProgress
import com.dredfit.workout.SetFacts
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class AppStoreTest : AppStoreTestCase() {

    // MARK: - Initial state and persistence

    @Test
    fun freshStoreStartsEmpty() {
        val store = makeStore()
        assertEquals(0, store.totalProgress)
        assertTrue(store.records.isEmpty())
        assertFalse(store.doneToday)
        assertEquals(1, store.nextSession.sessionNumber)
    }

    @Test
    fun completeWorkoutPersistsAndReloads() {
        val store = makeStore()
        val session = store.nextSession
        val skippedPattern = session.exercises[1].pattern
        store.completeWorkout(session = session, result = FeedbackResult.more,
                              overrides = mapOf(session.exercises[0].pattern to 6.0),
                              skipped = setOf(skippedPattern))

        // a separate store on the same file sees the same state
        val reloaded = makeStore()
        assertEquals(1, reloaded.records.size)
        assertEquals(store.engineState, reloaded.engineState)
        assertEquals(FeedbackResult.more, reloaded.records.last().result)
        assertEquals(session.exercises.size, reloaded.records.last().exercises?.size,
                     "workout snapshot was not saved")
        assertEquals(6, reloaded.records.last().actuals?.get(session.exercises[0].pattern))
        // skips and the per-pattern position snapshot survive the reload
        assertEquals(setOf(skippedPattern), reloaded.records.last().skipped)
        assertEquals(store.currentPositions, reloaded.records.last().positionsAfter)
    }

    /** The same session can arrive twice — a double tap, or a rating landing
     *  after the settlement already recorded it. Only `completeWorkout`'s own
     *  guard keeps a second journal entry out. */
    @Test
    fun completingTheSameSessionTwiceRecordsItOnce() {
        val store = makeStore()
        val session = store.nextSession
        store.completeWorkout(session = session, result = FeedbackResult.plan)
        val replay = store.completeWorkout(session = session, result = FeedbackResult.more)
        assertTrue(replay.isEmpty(), "a replay earns no milestones")
        assertEquals(1, store.records.size)
        assertEquals(FeedbackResult.plan, store.records.first().result, "the first answer stands")
        assertEquals(1, store.engineState.counter)
        assertEquals(1, makeStore().records.size, "and only one entry reached the file")
    }

    /** The journal keeps the sets behind the number, so history can say
     *  "15 · 15 · 10" instead of the bare mean the engine was handed. */
    @Test
    fun theJournalKeepsTheSetsBehindTheReportedNumber() {
        val store = makeStore()
        val session = store.nextSession
        val ex = session.exercises[0]
        // One rep short on the last set — what Swift's `SetFacts.recording`
        // writes for it; the writing half of SetFacts is not ported, so the
        // facts are spelled out. A clean start plans 3×4, and the corridor
        // floor is 0 — "minus five" would be clamped there.
        val facts = mapOf(ex.pattern to (0 until ex.sets).map { if (it == ex.sets - 1) ex.load - 1 else ex.plannedLoad(it) })
        val overrides = SetFacts.overrides(facts, skipping = emptyMap(), exercises = session.exercises)
        store.completeWorkout(session = session, result = FeedbackResult.plan,
                              overrides = overrides, setActuals = facts)

        val record = assertNotNull(makeStore().records.lastOrNull())
        assertEquals(facts[ex.pattern], record.setActuals?.get(ex.pattern))
        // The engine is handed the RAW mean; the journal keeps the integer it
        // acted on, rounded.
        assertEquals(overrides[ex.pattern]?.let { roundedAwayFromZero(it).toInt() },
                     record.actuals?.get(ex.pattern),
                     "the stored number is the one the engine acted on")
    }

    @Test
    fun skippedExerciseKeepsItsLevel() {
        val store = makeStore()
        val session = store.nextSession
        val skippedPattern = session.exercises[2].pattern
        store.completeWorkout(session = session, result = FeedbackResult.more, skipped = setOf(skippedPattern))
        assertEquals(0, Engine.progress(store.engineState, skippedPattern),
                     "a skipped pattern must not level up")
        assertEquals(0, store.engineState.sub[skippedPattern] ?: 0, "nor collect a sub-step")
        // "moves by the rating" is two SUB-STEPS, which on a clean start is
        // not yet a whole rung of dose.
        assertEquals(EngineConfig.deltaMore, store.engineState.sub[session.exercises[0].pattern],
                     "a trained pattern must still move by the rating")
        assertEquals(setOf(skippedPattern), store.records.last().skipped)
    }

    /** No button can rate "easy" on a session where nothing was trained, so
     *  the invariant is pinned here, on the ENGINE's guarantee: it must hold
     *  for a call no screen can produce. */
    @Test
    fun easyOverAFullySkippedSessionLeavesTheTotalAtZero() {
        val store = makeStore()
        val session = store.nextSession
        val skipped: Set<Pattern> = session.exercises.map { it.pattern }.toSet()
        store.completeWorkout(session = session, result = FeedbackResult.more, skipped = skipped)
        assertEquals(0, store.totalProgress, "skipped exercises must not raise the level (honest skips)")
        assertEquals(1, store.engineState.counter, "the appearance is still spent — the session happened")
    }
}
