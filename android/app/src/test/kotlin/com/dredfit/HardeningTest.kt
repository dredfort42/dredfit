//
//  Port of ios/DredfitTests/HardeningTests.swift — the day anchor and the
//  cold-launch activation. The reminder tests (ten) arrive with reminders/,
//  and `testStaleDateArithmetic` with the Live Activity's counterpart.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.journal.RecordedPosition
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.doneToday
import com.dredfit.store.nextSession
import com.dredfit.store.positions
import com.dredfit.store.refreshDay
import java.nio.file.Path
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HardeningTest : AppStoreTestCase() {

    // MARK: - Day anchor

    /** Crossing midnight while the process stays alive must re-anchor the
     *  UI's "today" — the tab must not stay stuck on yesterday's done state. */
    @Test
    fun refreshDayReanchorsAcrossMidnight() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        assertTrue(store.doneToday)

        store.refreshDay(now = ZonedDateTime.now().plusDays(1).toInstant())
        assertFalse(store.doneToday, "the new day must not inherit yesterday's done state")

        // Same-day activations must not move the anchor (no pointless renders).
        val anchor = store.today
        store.refreshDay(now = anchor.plusSeconds(60))
        assertEquals(anchor, store.today, "a same-day refresh must be a no-op")
    }

    /** A workout run across midnight: only the time-change pulse moves the
     *  anchor — and it moves nothing but the date (the decay stays with
     *  `activate()`). */
    @Test
    fun aWorkoutFinishedPastMidnightReadsDoneOnceTheDateMoves() {
        val store = makeStore()
        val pastMidnight = ZonedDateTime.now().plusDays(1).toInstant()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = pastMidnight)
        assertFalse(store.doneToday, "the stale anchor still reads yesterday")
        val state = store.engineState
        store.reanchorToday(now = pastMidnight)
        assertTrue(store.doneToday)
        assertEquals(state, store.engineState, "re-anchoring must not touch the plan")
    }

    // MARK: - Cold-launch activation (issue #93)

    /** A journal whose last workout was `daysAgo` days ago — four workouts —
     *  and the positions they left: what a decay is measured against. */
    private fun seedWorkout(daysAgo: Long, at: Path): Map<Pattern, RecordedPosition> {
        val store = makeStore(at)
        val date = ZonedDateTime.now().minusDays(daysAgo).toInstant()
        repeat(4) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date) }
        return positions(store.engineState)
    }

    /** A decay is one rung of DOSE, and on a grid's floor a set instead — so
     *  what is claimed is "the plan moved, and it never moved up". */
    private fun assertDecayed(store: AppStore, seeded: Map<Pattern, RecordedPosition>, message: String) {
        var moved = false
        for (p in Pattern.allCases) {
            val was = seeded[p] ?: continue
            val before = Engine.progress(p, variation = was.variation, sets = was.sets, dose = was.dose)
            val now = Engine.progress(store.engineState, p)
            assertTrue(now <= before, "$p: $message")
            if (now < before) moved = true
        }
        assertTrue(moved, message)
    }

    /** A cold launch renders already active, so the phase transition never
     *  fires — `activate()` must run the blind-zone decay, or a 7–13-day
     *  return trains on the pre-break plan. */
    @Test
    fun coldLaunchActivationAppliesSilentDecay() {
        val seeded = seedWorkout(daysAgo = 10, at = tempPath)

        val cold = makeStore()
        cold.activate()
        assertDecayed(cold, seeded, "the cold launch must see the decay")

        val once = positions(cold.engineState)
        cold.activate()
        assertEquals(once, positions(cold.engineState), "a second activation in the same break must not decay again")

        val relaunched = makeStore()
        relaunched.activate()
        assertEquals(once, positions(relaunched.engineState),
                     "the stamp persists — a relaunch inside the break must not decay again")
    }

    @Test
    fun coldLaunchActivationLeavesGapsOutsideTheBlindZoneAlone() {
        for (days in listOf(6L, 14)) {
            val path = tempDir.resolve("gap$days.json")
            seedWorkout(daysAgo = days, at = path)
            val cold = makeStore(path)
            val before = cold.engineState
            cold.activate()
            assertEquals(before, cold.engineState, "gap $days: outside [7, 14) activation must not touch the engine")
        }
    }

    /** The seam's order matters: a launch that could not read its journal
     *  must reload first and decay after — the other way round the decay
     *  finds no journal and silently skips the break. */
    @Test
    fun activationReloadsBeforeDecaying() {
        assumeNotRoot()
        val seeded = seedWorkout(daysAgo = 10, at = tempPath)
        setPermissions(tempPath, "---------")
        val frozen = makeStore()
        setPermissions(tempPath, "rw-r--r--")

        frozen.activate()
        assertDecayed(frozen, seeded, "one activate() must both reload the journal and decay it")
    }
}
