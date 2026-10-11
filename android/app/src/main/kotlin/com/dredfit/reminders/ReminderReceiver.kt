//
//  The two receivers of the reminder. No Swift twin: on iOS the system posts
//  a calendar notification itself and keeps it across a reboot or a zone
//  change. Here an alarm fires `ReminderReceiver`, which posts; and what an
//  alarm loses — every alarm on a reboot, the wall time on a zone change —
//  `ReminderRescheduleReceiver` rebuilds from the store, exactly as the app
//  does on every return (`rescheduleReminders`): idempotent, so a second
//  broadcast, or one with the reminder off, changes nothing. The home-screen
//  widget rides the same broadcasts (widgets/WidgetCenter.kt): its snapshot
//  and its midnight are lost or moved by the same events.
//

package com.dredfit.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.dredfit.DredfitApp
import com.dredfit.store.rescheduleReminders
import com.dredfit.widgets.refreshWidgetSnapshot
import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone

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
        val at = intent.getLongExtra(SystemNotificationScheduler.EXTRA_AT, -1)
        if (at >= 0 && !ReminderScheduler.stillItsDay(Instant.ofEpochMilli(at), Instant.now(), ZoneId.systemDefault())) return
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
        // The system tells a running process about a new zone on a path of its
        // own (a one-way call that drops the cached zone), with nothing
        // ordering it against this broadcast; a rebuild that read the stale
        // cache would put 09:00 on the OLD wall. On API 37 the call arrived
        // first (the mutant without this line stayed green, 09.10.2026), so
        // this only makes the order certain: the next read is the system's
        // current zone, as the process is about to be told.
        if (intent.action == Intent.ACTION_TIMEZONE_CHANGED) TimeZone.setDefault(null)
        val app = context.applicationContext as DredfitApp
        val pending = goAsync()
        // The store loads off the main thread (DredfitApp); the rebuild runs
        // once it is here, and the broadcast ends once the alarms are set.
        app.withStore { store ->
            store.act {
                rescheduleReminders()
                // The widget loses the same things: its snapshot was written
                // in the old zone or by the old build, and its midnight alarm
                // is an instant that a reboot drops and a new wall moves.
                refreshWidgetSnapshot()
            }
            app.widgets.refresh()
            app.reminders.afterPending { pending.finish() }
        }
    }
}
