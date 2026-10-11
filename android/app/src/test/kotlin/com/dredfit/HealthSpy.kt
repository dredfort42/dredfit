//
//  Port of ios/DredfitTests/HealthSpy.swift: records saved intervals and the
//  calories that rode along, grants or denies on demand, simulates save
//  failures (all, or from a given 1-based call), answers the four reads with
//  whatever a test needs, and can hold one save — or the weight read —
//  mid-flight on a gate, so a test can interleave store changes with a
//  suspended backfill. iOS's `HealthGate` is a `CompletableDeferred<Unit>`.
//

package com.dredfit

import com.dredfit.health.BodyMassReading
import com.dredfit.health.TimeSpan
import com.dredfit.health.WorkoutHealthWriting
import com.dredfit.workout.BodyProfile
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.runBlocking
import java.time.Instant

/** One saved workout as the spy recorded it. */
data class SavedWorkout(val start: Instant, val end: Instant, val kcal: Double?, val journalID: String)

class HealthSpy : WorkoutHealthWriting {
    var available = true
    var grant = true
    /** The workout write as the phone reports it now — taken back in Health
     *  Connect when false. Separate from `grant`, which answers the screen. */
    var shareGranted = true
    var allFail = false
    var failFromCall: Int? = null
    var gate: CompletableDeferred<Unit>? = null
    var gateAtCall: Int? = null
    val saved = mutableListOf<SavedWorkout>()
    var callCount = 0
        private set

    /** What the phone would answer. All four default to "nothing there",
     *  which is also what a refused read looks like to the store. */
    var bodyMassKg: Double? = null
    /** When the scale was stood on; the moment of the read when unset. */
    var bodyMassDate: Instant? = null
    var profile = BodyProfile()
    var basalKcal: Double? = null
    var foreign: List<TimeSpan> = emptyList()
    var foreignQueries = 0
        private set
    val restingQueries = mutableListOf<TimeSpan>()
    /** Counted, and gated, for the reason the Swift spy gives: a test that
     *  cannot see the read cannot tell "not asked" from "asked and ignored". */
    var massQueries = 0
        private set
    var massGate: CompletableDeferred<Unit>? = null

    override val isAvailable: Boolean get() = available

    override suspend fun requestAuthorization(): Boolean = grant

    override suspend fun workoutShareGranted(): Boolean = shareGranted

    override suspend fun latestBodyMass(): BodyMassReading? {
        massQueries += 1
        massGate?.await()
        return bodyMassKg?.let { BodyMassReading(it, bodyMassDate ?: Instant.now()) }
    }

    override suspend fun profile(): BodyProfile = profile

    override suspend fun restingKcal(start: Instant, end: Instant): Double? {
        restingQueries += TimeSpan(start, maxOf(start, end))
        return basalKcal
    }

    /** Answers like the real reader: only what touches the window. */
    override suspend fun foreignWorkoutIntervals(start: Instant, end: Instant): List<TimeSpan> {
        foreignQueries += 1
        val window = TimeSpan(start, maxOf(start, end))
        return foreign.filter { it.overlapSec(window) > 0 }
    }

    override suspend fun saveWorkout(start: Instant, end: Instant, activeKcal: Double?, journalID: String): Boolean {
        callCount += 1
        if (callCount == gateAtCall) gate?.await()
        saved += SavedWorkout(start, end, activeKcal, journalID)
        if (start >= end) return false   // Health Connect rejects such intervals
        if (allFail) return false
        val f = failFromCall
        if (f != null && callCount >= f) return false
        return true
    }
}

/** `async` XCTest methods: the body on this thread's event loop, which is
 *  also where the store's inline `healthScope` resumes. */
fun runHealth(block: suspend CoroutineScope.() -> Unit) {
    runBlocking(block = block)
}
