//
//  Where the plan lands on a calendar: the next training day and the week
//  summary. Read-only. Port of ios/Dredfit/AppStore+Calendar.swift.
//
//  The label the cards show for the next day ("tomorrow", "on Tuesday", the
//  Russian accusative) is words, not calendar: it lives with the screens that
//  say it (ui/today), which hold the strings.
//

package com.dredfit.store

import java.time.DayOfWeek
import java.time.Instant
import java.time.temporal.TemporalAdjusters

/**
 * iOS's `Calendar.component(.weekday, from:)`: 1 = Sunday … 7 = Saturday —
 * the numbering `AppSettings.restWeekdays` is stored in. java.time counts
 * 1 = Monday … 7 = Sunday; this is the one conversion between the two.
 */
fun swiftWeekday(day: DayOfWeek): Int = day.value % 7 + 1

val AppStore.nextTrainingDate: Instant get() = nextTrainingDate(today)

/** The next day the plan trains, from `now`: today when it trains today. */
fun AppStore.nextTrainingDate(from: Instant): Instant {
    var d = from.atZone(zone)
    if (isDone(from) || planRests(from, today)) {
        var hops = 0
        do {
            d = d.plusDays(1)
            hops += 1
        } while (isRestDay(d.toInstant()) && hops < 7)   // toggleRestDay keeps ≥ 1 training day
    }
    return d.toInstant()
}

/** Whether the PLAN rests on this day. Rest is rest FROM something: an
 *  install that has never trained is offered the plan on a marked weekday. */
fun AppStore.restApplies(date: Instant): Boolean = records.isNotEmpty() && isRestDay(date)

/** Seen from `today`: today follows `restApplies`, every other day the
 *  marked weekdays — one rule for the widget's grid and the next date. */
fun AppStore.planRests(day: Instant, today: Instant): Boolean =
    if (sameDay(day, today)) restApplies(day) else isRestDay(day)

val AppStore.restAppliesToday: Boolean get() = restApplies(today)

/** The week is Monday–Sunday regardless of locale. */
data class WeekSummary(val workouts: Int, val stepsDelta: Int)

/** Deload weeks can be negative — that is honest, not an error. A null
 *  `date` is the store's anchor, so callers stay midnight-reactive. */
fun AppStore.weekSummary(date: Instant? = null): WeekSummary {
    val day = localDay(date ?: today, zone)
    val monday = day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val start = monday.atStartOfDay(zone).toInstant()
    val end = monday.plusWeeks(1).atStartOfDay(zone).toInstant()
    val inWeek = records.filter { it.date >= start && it.date < end }
    val last = inWeek.lastOrNull() ?: return WeekSummary(workouts = 0, stepsDelta = 0)
    // Records from before v3 carry no point on this scale: measured from zero.
    val baseline = records.lastOrNull { it.date < start }?.totalProgressAfter ?: 0
    return WeekSummary(workouts = inWeek.size, stepsDelta = (last.totalProgressAfter ?: baseline) - baseline)
}
