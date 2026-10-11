//
//  Writes workouts, reads only what a calorie needs. Nothing leaves the
//  device. Port of the seam half of ios/Dredfit/HealthStore.swift: the store
//  and the exporter talk to `WorkoutHealthWriting`, JVM tests hand them a
//  spy, and the app hands them `HealthConnectWriter` (HealthConnectWriter.kt),
//  the Health Connect half of HealthKitWorkoutWriter. Plain Kotlin, so the
//  rules here run in a JVM test.
//

package com.dredfit.health

import com.dredfit.workout.BodyProfile
import com.dredfit.workout.Countdown
import java.time.Instant

/** Where a workout in Health Connect came from, and when: just enough of an
 *  ExerciseSessionRecord to decide whether it is ours. */
data class WorkoutOrigin(val packageName: String?, val start: Instant, val end: Instant)

/** One weigh-in: the kilograms and when they were true. */
data class BodyMassReading(val kg: Double, val date: Instant)

/** A span of time, as the exporter and the foreign-workout sweep use it —
 *  Foundation's `DateInterval`. `end` never precedes `start`. */
data class TimeSpan(val start: Instant, val end: Instant) {
    val durationSec: Double get() = Countdown.seconds(start, end)

    /** Seconds the two spans share; zero when they only touch or miss —
     *  `intersection(with:)?.duration ?? 0`. */
    fun overlapSec(other: TimeSpan): Double {
        val from = maxOf(start, other.start)
        val to = minOf(end, other.end)
        return if (to > from) Countdown.seconds(from, to) else 0.0
    }
}

/**
 * The seam. Every call is best-effort: Health Connect may be missing, a type
 * may be refused on its own, and each refusal only costs the feature that
 * needs it. Unlike HealthKit, Health Connect DOES say what was granted, but
 * the answers are kept iOS's shape — nil for "nothing there" and for "not
 * allowed" alike — so the store's rules are the iOS rules.
 */
interface WorkoutHealthWriting {
    /** Health Connect is installed and usable on this phone, now. */
    val isAvailable: Boolean

    /** Asks for the whole set (HealthConnectWriter.permissions); true only
     *  when the WORKOUT write was granted. Every other type may be refused
     *  on its own. May wait on a system screen. */
    suspend fun requestAuthorization(): Boolean

    /** The same answer, read now and without asking. A suspend call here
     *  where HealthKit's is a property: on Android 10–13 the grants live in
     *  the Health Connect app and are read over IPC. */
    suspend fun workoutShareGranted(): Boolean

    /** The newest weight with the moment it was taken, or null when there is
     *  none and when the read was refused. */
    suspend fun latestBodyMass(): BodyMassReading?

    /** Height, age and sex. Health Connect has no date-of-birth and no sex
     *  record, so on Android the age and sex are always absent — and the
     *  Mifflin rung needs the age, so the height alone changes nothing and is
     *  not read either: the profile is `BodyProfile.unknown` (android/README.md
     *  "Health Connect" says why). Kept in the seam so the exporter stays the
     *  iOS one and a test can still hand it a profile. */
    suspend fun profile(): BodyProfile

    /** Resting energy already recorded for this interval, in kcal. */
    suspend fun restingKcal(start: Instant, end: Instant): Double?

    /** Workouts recorded by OTHER apps that touch this window. */
    suspend fun foreignWorkoutIntervals(start: Instant, end: Instant): List<TimeSpan>

    /** False on any failure. `journalID` is the record's id: the
     *  `clientRecordId` of both the session and its calories, which is what
     *  makes a second save of the same record replace the first instead of
     *  adding a copy. */
    suspend fun saveWorkout(start: Instant, end: Instant, activeKcal: Double?, journalID: String): Boolean

    companion object {
        /** No Health at all — a store whose test or caller is not about it. */
        val none: WorkoutHealthWriting = object : WorkoutHealthWriting {
            override val isAvailable = false
            override suspend fun requestAuthorization() = false
            override suspend fun workoutShareGranted() = false
            override suspend fun latestBodyMass(): BodyMassReading? = null
            override suspend fun profile() = BodyProfile.unknown
            override suspend fun restingKcal(start: Instant, end: Instant): Double? = null
            override suspend fun foreignWorkoutIntervals(start: Instant, end: Instant) = emptyList<TimeSpan>()
            override suspend fun saveWorkout(start: Instant, end: Instant, activeKcal: Double?, journalID: String) = false
        }

        /**
         * OUR OWN workouts are not a second recording of the session. Without
         * this filter the first export writes a session, the next run finds it
         * overlapping, and the app silently forbids itself energy from then on.
         * Pure, and apart from the query, because it is the trap in this file
         * and a guard that only runs against a real Health Connect never goes
         * red.
         */
        fun foreignIntervals(origins: List<WorkoutOrigin>, excluding: String?): List<TimeSpan> =
            origins.filter { it.packageName != excluding }
                .map { TimeSpan(it.start, maxOf(it.start, it.end)) }
    }
}
