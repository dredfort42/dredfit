//
//  The two receivers of the reminder. No Swift twin: on iOS the system posts
//  a calendar notification itself and keeps it across a reboot or a zone
//  change. Here an alarm fires `ReminderReceiver`, which posts; and what an
//  alarm loses — every alarm on a reboot, the wall time on a zone change —
//  `ReminderRescheduleReceiver` rebuilds from the store, exactly as the app
//  does on every return (`rescheduleReminders`): idempotent, so a second
//  broadcast, or one with the reminder off, changes nothing.
//

package com.dredfit.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.dredfit.DredfitApp
import com.dredfit.store.rescheduleReminders

/** What rebuilds the window, beside the app's own returns. Plain, so a JVM
 *  test holds the manifest's intent filter to it (ReminderTriggerTest). */
object ReminderTriggers {
    val actions: Set<String> = setOf(
        // Alarms do not survive a reboot. Delivered after the first unlock,
        // when the state file can be read.
        "android.intent.action.BOOT_COMPLETED",
        // An alarm is an instant: a new clock or zone moves 09:00 elsewhere.
        "android.intent.action.TIME_SET",
        "android.intent.action.TIMEZONE_CHANGED",
        // An update that came while the app was closed: the window the new
        // build would draw, without waiting for the next open.
        "android.intent.action.MY_PACKAGE_REPLACED",
    )

    fun reschedules(action: String?): Boolean = action in actions
}

/** A reminder's alarm went off: post it. Not exported — only the app's own
 *  PendingIntent reaches it. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != SystemNotificationScheduler.ACTION_FIRE) return
        val app = context.applicationContext as DredfitApp
        app.reminders.post(title = intent.getStringExtra(SystemNotificationScheduler.EXTRA_TITLE) ?: ReminderScheduler.TITLE,
                           bodyKey = intent.getStringExtra(SystemNotificationScheduler.EXTRA_BODY)
                               ?: ReminderScheduler.BODY.format)
    }
}

/** Exported, because the system's broadcasts are what it listens for; any
 *  other action is ignored, and the rebuild is harmless anyway. */
class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!ReminderTriggers.reschedules(intent.action)) return
        val app = context.applicationContext as DredfitApp
        val pending = goAsync()
        // The store loads off the main thread (DredfitApp); the rebuild runs
        // once it is here, and the broadcast ends once the alarms are set.
        app.withStore { store ->
            store.act { rescheduleReminders() }
            app.reminders.afterPending { pending.finish() }
        }
    }
}
