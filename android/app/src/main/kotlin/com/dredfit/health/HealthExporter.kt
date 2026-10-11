//
//  What the app reads from Health Connect and writes to it: one workout per
//  journal record, the calories it carries, and the weight they are priced
//  from. Port of ios/Dredfit/HealthExporter.swift — best-effort, and nothing
//  here touches the journal: the store flags a record exported only after the
//  save this reports has been confirmed, so a hole in the export is always
//  retriable. Each workout carries its record's id as its `clientRecordId`,
//  which is what keeps a re-export from duplicating it.
//

package com.dredfit.health

import com.dredfit.core.EngineConfig
import com.dredfit.core.Pattern
import com.dredfit.core.SwiftJson
import com.dredfit.journal.WorkoutRecord
import com.dredfit.workout.BodyProfile
import com.dredfit.workout.EnergyEstimate
import java.time.Instant

class HealthExporter(val health: WorkoutHealthWriting) {

    /** Read once per backfill run, not once per record: the profile does not
     *  change mid-run, and the foreign-workout sweep is ONE query over the
     *  whole journal rather than one per workout. */
    data class EnergyContext(
        val bodyMassKg: Double? = null,
        val profile: BodyProfile = BodyProfile.unknown,
        val foreign: List<TimeSpan> = emptyList(),
    )

    /** Health Connect's newest weight, sanitized; null when there is none and
     *  when the read was refused. Its date is held to what a Swift `Date`
     *  can carry, as every stored date is: the store compares it with the
     *  date it wrote down, and a reading must equal itself read back or every
     *  activation would rewrite the file for a number that did not move. */
    suspend fun latestBodyMass(): BodyMassReading? {
        val r = health.latestBodyMass() ?: return null
        return sanitizedBodyMass(r.kg)?.let { BodyMassReading(it, SwiftJson.swiftDate(r.date)) }
    }

    /** Nothing is read unless a weight makes the reading useful. `pending`
     *  is read after the profile query, so a workout finished while it ran
     *  is inside the swept window. */
    suspend fun energyContext(bodyMassKg: Double?, watchRecordsWorkouts: Boolean,
                              now: Instant, pending: () -> List<WorkoutRecord>): EnergyContext {
        if (bodyMassKg == null || watchRecordsWorkouts) return EnergyContext()
        val profile = health.profile()
        val spans = pending().map { interval(it, estimatedDurationSec(it)) }
        // Up to now, not to the last pending record: the loop re-reads the
        // journal, so a workout finished seconds into the run is exported by
        // this same pass and has to be inside the swept window.
        val from = spans.minOfOrNull { it.start } ?: return EnergyContext(bodyMassKg, profile)
        val to = maxOf(spans.maxOf { it.end }, now)
        val foreign = if (from < to) health.foreignWorkoutIntervals(from, to) else emptyList()
        return EnergyContext(bodyMassKg, profile, foreign)
    }

    /** Saves one record's workout; false when Health Connect refused or failed. */
    suspend fun export(record: WorkoutRecord, context: EnergyContext): Boolean {
        val span = interval(record, estimatedDurationSec(record))
        val kcal = activeKcal(record, span, context)
        return health.saveWorkout(span.start, span.end, kcal, record.id)
    }

    // MARK: - Calories

    /** Null whenever the number would be a guess rather than an estimate: no
     *  weight, no exercise snapshot to segment, or a session another app also
     *  recorded — that one carries its own measured energy. */
    private suspend fun activeKcal(record: WorkoutRecord, span: TimeSpan, context: EnergyContext): Double? {
        val kg = context.bodyMassKg ?: return null
        val exercises = record.exercises ?: return null
        val segments = EnergyEstimate.segments(exercises, notPerformed(record), record.warmupSec, record.cooldownSec)
            ?: return null
        if (context.foreign.any { it.overlapSec(span) > 0 }) return null
        // The rate is read over the interval the SUM covers, not over the plan.
        val basal = health.restingKcal(span.start, span.end)
        val resting = EnergyEstimate.resting(basal, span.durationSec / 60, kg, context.profile)
        val kcal = EnergyEstimate.activeKcal(segments, kg, resting) ?: return null
        return kcal * EnergyEstimate.actualityFactor(segments.totalSec, record.durationSec)
    }

    companion object {
        /** Whether a reading replaces the number in force: yes over nothing,
         *  yes over an undated number, yes when the reading is NEWER than the
         *  number's own statement — the later statement wins. */
        fun adopts(reading: BodyMassReading, over: Double?, statedAt: Instant?): Boolean {
            if (over == null) return true
            if (statedAt == null) return true
            return reading.date > statedAt
        }

        fun sanitizedBodyMass(kg: Double): Double? {
            if (!kg.isFinite() || kg <= 0) return null
            return minOf(kg, 500.0)
        }

        /** Clamped: a wall clock moved backwards mid-workout leaves a negative
         *  duration, and an interval that does not move forward fails the save
         *  forever — blocking the whole tail. */
        private fun interval(record: WorkoutRecord, estimate: Int): TimeSpan {
            val duration = maxOf(60, record.durationSec ?: estimate)
            return TimeSpan(record.date.minusSeconds(duration.toLong()), record.date)
        }

        /** A record written by an older build keeps its pain reports, and they
         *  were "not performed" exactly as a skip was. */
        private fun notPerformed(record: WorkoutRecord): Set<Pattern> =
            (record.skipped ?: emptySet()) + (record.discomfort ?: emptySet())

        /** For records that predate duration capture: the session's segments,
         *  so the estimate cannot drift from the plan's own length; a flat
         *  35 min without a snapshot. In Double until the final clamp — the
         *  snapshot comes back out of the journal file unclamped. */
        private fun estimatedDurationSec(record: WorkoutRecord): Int {
            val exercises = record.exercises ?: return 35 * 60
            val segments = EnergyEstimate.segments(exercises, notPerformed(record), record.warmupSec, record.cooldownSec)
                ?: return 35 * 60
            val total = segments.totalSec
            if (!total.isFinite()) return 35 * 60
            return total.coerceIn(0.0, EngineConfig.countMax.toDouble()).toInt()
        }
    }
}
