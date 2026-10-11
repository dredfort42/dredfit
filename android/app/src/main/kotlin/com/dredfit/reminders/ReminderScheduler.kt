//
//  The local reminders: one one-shot per upcoming training day, rebuilt whole
//  on every change. The only place that adds or removes pending reminders;
//  the store only decides when to rebuild and from what. Port of
//  ios/Dredfit/ReminderScheduler.swift — the same window, the same ids, the
//  same two filters (the day's rule, a slot already past).
//
//  Plain Kotlin: the alarms themselves are `NotificationScheduling`'s.
//

package com.dredfit.reminders

import com.dredfit.workout.Words
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

class ReminderScheduler(val notifications: NotificationScheduling) {

    /**
     * Replaces every pending reminder with one per day of the window that
     * `remindsOn` accepts, at `hour:minute` in `zone`. One-shots rather than
     * a daily repeat: a repeating alarm cannot skip a single firing, and
     * "trained this morning" needs exactly that.
     *
     * `remindsOn` is asked about each day's START, as on iOS.
     */
    @Suppress("LongParameterList")
    fun reschedule(enabled: Boolean, hour: Int, minute: Int, now: Instant, zone: ZoneId,
                   remindsOn: (Instant) -> Boolean) {
        notifications.removePendingRequests(ids)
        if (!enabled) return
        val start = now.atZone(zone).toLocalDate()
        for (offset in 0 until WINDOW_DAYS) {
            val date = start.plusDays(offset.toLong())
            if (!remindsOn(date.atStartOfDay(zone).toInstant())) continue
            // The wall time in the zone of THIS moment. A time a spring-forward
            // skips fires as late as the gap (02:30 → 03:30), and a time a
            // fall-back repeats fires at its first occurrence — the first
            // moment the clock shows it, which is when a calendar trigger
            // matching hour and minute fires on iOS.
            val fire = date.atTime(LocalTime.of(hour, minute)).atZone(zone).toInstant()
            // A slot whose time already passed would never fire but would
            // sit in the pending list.
            if (!fire.isAfter(now)) continue
            notifications.addReminder(id = "$DAY_PREFIX$offset", title = TITLE, body = BODY, fireAt = fire)
        }
    }

    /** True only when granted. */
    fun requestAuthorization(answer: (Boolean) -> Unit) = notifications.requestAuthorization(answer)

    companion object {
        /** 28 daily slots: iOS keeps them under its cap of 64 pending
         *  notifications per app, and Android keeps the same window so the
         *  two phones remind on the same days. The accepted price, on both:
         *  reminders run dry if the app is not opened for four weeks
         *  (BACKLOG №8). */
        const val WINDOW_DAYS = 28

        const val DAY_PREFIX = "reminder-day-"

        /** The iOS weekly series of before 1.8 never existed here; the ids
         *  stay in the list so the two ports remove the same set. */
        val ids: List<String> = (1..7).map { "reminder-wd-$it" } + (0 until WINDOW_DAYS).map { "$DAY_PREFIX$it" }

        /**
         * Whether a reminder that fires at `now` still fires on its own day.
         * The alarm is inexact — up to an hour late (SystemNotificationScheduler)
         * — and iOS's never is: a 23:30 slot posted at 00:20 would say
         * "Today's workout is ready" on the next day, a rest day perhaps.
         * Such a reminder is dropped; the new day has its own slot, if any.
         */
        fun stillItsDay(fireAt: Instant, now: Instant, zone: ZoneId): Boolean =
            fireAt.atZone(zone).toLocalDate() == now.atZone(zone).toLocalDate()

        const val TITLE = "Dredfit"
        val BODY: Words = Words.of("Today's workout is ready")
    }
}
