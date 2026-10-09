//
//  The device half of the reminder suites: which alarms the app and the
//  system hold, the posted reminder, the store on the main thread. Shared by
//  ReminderTest (permission granted, in the suite) and ReminderDeniedTest
//  (a fresh install, alone).
//

package com.dredfit

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import com.dredfit.reminders.ReminderReceiver
import com.dredfit.reminders.ReminderScheduler
import com.dredfit.reminders.SystemNotificationScheduler
import com.dredfit.store.AppStore
import com.dredfit.ui.Observed
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

abstract class ReminderTestCase : OngoingTestCase() {

    /** The alarm's own PendingIntent for `id`, if the app holds one — what
     *  `removePendingRequests` finds and cancels. */
    protected fun pendingIntent(id: String): PendingIntent? = PendingIntent.getBroadcast(
        app, 0,
        Intent(app, ReminderReceiver::class.java).setAction(SystemNotificationScheduler.ACTION_FIRE)
            .setData(Uri.fromParts(SystemNotificationScheduler.URI_SCHEME, id, null)),
        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)

    /** The reminder ids with an alarm behind them, once every queued alarm
     *  call has reached the system. */
    protected fun pendingIds(): List<String> {
        settleAlarms()
        return ReminderScheduler.ids.filter { pendingIntent(it) != null }
    }

    /** The reminder alarms the SYSTEM holds for the app, read off `dumpsys
     *  alarm` — the other side of `pendingIds`: each is an `RTC_WAKEUP #n:
     *  Alarm{id type 0 … com.dredfit.dredfit}` whose next line is its tag.
     *  The dump lists a pending alarm twice (summary and detail), hence the
     *  distinct ids. */
    protected fun systemAlarms(): Set<String> {
        settleAlarms()
        val lines = shell("dumpsys alarm").lines()
        val head = Regex("""RTC_WAKEUP #\d+: Alarm\{(\w+) type 0 .* ${app.packageName}\}""")
        return lines.indices.mapNotNull { i ->
            val id = head.find(lines[i])?.groupValues?.get(1) ?: return@mapNotNull null
            id.takeIf { lines.getOrNull(i + 1)?.contains("tag=*walarm*:${SystemNotificationScheduler.ACTION_FIRE}") == true }
        }.toSet()
    }

    /** The window the system gives one of them (`window=+1h0m0s0ms`). */
    protected fun systemAlarmWindow(): String? =
        Regex("""tag=\*walarm\*:${Regex.escape(SystemNotificationScheduler.ACTION_FIRE)}\n\s+type=RTC_WAKEUP origWhen=\S+ \S+ window=(\S+)""")
            .find(shell("dumpsys alarm"))?.groupValues?.get(1)

    /** Waits for the reminders' worker to run everything queued so far. */
    protected fun settleAlarms() {
        val done = CountDownLatch(1)
        app.reminders.afterPending { done.countDown() }
        check(done.await(10, TimeUnit.SECONDS)) { "the reminder worker never drained" }
    }

    /** The slots a window at `hour:minute` holds from now with every day a
     *  training day (the suite's seeds clear the rest days). */
    protected fun expectedSlots(hour: Int, minute: Int, zone: ZoneId = ZoneId.systemDefault()): Int {
        val now = ZonedDateTime.now(zone)
        return (0 until ReminderScheduler.WINDOW_DAYS).count {
            LocalDate.now(zone).plusDays(it.toLong()).atTime(hour, minute).atZone(zone).isAfter(now)
        }
    }

    /** Runs `change` on the store, on the main thread, as a tap does. */
    protected fun onStore(change: AppStore.() -> Unit) {
        val done = CountDownLatch(1)
        instrumentation.runOnMainSync {
            app.withStore { observed: Observed<AppStore> ->
                observed.act(change)
                done.countDown()
            }
        }
        check(done.await(10, TimeUnit.SECONDS)) { "the store never loaded" }
    }

    protected fun <T> readStore(read: AppStore.() -> T): T {
        var value: T? = null
        onStore { value = read() }
        @Suppress("UNCHECKED_CAST")
        return value as T
    }

    /** The posted reminder, if any. */
    protected fun reminder(): Notification? =
        app.getSystemService(NotificationManager::class.java).activeNotifications
            .firstOrNull { it.id == SystemNotificationScheduler.NOTIFICATION_ID }?.notification

    protected fun clearReminders() {
        app.getSystemService(NotificationManager::class.java).cancel(SystemNotificationScheduler.NOTIFICATION_ID)
        app.reminders.removePendingRequests(ReminderScheduler.ids)
        settleAlarms()
    }
}
