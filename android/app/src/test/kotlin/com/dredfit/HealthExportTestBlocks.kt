//
//  Port of ios/DredfitTests/HealthExportTests+Blocks.swift: telling our own
//  workout from a foreign one, the blocks that did not happen, and the
//  identity the energy record carries. Every Swift test is ported; the
//  bundle identifier is a package name here.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.health.WorkoutHealthWriting
import com.dredfit.health.WorkoutOrigin
import com.dredfit.store.enableHealth
import com.dredfit.store.nextSession
import com.dredfit.store.setBodyMass
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HealthExportTestBlocks : AppStoreTestCase() {

    /** The trap this filter exists for: our own exported workout, found by the
     *  next run, would look like a watch recording of the same session and
     *  switch calories off forever. */
    @Test
    fun ourOwnWorkoutsAreNotForeign() {
        val start = date(2026, 7, 14)
        val origins = listOf(
            WorkoutOrigin("app.dredfit", start, start.plusSeconds(1800)),
            WorkoutOrigin("com.google.android.apps.fitness", start, start.plusSeconds(1800)),
            WorkoutOrigin(null, start, start.plusSeconds(600)),
        )
        val foreign = WorkoutHealthWriting.foreignIntervals(origins, excluding = "app.dredfit")
        assertEquals(listOf(1800.0, 600.0), foreign.map { it.durationSec }, "only our own package is filtered out")
    }

    /** A record whose end precedes its start must not run backwards. */
    @Test
    fun aBackwardsForeignSampleDoesNotTrap() {
        val start = date(2026, 7, 14)
        val foreign = WorkoutHealthWriting.foreignIntervals(
            listOf(WorkoutOrigin("other", start, start.minusSeconds(60))), excluding = "app.dredfit")
        assertEquals(0.0, foreign.firstOrNull()?.durationSec)
    }

    // MARK: - Blocks that did not happen

    @Test
    fun decliningBothBlocksLowersTheCalorie() = runHealth {
        val withBlocks = HealthSpy()
        val a = makeStore(health = withBlocks)
        a.enableHealth()
        a.setBodyMass(80.0)
        a.completeWorkout(session = a.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        a.healthExportJob?.join()

        val declined = HealthSpy()
        val b = makeStore(path = tempDir.resolve("b.json"), health = declined)
        b.enableHealth()
        b.setBodyMass(80.0)
        b.completeWorkout(session = b.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60,
                          warmupSec = 0, cooldownSec = 0)
        b.healthExportJob?.join()

        val full = assertNotNull(withBlocks.saved.firstOrNull()?.kcal)
        val bare = assertNotNull(declined.saved.firstOrNull()?.kcal)
        assertTrue(bare < full, "ten minutes nobody spent must not be billed")
    }

    @Test
    fun aPartlyDoneBlockLandsBetween() = runHealth {
        val kcal = mutableListOf<Double>()
        for (seconds in listOf(0, 150, 300)) {
            val spy = HealthSpy()
            val store = makeStore(path = tempDir.resolve("$seconds.json"), health = spy)
            store.enableHealth()
            store.setBodyMass(80.0)
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60,
                                  warmupSec = seconds, cooldownSec = 0)
            store.healthExportJob?.join()
            kcal += assertNotNull(spy.saved.firstOrNull()?.kcal)
        }
        assertTrue(kcal[0] < kcal[1])
        assertTrue(kcal[1] < kcal[2])
    }

    @Test
    fun aSessionWithEverythingSkippedWritesNoCalorie() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        val session = store.nextSession
        store.completeWorkout(session = session, result = FeedbackResult.plan,
                              skipped = session.exercises.map { it.pattern }.toSet(), durationSec = 35 * 60)
        store.healthExportJob?.join()

        assertEquals(1, spy.saved.size, "the workout is still a fact and still exports")
        assertNull(spy.saved[0].kcal)
    }

    @Test
    fun blockMeasurementsSurviveAReload() {
        val store = makeStore(health = HealthSpy())
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 30 * 60,
                              warmupSec = 0, cooldownSec = 210)
        val reloaded = makeStore(health = HealthSpy())
        val record = assertNotNull(reloaded.records.lastOrNull())
        assertEquals(0, record.warmupSec)
        assertEquals(210, record.cooldownSec)
    }

    @Test
    fun anOlderRecordFallsBackToThePlannedBlocks() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        store.healthExportJob?.join()

        val record = assertNotNull(store.records.lastOrNull())
        assertNull(record.warmupSec)
        assertNull(record.cooldownSec)
        assertNotNull(spy.saved.firstOrNull()?.kcal, "unknown blocks still price at the plan")
    }

    // MARK: - Provenance

    /** The record carries the identity of the journal entry it came from — on
     *  Android its `clientRecordId`, which is also what makes a second save
     *  replace the first. */
    @Test
    fun theEnergySampleCarriesTheRecordIdentity() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        store.healthExportJob?.join()

        val record = assertNotNull(store.records.lastOrNull())
        assertEquals(record.id, spy.saved.firstOrNull()?.journalID)
        assertFalse(record.id.isEmpty())
    }
}
