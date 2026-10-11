//
//  Port of ios/DredfitTests/HealthExportTests+Energy.swift: the calorie half
//  of the export — what makes a number appear, what keeps it away, and where
//  the weight behind it comes from. Every Swift test is ported. `activate()`
//  re-checks the permission and reads the weight in one job here
//  (`bodyMassJob`), iOS's `bodyMassTask`.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.health.BodyMassReading
import com.dredfit.health.HealthExporter
import com.dredfit.health.TimeSpan
import com.dredfit.store.AppData
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.backfillHealth
import com.dredfit.store.disableHealth
import com.dredfit.store.enableHealth
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import com.dredfit.store.nextSession
import com.dredfit.store.setBodyMass
import com.dredfit.store.setWatchRecordsWorkouts
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.yield
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HealthExportTestEnergy : AppStoreTestCase() {

    private fun durationSec(span: TimeSpan): Double = span.durationSec

    @Test
    fun withoutABodyMassTheWorkoutExportsWithoutCalories() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        store.healthExportJob?.join()

        assertEquals(1, spy.saved.size, "the workout still reaches Health Connect")
        assertNull(spy.saved[0].kcal, "no weight may produce no calories")
        assertEquals(0, store.records.count { it.healthConnectExported != true }, "and the record is done, not stuck")
    }

    @Test
    fun withoutABodyMassTheTwoSweepsAreSkipped() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        store.healthExportJob?.join()

        assertEquals(0, spy.foreignQueries)
        assertTrue(spy.restingQueries.isEmpty())
        assertTrue(spy.massQueries > 0, "the weight is read even so")
    }

    @Test
    fun aBodyMassProducesCalories() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        store.healthExportJob?.join()

        val kcal = assertNotNull(spy.saved.firstOrNull()?.kcal)
        assertTrue(kcal > 30)
        assertTrue(kcal < 400, "a bodyweight session is not a marathon")
    }

    @Test
    fun anOverlappingForeignWorkoutSuppressesOnlyTheCalories() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        val end = date(2026, 7, 14)
        spy.foreign = listOf(TimeSpan(end.minusSeconds(20 * 60), end))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60, date = end)
        store.healthExportJob?.join()

        assertEquals(1, spy.saved.size, "the workout must still reach Health Connect")
        assertNull(spy.saved[0].kcal, "the calories are the double count, not the workout")
    }

    @Test
    fun aDistantForeignWorkoutLeavesTheCaloriesAlone() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        spy.foreign = listOf(TimeSpan(date(2026, 7, 12), date(2026, 7, 12).plusSeconds(3600)))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60,
                              date = date(2026, 7, 14))
        store.healthExportJob?.join()

        assertNotNull(spy.saved.firstOrNull()?.kcal)
    }

    @Test
    fun theWatchToggleSuppressesCalories() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        store.setWatchRecordsWorkouts(true)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        store.healthExportJob?.join()

        assertEquals(1, spy.saved.size)
        assertNull(spy.saved[0].kcal)
        assertEquals(0, spy.foreignQueries, "there is nothing left to look for")
    }

    @Test
    fun theForeignSweepRunsOncePerBackfill() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.setBodyMass(80.0)
        for (day in 10..14) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60,
                                  date = date(2026, 7, day))
        }
        store.enableHealth()
        store.backfillHealth()

        assertEquals(5, spy.saved.size)
        assertEquals(1, spy.foreignQueries, "one sweep covers the whole journal")
    }

    @Test
    fun theRestingSumIsReadOverTheExportedInterval() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(80.0)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 50 * 60,
                              date = date(2026, 7, 14))
        store.healthExportJob?.join()

        assertEquals(1, spy.restingQueries.size)
        assertEquals(50.0 * 60, durationSec(spy.restingQueries[0]), 1.0)
        assertEquals(date(2026, 7, 14), spy.restingQueries[0].end)
    }

    // MARK: - Where the weight comes from

    @Test
    fun enablingHealthAdoptsTheRecordedBodyMass() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        val store = makeStore(health = spy)
        store.enableHealth()
        assertEquals(72.5, store.settings.bodyMassKg)
    }

    @Test
    fun onEnablingANewerHealthReadingReplacesTheTypedWeightAndAnOlderOneDoesNot() = runHealth {
        val newer = HealthSpy()
        newer.bodyMassKg = 72.5
        newer.bodyMassDate = Instant.now().plusSeconds(60)
        val a = makeStore(health = newer)
        a.setBodyMass(90.0)
        a.enableHealth()
        assertEquals(72.5, a.settings.bodyMassKg, "the scale spoke later")
        assertTrue(a.settings.bodyMassFromHealth)
        // Held to a Swift Date, as every stored date is.
        assertEquals(com.dredfit.core.SwiftJson.swiftDate(assertNotNull(newer.bodyMassDate)), a.settings.bodyMassDate)

        val older = HealthSpy()
        older.bodyMassKg = 72.5
        older.bodyMassDate = Instant.now().minusSeconds(30 * 86_400)
        val b = makeStore(path = tempDir.resolve("older.json"), health = older)
        b.setBodyMass(90.0)
        b.enableHealth()
        assertEquals(90.0, b.settings.bodyMassKg, "the typed number is the later statement")
        assertFalse(b.settings.bodyMassFromHealth)
        assertEquals(1, older.massQueries, "Health Connect was asked, and its answer ranked lower")
    }

    @Test
    fun aStaleHealthReadingDoesNotOverwriteATypedWeightUntilANewerOneArrives() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        spy.bodyMassDate = Instant.now().minusSeconds(30 * 86_400)
        val store = makeStore(health = spy)
        store.enableHealth()
        assertEquals(72.5, store.settings.bodyMassKg, "nothing typed yet: the reading is adopted, old or not")

        store.setBodyMass(80.0)
        repeat(3) {
            store.activate()
            store.bodyMassJob?.join()
            assertEquals(80.0, store.settings.bodyMassKg, "the typed number stands on every foreground")
            assertFalse(store.settings.bodyMassFromHealth)
        }

        spy.bodyMassKg = 78.0
        spy.bodyMassDate = Instant.now().plusSeconds(1)
        store.activate()
        store.bodyMassJob?.join()
        assertEquals(78.0, store.settings.bodyMassKg, "a newer weigh-in takes over")
        assertTrue(store.settings.bodyMassFromHealth)
    }

    @Test
    fun aReadingIsAdoptedOnlyOverNothingOrOverAnOlderStatement() {
        val sample = BodyMassReading(70.0, Instant.ofEpochSecond(1_000))
        assertTrue(HealthExporter.adopts(sample, null, null))
        assertTrue(HealthExporter.adopts(sample, 80.0, null), "an undated number is a file from before the date was kept")
        assertTrue(HealthExporter.adopts(sample, 80.0, Instant.ofEpochSecond(999)))
        assertFalse(HealthExporter.adopts(sample, 80.0, Instant.ofEpochSecond(1_000)), "the same moment is not later")
        assertFalse(HealthExporter.adopts(sample, 80.0, Instant.ofEpochSecond(1_001)))
    }

    @Test
    fun aNewHealthWeightIsPickedUpOnActivation() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        val store = makeStore(health = spy)
        store.enableHealth()

        spy.bodyMassKg = 68.0
        store.activate()
        store.bodyMassJob?.join()
        assertEquals(68.0, store.settings.bodyMassKg)
    }

    @Test
    fun anAbsentHealthWeightKeepsTheTypedOneAndTheField() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(90.0)

        store.activate()
        store.bodyMassJob?.join()
        assertEquals(90.0, store.settings.bodyMassKg)
        assertFalse(store.settings.bodyMassFromHealth, "so the row stays editable")
    }

    @Test
    fun healthGoingQuietKeepsTheLastReadingAndItsOrigin() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        val store = makeStore(health = spy)
        store.enableHealth()

        spy.bodyMassKg = null
        store.activate()
        store.bodyMassJob?.join()
        assertEquals(72.5, store.settings.bodyMassKg, "the last reading stands")
        assertTrue(store.settings.bodyMassFromHealth, "and it still came from Health Connect")
    }

    @Test
    fun theWeightIsNotReadWhileHealthIsOff() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        val store = makeStore(health = spy)
        store.activate()
        store.bodyMassJob?.join()
        assertNull(store.settings.bodyMassKg)
        assertFalse(store.settings.bodyMassFromHealth)
        assertEquals(0, spy.massQueries)
    }

    /** The baseline is MEASURED, not guessed: the same session exported
     *  while Health Connect still says 60. */
    @Test
    fun theExportRunRefreshesTheWeightFirst() = runHealth {
        val stale = HealthSpy()
        stale.bodyMassKg = 60.0
        val staleStore = makeStore(path = tempDir.resolve("stale.json"), health = stale)
        staleStore.enableHealth()
        staleStore.completeWorkout(session = staleStore.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        staleStore.healthExportJob?.join()
        val atSixty = assertNotNull(stale.saved.firstOrNull()?.kcal)

        val spy = HealthSpy()
        spy.bodyMassKg = 60.0
        val store = makeStore(health = spy)
        store.enableHealth()

        spy.bodyMassKg = 120.0   // weighed again, after the toggle went on
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, durationSec = 35 * 60)
        store.healthExportJob?.join()

        assertEquals(120.0, store.settings.bodyMassKg)
        val kcal = assertNotNull(spy.saved.firstOrNull()?.kcal)
        assertTrue(kcal > atSixty, "the export multiplied by the new weight, not the enabled-day one")
    }

    /** Kicks an activation and returns once the spy's gated weight read is in
     *  flight — a test that moves the world before the read starts is caught
     *  by the guard at the top of the refresh and passes vacuously. */
    private suspend fun CoroutineScope.activateAndWaitForGatedRead(store: AppStore, spy: HealthSpy) {
        val before = spy.massQueries
        store.activate()
        var spins = 0
        while (spy.massQueries == before && spins < 10_000) {
            spins += 1
            yield()
        }
        assertEquals(before + 1, spy.massQueries, "the gated read must be in flight")
    }

    @Test
    fun theToggleGoingDownMidReadStopsTheWrite() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(90.0)

        val gate = CompletableDeferred<Unit>()
        spy.massGate = gate
        activateAndWaitForGatedRead(store, spy)
        store.disableHealth()
        gate.complete(Unit)
        store.bodyMassJob?.join()

        assertEquals(90.0, store.settings.bodyMassKg, "a reading may not land after the toggle went down")
        assertFalse(store.settings.bodyMassFromHealth)
    }

    @Test
    fun aCancelledRefreshDoesNotWrite() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 68.0
        val store = makeStore(health = spy)
        store.enableHealth()
        store.setBodyMass(90.0)

        val gate = CompletableDeferred<Unit>()
        spy.massGate = gate
        activateAndWaitForGatedRead(store, spy)
        val superseded = store.bodyMassJob
        superseded?.cancel()
        gate.complete(Unit)
        superseded?.join()

        assertEquals(90.0, store.settings.bodyMassKg, "the superseded run wrote nothing")
    }

    @Test
    fun aRestoredBackupDoesNotInheritTheHealthOrigin() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        val donor = makeStore(health = spy)
        donor.enableHealth()
        assertTrue(donor.settings.bodyMassFromHealth)
        val backup = donor.exportBackup()

        // This device's Health Connect answers nothing.
        val fresh = makeStore(path = tempDir.resolve("restored.json"), health = HealthSpy())
        fresh.importBackup(backup)

        assertEquals(72.5, fresh.settings.bodyMassKg, "the number travels")
        assertFalse(fresh.settings.bodyMassFromHealth, "the claim about where it came from does not")
    }

    @Test
    fun aRestoredWeightOutranksAnOlderHealthReading() = runHealth {
        val donor = makeStore(health = HealthSpy())
        donor.completeWorkout(session = donor.nextSession, result = FeedbackResult.plan)
        donor.setBodyMass(80.0)
        val backup = donor.exportBackup()

        val stale = HealthSpy()
        stale.bodyMassKg = 72.5
        stale.bodyMassDate = Instant.now().minusSeconds(30 * 86_400)
        val fresh = makeStore(path = tempDir.resolve("restored.json"), health = stale)
        fresh.enableHealth()
        assertEquals(72.5, fresh.settings.bodyMassKg, "before the restore Health Connect's number is all there is")
        fresh.importBackup(backup)
        fresh.activate()
        fresh.bodyMassJob?.join()
        assertEquals(80.0, fresh.settings.bodyMassKg, "the restored weight is the later statement")

        // The same backup with the date stripped — a file from before the key.
        val json = Json.parseToJsonElement(backup.toString(Charsets.UTF_8)).jsonObject
        val settings = assertNotNull(json["settings"]?.jsonObject)
        assertTrue("bodyMassDate" in settings, "the date travels in the file")
        val legacy = JsonObject(json + ("settings" to JsonObject(settings - "bodyMassDate")))
        val again = makeStore(path = tempDir.resolve("restored2.json"), health = stale)
        again.enableHealth()
        again.importBackup(legacy.toString().toByteArray())
        assertEquals(again.records.maxOfOrNull { it.date }, again.settings.bodyMassDate,
                     "dated by the newest workout it came with")
        again.activate()
        again.bodyMassJob?.join()
        assertEquals(80.0, again.settings.bodyMassKg)
    }

    @Test
    fun aFileClaimingHealthWithoutAWeightDecodesAsTyped() {
        val seed = makeStore(health = HealthSpy())
        val settings = seed.settings.copy(healthEnabled = true, bodyMassFromHealth = true)   // and no bodyMassKg
        Files.writeString(tempPath, AppData(seed.engineState, emptyList(), settings).encode())

        val store = makeStore(health = HealthSpy())
        assertNull(store.settings.bodyMassKg)
        assertFalse(store.settings.bodyMassFromHealth, "no number, no claim about it")
    }

    @Test
    fun theDateOfTheWeightIsNeverKeptWithoutTheNumber() {
        val seed = makeStore(health = HealthSpy())
        val settings = seed.settings.copy(bodyMassDate = Instant.now())   // and no bodyMassKg
        Files.writeString(tempPath, AppData(seed.engineState, emptyList(), settings).encode())
        val store = makeStore(health = HealthSpy())
        assertNull(store.settings.bodyMassDate)

        store.setBodyMass(80.0)
        assertNotNull(store.settings.bodyMassDate)
        store.setBodyMass(null)
        assertNull(store.settings.bodyMassDate, "clearing is not a claim about a number")
    }

    @Test
    fun theHealthOriginOfTheWeightPersists() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        val store = makeStore(health = spy)
        store.enableHealth()

        val reloaded = makeStore(health = HealthSpy())
        assertEquals(72.5, reloaded.settings.bodyMassKg)
        assertTrue(reloaded.settings.bodyMassFromHealth)
    }

    @Test
    fun aRefusedBodyMassReadLeavesTheFieldEmpty() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        assertNull(store.settings.bodyMassKg)
    }

    @Test
    fun anImpossibleBodyMassIsNotStored() {
        val store = makeStore(health = HealthSpy())
        for (mass in listOf(0.0, -5.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            store.setBodyMass(mass)
            assertNull(store.settings.bodyMassKg, "$mass kg is not a body")
        }
        store.setBodyMass(900.0)
        assertEquals(500.0, store.settings.bodyMassKg, "clamped, not refused")
    }

    @Test
    fun bodyMassAndWatchAnswerPersist() {
        val store = makeStore(health = HealthSpy())
        store.setBodyMass(77.5)
        store.setWatchRecordsWorkouts(true)
        val reloaded = makeStore(health = HealthSpy())
        assertEquals(77.5, reloaded.settings.bodyMassKg)
        assertTrue(reloaded.settings.watchRecordsWorkouts)
    }

    // MARK: - Android only

    /** A reading lands on a date a Swift `Date` can hold, so a reload reads
     *  back the very date the refresh compares with — otherwise every return
     *  to the app would rewrite the file for a weight that did not move. */
    @Test
    fun anUnchangedReadingWritesNothingAfterAReload() = runHealth {
        val spy = HealthSpy()
        spy.bodyMassKg = 72.5
        // A nanosecond a Swift Date rounds DOWN: read back, the stored date
        // is older than the reading, which would then win again and again.
        spy.bodyMassDate = Instant.parse("2026-10-01T09:07:39.500000001Z")
        val store = makeStore(health = spy)
        store.enableHealth()

        val reloaded = makeStore(health = spy)
        Files.delete(tempPath)
        reloaded.activate()
        reloaded.bodyMassJob?.join()
        assertFalse(Files.exists(tempPath), "the same reading again is not a change")
    }
}
