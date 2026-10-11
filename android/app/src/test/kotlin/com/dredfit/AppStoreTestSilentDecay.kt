//
//  Port of ios/DredfitTests/AppStoreTests+SilentDecay.swift — the 7–13 day
//  blind zone (issue #37). One invariant: a break decays at most once, and a
//  peeked-at break must not cost more than one left alone.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.store.positions
import org.junit.jupiter.api.Test
import java.nio.file.Path
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class AppStoreTestSilentDecay : AppStoreTestCase() {

    /**
     * A store whose last workout happened `daysAgo` days ago, after `sessions`
     * workouts rated "plan": grown positions give a break room to fall. Seeded
     * from MIDNIGHTS (`daysAgo`): 6/7 and 13/14 are the exact edges of the
     * zone, and an elapsed-seconds seed slips a day across DST. The seeding
     * workouts are one CALENDAR day apart — stacked on one instant, the weekly
     * budget would hold the positions near the clean start.
     */
    private fun storeWithWorkout(daysAgo: Long, at: Path, sessions: Long = 15): AppStore {
        val last = daysAgo(daysAgo).atZone(ZoneId.systemDefault())
        val store = makeStore(at)
        for (i in 0 until sessions) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                                  date = last.minusDays(sessions - 1 - i).toInstant())
        }
        return store
    }

    @Test
    fun silentDecayAppliesExactlyOncePerBreak() {
        val store = storeWithWorkout(daysAgo = 10, at = tempPath)
        val before = positions(store.engineState)
        store.applySilentDecayIfNeeded()
        for (p in Pattern.allCases) {
            // One rung of DOSE, floored by the grid — on the floor it takes a
            // set instead, hence "no heavier", not "exactly minus one".
            val was = assertNotNull(before[p])
            assertTrue(Engine.progress(store.engineState, p) <=
                           Engine.progress(p, variation = was.variation, sets = was.sets, dose = was.dose),
                       "$p: a decay never adds")
        }
        val once = positions(store.engineState)
        assertNotEquals(before, once, "the decay did something")
        store.applySilentDecayIfNeeded()
        assertEquals(once, positions(store.engineState), "the same break must not decay twice")
        // The stamp survives a relaunch — persisted, not in-memory.
        val reloaded = makeStore()
        reloaded.applySilentDecayIfNeeded()
        assertEquals(once, positions(reloaded.engineState), "a relaunch inside the same break must not decay again")
    }

    @Test
    fun silentDecayIgnoresGapsOutsideTheBlindZone() {
        for (days in listOf(0L, 6L, 14L, 30L)) {
            val store = storeWithWorkout(daysAgo = days, at = tempDir.resolve("dredfit-test.$days.json"))
            val before = store.engineState
            store.applySilentDecayIfNeeded()
            assertEquals(before, store.engineState, "gap $days: outside [7, 14) nothing may change")
        }
    }

    @Test
    fun decayedBreakComebackTotalsExactlyTheTable() {
        // Calendar arithmetic, like the seed: 10 + 6 must stay 16 across DST.
        val day16 = ZonedDateTime.now().plusDays(6).toInstant()
        // Break that got peeked at on day 10: decay, then a weakened comeback.
        val peeked = storeWithWorkout(daysAgo = 10, at = tempPath)
        peeked.applySilentDecayIfNeeded()
        peeked.acceptComeback(now = day16)
        // The same break with the app never opened: one plain comeback.
        val control = storeWithWorkout(daysAgo = 10, at = tempDir.resolve("dredfit-test.control.json"))
        control.acceptComeback(now = day16)
        // A decay plus a weakened comeback walks the same rungs as one plain
        // comeback, and the identity is read where it lands.
        assertEquals(positions(control.engineState), positions(peeked.engineState),
                     "peeking mid-break must not cost more than staying away")
    }

    @Test
    fun decayStampGoesStaleAfterTheNextWorkout() {
        val store = storeWithWorkout(daysAgo = 10, at = tempPath)
        store.applySilentDecayIfNeeded()
        // The break ends: a workout today re-anchors the stamp's reference.
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        val after = positions(store.engineState)
        // A fresh 8-day break decays again — the old stamp must not block it.
        val day8 = ZonedDateTime.now().plusDays(8).toInstant()
        store.applySilentDecayIfNeeded(now = day8)
        assertNotEquals(after, positions(store.engineState), "a new break must decay independently")
    }
}
