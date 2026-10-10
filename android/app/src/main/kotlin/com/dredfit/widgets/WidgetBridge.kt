//
//  After every persisted change the store rebuilds the two-week snapshot and
//  hands it to the widget; the widget never computes rest days itself. Port
//  of ios/Dredfit/WidgetBridge.swift. Plain Kotlin, like the store: what the
//  snapshot says is decided here and read by a JVM unit test.
//
//  iOS writes the file and pokes WidgetKit inside `refreshWidgetSnapshot`.
//  Here both halves are behind `WidgetPublishing`, because the disk is off
//  the main thread and Glance is Android: the app's `WidgetCenter`
//  (WidgetCenter.kt) writes the file on the disk thread and redraws, a unit
//  test records what it was handed.
//

package com.dredfit.widgets

import com.dredfit.store.AppStore
import com.dredfit.store.localDay
import com.dredfit.store.nextSession
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.planRests
import com.dredfit.store.totalProgress
import com.dredfit.store.weekSummary
import com.dredfit.workout.Words
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

/** Where a snapshot goes once the store has made it. Called on the store's
 *  thread — the main thread, or the disk thread for the read at launch. */
fun interface WidgetPublishing {
    fun publish(snapshot: WidgetSnapshot)

    companion object {
        /** A store whose test is not about the widget — iOS's
         *  `widgetSnapshotURL: nil`. */
        val none = WidgetPublishing { }
    }
}

fun AppStore.refreshWidgetSnapshot(now: Instant = clock.instant()) {
    // A frozen launch knows nothing about the person: publishing that
    // emptiness would put "nothing done" over a perfectly fine history.
    if (journalFrozen) return
    widgets.publish(widgetSnapshot(now))
}

/** Two weeks from the Monday of `now`'s week, Monday-first like the
 *  Calendar tab: starting on Monday rather than today is what lets an entry
 *  days ahead draw its own week. */
fun AppStore.widgetSnapshot(now: Instant): WidgetSnapshot {
    val today = localDay(now, zone)
    val todayAt = today.atStartOfDay(zone).toInstant()
    val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    // Not cheap — resolved once rather than per day.
    val next = nextSession
    // The days anything was recorded on, once: iOS asks `record(on:)` per
    // day, a scan of the whole journal fourteen times.
    val recorded = records.mapTo(HashSet()) { localDay(it.date, zone) }
    val days = (0L until DAYS).map { offset ->
        val day = monday.plusDays(offset)
        val at = day.atStartOfDay(zone).toInstant()
        val status = widgetStatus(day, at, today, todayAt, recorded)
        WidgetSnapshot.Day(
            date = day,
            status = status,
            sessionNumber = if (day == today && status == WidgetSnapshot.DayStatus.workout) next.sessionNumber else null,
            // From the entry's own day, not from this write: a rest-day entry
            // shown days from now must not say a stale "today".
            nextDate = if (day >= today && status != WidgetSnapshot.DayStatus.workout) {
                localDay(nextTrainingDate(at), zone)
            } else null)
    }
    val summary = weekSummary(todayAt)
    return WidgetSnapshot(
        days = days,
        totalSteps = totalProgress,
        week = WidgetSnapshot.Week(workouts = summary.workouts, stepsDelta = summary.stepsDelta),
        weekStart = monday,
        planSessionNumber = next.sessionNumber,
        plan = next.exercises.map { WidgetSnapshot.PlanRow(it.name, Words.head(it), it.unit, it.perSide) },
    )
}

/** Past days come from the journal, not `isDone`, which only ever knows the
 *  latest record. A missed training day stays UNMARKED — the Calendar leaves
 *  those unshamed and the widget follows. TODAY follows `restApplies`, the
 *  rest of the grid the marked weekdays (`planRests`): a fresh install whose
 *  onboarding ended on a marked weekday is offered the plan on Today, and
 *  the widget must not tell that person "Rest day". */
private fun AppStore.widgetStatus(day: LocalDate, at: Instant, today: LocalDate, todayAt: Instant,
                                  recorded: Set<LocalDate>): WidgetSnapshot.DayStatus = when {
    day in recorded -> WidgetSnapshot.DayStatus.done
    planRests(at, todayAt) -> WidgetSnapshot.DayStatus.rest
    day < today -> WidgetSnapshot.DayStatus.unmarked
    else -> WidgetSnapshot.DayStatus.workout
}

/** Two weeks: the write week and the next, so the widget has a day of its
 *  own to show for at least a week without the app. */
private const val DAYS = 14L
