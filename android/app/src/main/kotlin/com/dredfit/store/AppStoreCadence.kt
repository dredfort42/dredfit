//
//  The trainee's own rhythm and the training day (#134, #147). A steady cadence
//  is not a break: when a new gap lands within ±1 day of any of the last eight
//  gaps, the silent decay and the comeback card both stand down. Read-only.
//  Port of ios/Dredfit/AppStore+Cadence.swift.
//

package com.dredfit.store

import com.dredfit.core.EngineConfig
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs

/** The calendar day an instant falls on in `zone` — iOS's `startOfDay`. */
fun localDay(instant: Instant, zone: ZoneId): LocalDate = instant.atZone(zone).toLocalDate()

/**
 * CALENDAR days in the trainee's zone — the number of midnights between the
 * two instants, not whole 24-hour periods: Monday 23:00 → Tuesday 01:00 is
 * one day, and a DST day of 23 or 25 hours is still one. Clamped at zero (a
 * zone change or a clock set backwards) and at countMax (a corrupt date).
 * Static on iOS so tests can pin a zone that has DST; the zone is a parameter
 * here for the same reason.
 */
fun trainingDays(from: Instant, to: Instant, zone: ZoneId): Int {
    val days = ChronoUnit.DAYS.between(localDay(from, zone), localDay(to, zone))
    return days.coerceIn(0L, EngineConfig.countMax.toLong()).toInt()
}

/** Whether two instants fall on the same calendar day in the store's zone. */
fun AppStore.sameDay(a: Instant, b: Instant): Boolean = localDay(a, zone) == localDay(b, zone)

/** Training days since the last workout — the gap the engine's break
 *  functions read. Null while the journal is empty. Measured to the real
 *  clock, not the `today` anchor. */
fun AppStore.gapDays(now: Instant = clock.instant()): Int? {
    val last = records.lastOrNull() ?: return null
    return trainingDays(last.date, now, zone)
}

/** The same elapsed time, NOT floored — the fraction of a day the engine's
 *  weekly window needs, and nothing else reads it. */
fun AppStore.gapFraction(now: Instant = clock.instant()): Double? {
    val last = records.lastOrNull() ?: return null
    val elapsed = Duration.between(last.date, now)
    val days = (elapsed.seconds + elapsed.nano / 1e9) / 86_400
    if (!days.isFinite()) return 0.0
    return days.coerceIn(0.0, EngineConfig.countMax.toDouble())
}

/** The last up-to-eight gaps between consecutive journal entries. Eight, not
 *  three: a life cycle repeats over more than three sessions. */
val AppStore.recentGaps: List<Int>
    get() {
        val dates = records.takeLast(9).map { it.date }
        if (dates.size < 2) return emptyList()
        return dates.zipWithNext { a, b -> trainingDays(a, b, zone) }
    }

/**
 * A break is the trainee's own rhythm when it lands within ±1 day of any of
 * the last eight gaps — no upper cap. The second clause covers a mid-cycle
 * open: a silence that has not yet outgrown a REPEATING gap is no break
 * either, so one long vacation does not shield the next absence.
 */
fun AppStore.isRhythmBreak(gap: Int): Boolean {
    val gaps = recentGaps
    if (gaps.any { abs(it - gap) <= 1 }) return true
    val rhythmic = gaps.indices.filter { i ->
        gaps.indices.any { j -> j != i && abs(gaps[j] - gaps[i]) <= 1 }
    }.map { gaps[it] }
    val ceiling = rhythmic.maxOrNull() ?: return false
    return gap <= ceiling + 1
}
