//
//  When the reminders are rebuilt and from what: the settings and the journal.
//  The window itself is ReminderScheduler's. Port of
//  ios/Dredfit/AppStore+Reminders.swift.
//

package com.dredfit.store

import com.dredfit.reminders.ReminderScheduler
import java.time.Instant

val AppStore.reminderScheduler: ReminderScheduler get() = ReminderScheduler(notifications)

/** Rebuilt from scratch on every settings change, activation and
 *  completion — and on Android after a reboot, a clock or zone change and an
 *  update too (reminders/ReminderReceiver.kt), because an alarm is an
 *  instant and dies with the boot, where an iOS calendar trigger is a wall
 *  time the system keeps. A day that is a rest day, or already trained, gets
 *  none. */
fun AppStore.rescheduleReminders(now: Instant = clock.instant()) {
    // A frozen launch knows neither the settings nor the journal: leave what
    // the system holds rather than clearing a window the user expects.
    if (journalFrozen) return
    reminderScheduler.reschedule(enabled = settings.reminderEnabled,
                                 hour = settings.reminderHour,
                                 minute = settings.reminderMinute,
                                 now = now,
                                 zone = zone,
                                 remindsOn = { !isRestDay(it) && !isDone(it) })
}
