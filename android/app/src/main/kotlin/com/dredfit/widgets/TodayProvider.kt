//
//  The widget's timeline: one entry per snapshot day. Port of
//  ios/DredfitWidgets/TodayProvider.swift. Plain Kotlin — a JVM unit test
//  pins the mapping and the day it picks.
//
//  iOS hands WidgetKit a timeline of entries stamped at each midnight and the
//  system switches them on its own. Android has no such engine: the widget
//  is redrawn by the app, so the timeline becomes a choice made at render —
//  `entry(snapshot, today)` takes the entry of the day on the wall — and a
//  redraw booked at the next local midnight (`nextMidnight`, scheduled by
//  WidgetCenter.kt) stands in for WidgetKit's switch.
//

package com.dredfit.widgets

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/** What the widget draws for one day — iOS's `TodayEntry`. */
data class TodayEntry(
    val date: LocalDate,
    val status: WidgetSnapshot.DayStatus?,
    val sessionNumber: Int?,
    /** The Monday–Sunday around `date`, past days included. */
    val week: List<WidgetSnapshot.Day>,
    val totalSteps: Int?,
    /** The tally, only inside the week it was written in. */
    val summary: WidgetSnapshot.Week?,
    val nextDate: LocalDate?,
    val planSessionNumber: Int?,
    val plan: List<WidgetSnapshot.PlanRow>,
) {
    companion object {
        /** No snapshot, or none left for today: the widget signs itself
         *  rather than guessing. */
        fun empty(date: LocalDate): TodayEntry =
            TodayEntry(date = date, status = null, sessionNumber = null, week = emptyList(), totalSteps = null,
                       summary = null, nextDate = null, planSessionNumber = null, plan = emptyList())
    }
}

object TodayProvider {

    /** One entry per snapshot day from `today` on; past days are dropped from
     *  the timeline but stay in each entry's week strip. */
    fun entries(snapshot: WidgetSnapshot?, today: LocalDate): List<TodayEntry> {
        snapshot ?: return emptyList()
        return snapshot.days.filter { it.date >= today }.map { day ->
            // Monday-first, as the store writes it.
            val monday = day.date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            val sunday = monday.plusDays(6)
            TodayEntry(
                date = day.date,
                status = day.status,
                sessionNumber = day.sessionNumber,
                week = snapshot.days.filter { it.date >= monday && it.date <= sunday },
                totalSteps = snapshot.totalSteps,
                // The tally travels only with the week it was written in:
                // last week's numbers must not read as "This week".
                summary = if (snapshot.weekStart == monday) snapshot.week else null,
                nextDate = day.nextDate,
                planSessionNumber = snapshot.planSessionNumber,
                plan = snapshot.plan,
            )
        }
    }

    /** What the widget draws on `today`: the first entry from today on —
     *  the one WidgetKit would be showing — or the signed blank when the
     *  snapshot has run out (two weeks without the app) or is missing. */
    fun entry(snapshot: WidgetSnapshot?, today: LocalDate): TodayEntry =
        entries(snapshot, today).firstOrNull() ?: TodayEntry.empty(today)

    /** When the next redraw is due: the start of tomorrow on the wall of
     *  `zone` — iOS's `nextReload`, which is always a midnight here, because
     *  no system switches entries without the app. Strictly after `now`:
     *  a time in the past would fire at once and book itself again. */
    fun nextMidnight(now: Instant, zone: ZoneId): Instant =
        now.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
}
