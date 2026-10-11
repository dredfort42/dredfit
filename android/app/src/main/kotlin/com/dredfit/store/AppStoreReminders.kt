//
//  When the reminders are rebuilt and from what: the settings and the journal.
//  The window itself is ReminderScheduler's. Port of
//  ios/Dredfit/AppStore+Reminders.swift.
//

package com.dredfit.store

import com.dredfit.reminders.ReminderScheduler
import java.io.File
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

/**
 * After Android's own restore (auto backup, `allowBackup`) the state file
 * comes back with `reminderEnabled` as it was on the old phone, and the
 * notification permission may not: the re-check an import makes, made on
 * the first launch on this device (owner decision, 09.10.2026) — it asks
 * where it can, and a refusal flips the switch off with the denied note.
 * Never a switched-on reminder that cannot post.
 *
 * @return whether the check ran: not on a frozen journal, whose settings are
 *   the empty state's, so the next return tries again.
 */
fun AppStore.recheckRemindersOnANewDevice(): Boolean {
    if (journalFrozen) return false
    if (settings.reminderEnabled) setReminderEnabled(true)
    return true
}

/**
 * The mark that this device has run the state before: a file in
 * `noBackupFilesDir`, which a backup never carries, so a state file with no
 * mark beside it came from a restore (or from a build before the mark —
 * checking that once is harmless). The pattern of the notification ask's
 * mark (`NotificationAsk.mark`). Chosen over a BackupAgent's
 * `onRestoreFinished`: a restore runs the agent in a process without the
 * app's Application, and a custom agent replaces auto backup's own.
 */
object DeviceMark {
    fun file(noBackupFilesDir: File): File = File(noBackupFilesDir, "state-seen-here")
}
