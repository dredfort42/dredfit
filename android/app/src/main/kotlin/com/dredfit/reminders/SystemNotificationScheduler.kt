//
//  The Android half of `NotificationScheduling` — iOS's
//  `UserNotificationScheduler` (NotificationScheduling.swift), which hands a
//  calendar trigger to UNUserNotificationCenter. Here a reminder is an ALARM
//  that fires a receiver, and the receiver posts the notification.
//
//  WHICH ALARM. `setAndAllowWhileIdle` — inexact, and allowed in Doze. The
//  Android page "Schedule alarms" names exactly this call for a "user-
//  specified action that should happen after a specific time (even if system
//  in idle state)"; it never fires early, and on Android 12+ fires within an
//  hour of its time (in practice minutes). An exact alarm would need
//  SCHEDULE_EXACT_ALARM — denied by default from Android 14, revocable,
//  "only if a user-facing function requires precisely-timed actions" — or
//  USE_EXACT_ALARM, which Play keeps for alarm-clock and calendar apps. The
//  iOS reminder promises a training day, not a minute (android/README.md).
//  WorkManager was weighed and left: its work runs when the system batches
//  it, by the app's standby bucket, hours late for a rarely opened app.
//
//  An alarm is an INSTANT and dies with the boot; an iOS calendar trigger is
//  a wall time the system keeps across a reboot and a zone change. So the
//  window is rebuilt on boot, on a clock or zone change and on an update
//  (ReminderReceiver.kt) — from the store, the same rebuild as everywhere.
//

package com.dredfit.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.dredfit.MainActivity
import com.dredfit.R
import com.dredfit.ongoing.NotificationAsk
import com.dredfit.ui.tr
import com.dredfit.workout.Words
import java.io.IOException
import java.time.Instant
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class SystemNotificationScheduler(context: Context) : NotificationScheduling {

    private val app = context.applicationContext
    private val alarms by lazy { app.getSystemService(AlarmManager::class.java) }
    private val manager by lazy { app.getSystemService(NotificationManager::class.java) }

    /** Every alarm call, in the order the store made it. A rebuild is some
     *  sixty binder calls, and it runs on every return to the app: off the
     *  main thread, on ONE thread, so a newer rebuild never lands under an
     *  older one. */
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { Thread(it, "dredfit-reminders") }

    /** Shows the system's question. Set by MainActivity while it exists —
     *  the question needs a screen; main thread only. */
    var ask: (() -> Unit)? = null

    /** Answers waiting for the question on screen. Main thread only. */
    private val waiting = mutableListOf<(Boolean) -> Unit>()

    // MARK: - The permission

    override fun requestAuthorization(answer: (Boolean) -> Unit) {
        val launch = ask
        when (NotificationAsk.reminderStep(Build.VERSION.SDK_INT, allowed(), permissionGranted(), canAsk = launch != null)) {
            NotificationAsk.ReminderStep.allowed -> answer(true)
            NotificationAsk.ReminderStep.refused -> answer(false)
            NotificationAsk.ReminderStep.ask -> {
                waiting += answer
                // One question at a time; a second tap waits for the same one.
                if (waiting.size > 1 || launch == null) return
                try {
                    NotificationAsk.mark(app.noBackupFilesDir).createNewFile()
                } catch (unwritable: IOException) {
                    Log.w(LOG, "the notification ask could not be marked", unwritable)
                }
                launch()
            }
        }
    }

    /** The question was answered — or its screen went away unanswered. Read
     *  from the phone rather than from the dialog's result: a granted
     *  permission over a blocked channel is still a refusal. */
    fun answered() {
        val all = waiting.toList()
        waiting.clear()
        val ok = allowed()
        all.forEach { it(ok) }
    }

    /** Notifications reach the reminder's channel. */
    private fun allowed(): Boolean =
        NotificationManagerCompat.from(app).areNotificationsEnabled() &&
            listOf(ReminderChannel.id(branded = true), ReminderChannel.id(branded = false))
                .mapNotNull { manager.getNotificationChannel(it) }
                .none { it.importance == NotificationManager.IMPORTANCE_NONE }

    private fun permissionGranted(): Boolean =
        Build.VERSION.SDK_INT < NotificationAsk.FIRST_SDK ||
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    // MARK: - The alarms

    override fun removePendingRequests(ids: List<String>) {
        worker.execute {
            for (id in ids) {
                // The lookup ignores extras, so the id alone finds the alarm.
                val pending = PendingIntent.getBroadcast(app, 0, fireIntent(id),
                                                         PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                    ?: continue
                alarms.cancel(pending)
                pending.cancel()
            }
        }
    }

    override fun addReminder(id: String, title: String, body: Words, fireAt: Instant) {
        worker.execute {
            val intent = fireIntent(id).putExtra(EXTRA_TITLE, title).putExtra(EXTRA_BODY, body.key ?: body.format)
            val pending = PendingIntent.getBroadcast(app, 0, intent,
                                                     PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt.toEpochMilli(), pending)
        }
    }

    /** Runs `then` after every alarm call queued so far — a receiver's
     *  `goAsync` finishes only once its rebuild has reached the system. */
    fun afterPending(then: () -> Unit) = worker.execute(then)

    /** One PendingIntent per id: the id rides in the data URI, which is what
     *  tells two alarms apart (`filterEquals`). */
    private fun fireIntent(id: String): Intent =
        Intent(app, ReminderReceiver::class.java).setAction(ACTION_FIRE).setData(Uri.fromParts(URI_SCHEME, id, null))

    // MARK: - The notification

    /** What a fired alarm shows: iOS's title and body, on the reminder's
     *  channel; a tap opens Today. One notification id — a new day's
     *  reminder replaces yesterday's if it is still there. */
    fun post(title: String, bodyKey: String) {
        if (!NotificationManagerCompat.from(app).areNotificationsEnabled()) return
        val channel = ensureChannel()
        val notification = NotificationCompat.Builder(app, channel)
            .setSmallIcon(R.drawable.ic_reminder)
            .setContentTitle(title)
            .setContentText(app.resources.tr(Words.of(bodyKey)))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            // "Today's workout is ready" is nothing to hide on a lock screen,
            // and the iOS banner shows it there.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(openToday())
            .build()
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (revoked: SecurityException) {
            // The permission went between the check and the post.
            Log.w(LOG, "the reminder could not be posted", revoked)
        }
    }

    /**
     * The reminder's channel, created on the way: the branded sound when its
     * file could be written, the system's otherwise (ReminderChannel says why
     * two ids), and any other reminder channel deleted. Recreated each time,
     * so its name follows the app's language — creating an existing channel
     * only renames it; its sound and importance stay the person's.
     */
    fun ensureChannel(): String {
        val sound = ReminderSoundFile.provision(app.filesDir)
        val id = ReminderChannel.id(branded = sound != null)
        for (stale in ReminderChannel.stale(manager.notificationChannels.map { it.id }, id)) {
            manager.deleteNotificationChannel(stale)
        }
        val res = app.resources
        // DEFAULT: a sound and a place in the shade, no heads-up — the
        // importance Android gives a reminder that is not time-critical.
        val channel = NotificationChannel(id, res.tr(Words.of("Reminder")), NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = res.tr(Words.of("On training days only — never on a rest day, and never after you have trained."))
            if (sound != null) {
                val uri = FileProvider.getUriForFile(app, "${app.packageName}.share", sound)
                setSound(uri, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
            }
        }
        manager.createNotificationChannel(channel)
        return id
    }

    /** Today, over whatever the app was showing — but never over a workout
     *  in flight, which covers everything (RootScreen). */
    private fun openToday(): PendingIntent {
        val intent = Intent(app, MainActivity::class.java)
            .setAction(MainActivity.ACTION_OPEN_TODAY)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(app, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** The posted reminder, for the UI suite. */
    internal fun posted(): Notification? = manager.activeNotifications.firstOrNull { it.id == NOTIFICATION_ID }?.notification

    companion object {
        const val ACTION_FIRE = "com.dredfit.reminders.FIRE"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val URI_SCHEME = "dredfit-reminder"
        /** The ongoing notification is 1. */
        const val NOTIFICATION_ID = 2
        private const val LOG = "Reminders"
    }
}
