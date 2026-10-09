//
//  The ongoing-workout notification — Android's counterpart of the iOS Live
//  Activity (ios/DredfitWidgets/RestLiveActivity.swift draws the tile there;
//  workout/RestLiveActivity.kt decides what it shows, this draws it) — and
//  the foreground service that carries it.
//
//  WHY A FOREGROUND SERVICE. Without one, a backgrounded app is cached and,
//  from Android 14, frozen within seconds: the beat stops and a 3-2-1 never
//  sounds. The service keeps the process in front for exactly the time the
//  tile is up. Its type is `health` — "long-running use cases to support apps
//  in the fitness category such as exercise trackers"; android/README.md
//  weighs it against the other types.
//
//  The CPU is the second half (workout/WorkoutBeat.kt): a partial wake lock
//  held only while a countdown runs, and never while the service is down.
//

package com.dredfit.ongoing

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.dredfit.DredfitApp
import com.dredfit.MainActivity
import com.dredfit.R
import com.dredfit.ui.tr
import com.dredfit.workout.OngoingContent
import com.dredfit.workout.OngoingHost
import com.dredfit.workout.Words

/** The process's one ongoing notification. Main thread only, like the flow
 *  that drives it. */
class OngoingNotification(context: Context) : OngoingHost {

    private val app = context.applicationContext
    private val manager by lazy { app.getSystemService(NotificationManager::class.java) }
    private val wakeLock by lazy {
        app.getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            .apply { setReferenceCounted(false) }
    }

    /** The service is wanted: shown and not yet hidden or refused. */
    override var isUp: Boolean = false
        private set

    /** What the service shows — read by it when it comes up. */
    internal var notification: Notification? = null
        private set

    /** The running service, once it is in the foreground. */
    private var service: OngoingWorkoutService? = null

    /** The CPU is held for a countdown (the UI suite reads it). */
    val isAwake: Boolean get() = wakeLock.isHeld

    override fun show(content: OngoingContent) {
        if (!isUp) createChannel()
        val drawn = build(content)
        notification = drawn
        if (isUp) {
            // Up or on its way: a running service redraws now, a pending one
            // takes the latest drawing when it starts.
            if (service != null) manager.notify(NOTIFICATION_ID, drawn)
            return
        }
        isUp = true
        try {
            app.startForegroundService(Intent(app, OngoingWorkoutService::class.java))
        } catch (refused: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException is one: the app was
            // not in front after all. The workout goes on without the tile.
            Log.w(LOG, "the ongoing notification was refused", refused)
            isUp = false
        }
    }

    override fun hide() {
        isUp = false
        // A service still on its way stops itself once it is in the
        // foreground (`onStartCommand`): stopping it earlier would break the
        // promise `startForegroundService` made, and the system crashes an
        // app for that.
        service?.retire()
    }

    override fun keepAwake(awake: Boolean) {
        if (awake && isUp) {
            wakeLock.acquire(WAKE_LOCK_TIMEOUT_MS)
        } else if (wakeLock.isHeld) {
            wakeLock.release()
        }
    }

    internal fun attach(running: OngoingWorkoutService) {
        service = running
    }

    /** `retired`: stopped by `hide`, which already let everything go — and
     *  a `show` since then may have asked for the next service already. */
    internal fun detach(stopped: OngoingWorkoutService, retired: Boolean) {
        if (service === stopped) service = null
        if (retired) return
        // Stopped by anything else (the system): nothing is up any more, and
        // nothing may stay held.
        isUp = false
        keepAwake(false)
    }

    /** The service could not go foreground: as if it had never been asked. */
    internal fun refused() {
        isUp = false
        keepAwake(false)
    }

    /** Recreated on every start, so the channel's name follows the app's
     *  language; creating an existing channel only renames it. LOW: the
     *  tones are the app's own, and the notification itself never sounds. */
    private fun createChannel() {
        val name = app.resources.tr(Words.of("Workout in progress"))
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
    }

    private fun build(content: OngoingContent): Notification {
        val res = app.resources
        val builder = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_ongoing_workout)
            // iOS's tile: the bold line is the title, the small one the detail.
            .setContentTitle(res.tr(content.title))
            .setContentText(content.detail?.let { res.tr(it) })
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            // The Live Activity is a lock-screen tile: an exercise name is
            // nothing to hide there.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            // Android 12 may hold a new service's notification back ten
            // seconds; a workout's tile is wanted at once.
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openTheFlow())
        val end = content.countdownTo
        if (end != null) {
            // The system ticks the countdown itself, as `Text(timerInterval:)`
            // does on iOS: no update a second.
            builder.setWhen(end.toEpochMilli()).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
        }
        return builder.build()
    }

    /** A tap opens the app where it is — the launcher's own intent, so an
     *  existing task comes forward instead of a second activity; the flow is
     *  the process's, and the root draws it over everything. No actions: the
     *  iOS tile has none. */
    private fun openTheFlow(): PendingIntent {
        val intent = Intent(app, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return PendingIntent.getActivity(app, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    companion object {
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "workout"
        const val WAKE_LOCK_TAG = "dredfit:countdown"
        /** A backstop, never the release: every countdown run ends in a tap
         *  long before an hour (the longest is a rest capped at twice its
         *  plan), and the beat releases the lock the second it does. */
        const val WAKE_LOCK_TIMEOUT_MS = 60L * 60 * 1000
        private const val LOG = "OngoingNotification"
    }
}

/**
 * Holds the process in front while the tile is up, and nothing else: the
 * beat, the flow and the wake lock are the process's. Not sticky — after a
 * process death the snapshot and Today's "Continue the workout?" bring the
 * workout back, and a service restarted on its own would show a tile for a
 * flow that no longer exists.
 */
class OngoingWorkoutService : Service() {

    private val host get() = (application as DredfitApp).ongoing

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val drawn = host.notification
        if (drawn == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            ServiceCompat.startForeground(this, OngoingNotification.NOTIFICATION_ID, drawn,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH else 0)
        } catch (refused: RuntimeException) {
            // SecurityException for a missing prerequisite, or the start
            // window closed: no tile, the flow goes on.
            Log.w("OngoingWorkoutService", "could not go foreground", refused)
            host.refused()
            stopSelf()
            return START_NOT_STICKY
        }
        host.attach(this)
        // Hidden while on its way: in the foreground now, so it may go.
        if (!host.isUp) retire()
        return START_NOT_STICKY
    }

    private var retired = false

    fun retire() {
        retired = true
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        host.detach(this, retired)
        super.onDestroy()
    }
}
