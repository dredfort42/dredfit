//
//  Port of ios/DredfitTests/HealthExporterTests.swift: the exporter on its
//  own — what it asks Health Connect, and what it hands over for a record.
//  The flags and the order of the backfill are the store's (HealthExportTest).
//  Every Swift test is ported.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.health.HealthExporter
import com.dredfit.health.TimeSpan
import com.dredfit.journal.WorkoutRecord
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HealthExporterTest {

    private val end = Instant.ofEpochSecond(1_900_000_000)

    private fun record(minutes: Int, daysBefore: Long = 0): WorkoutRecord =
        WorkoutRecord(sessionNumber = 1 + daysBefore.toInt(), date = end.minusSeconds(daysBefore * 86_400),
                      result = FeedbackResult.plan, durationSec = minutes * 60)

    @Test
    fun withoutAWeightHealthIsAskedNothing() = runHealth {
        val spy = HealthSpy()
        val exporter = HealthExporter(spy)
        val none = exporter.energyContext(null, watchRecordsWorkouts = false, now = end) { listOf(record(30)) }
        val watched = exporter.energyContext(70.0, watchRecordsWorkouts = true, now = end) { listOf(record(30)) }
        assertNull(none.bodyMassKg)
        assertNull(watched.bodyMassKg, "a watch already measured the energy")
        assertEquals(0, spy.foreignQueries)
    }

    @Test
    fun theSweepStartsWhereTheEarliestPendingWorkoutStarted() = runHealth {
        val spy = HealthSpy()
        spy.foreign = listOf(TimeSpan(end.minusSeconds(86_400 + 1_200), end.minusSeconds(86_400 + 1_140)))
        val context = HealthExporter(spy).energyContext(70.0, watchRecordsWorkouts = false, now = end) {
            listOf(record(30, daysBefore = 1), record(30))
        }
        assertEquals(70.0, context.bodyMassKg)
        assertEquals(1, spy.foreignQueries, "one query over the whole journal, not one per record")
        assertEquals(spy.foreign, context.foreign, "a foreign workout inside the older record is found too")
    }

    @Test
    fun anExportCarriesTheRecordsIntervalAndID() = runHealth {
        val spy = HealthSpy()
        val saved = HealthExporter(spy).export(record(30), HealthExporter.EnergyContext())
        assertTrue(saved)
        assertEquals(listOf(SavedWorkout(end.minusSeconds(1_800), end, null, record(30).id)), spy.saved)
    }

    @Test
    fun aRefusedSaveIsReportedAsNotExported() = runHealth {
        val spy = HealthSpy()
        spy.allFail = true
        val saved = HealthExporter(spy).export(record(30), HealthExporter.EnergyContext())
        assertFalse(saved, "the store flags a record only on a confirmed save")
    }

    @Test
    fun aBodyMassOutsideReasonIsNoBodyMass() {
        assertNull(HealthExporter.sanitizedBodyMass(0.0))
        assertNull(HealthExporter.sanitizedBodyMass(-70.0))
        assertNull(HealthExporter.sanitizedBodyMass(Double.NaN))
        assertNull(HealthExporter.sanitizedBodyMass(Double.POSITIVE_INFINITY))
        assertEquals(72.5, HealthExporter.sanitizedBodyMass(72.5))
        assertEquals(500.0, HealthExporter.sanitizedBodyMass(900.0))
    }
}
