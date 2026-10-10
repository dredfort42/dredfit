//
//  Where the store's snapshot reaches the widget: iOS's App Group file and
//  `WidgetCenter.shared.reloadAllTimelines()`, plus the one thing WidgetKit
//  does on its own that Android does not — switching to the next day's entry
//  at midnight. No Swift twin as a file; android/README.md ("The home-screen
//  widget") says why each choice below.
//
//  - The FEED is what every widget session draws from: the newest snapshot
//    this process knows and the day on the wall. A Glance session lives for
//    ~45 s after its first frame and does not run `provideGlance` again on
//    an update, so a second write inside that window would leave it drawing
//    the first one — the session collects the feed instead, and a change to
//    it redraws whatever session is alive.
//  - The FILE (`noBackupFilesDir`) is for a process that has not published
//    yet: a widget the system redraws after a reboot, an update or a process
//    death, before the store has loaded. Written whole, synced, through a
//    rename.
//  - The REDRAW of widgets with no live session goes through the receiver's
//    own update broadcast, which holds the process with `goAsync` for as long
//    as Glance needs; a coroutine of the app's would be frozen with a cached
//    process. Skipped when nothing the widget shows changed: most writes
//    (a plan shown, a setting) leave the snapshot as it was, and a fresh
//    process's first write usually says what the file already says.
//  - MIDNIGHT is an inexact, non-wakeup alarm (`setWindow`, RTC) at the next
//    local midnight, booked while a widget exists: it wakes nothing, and a
//    phone asleep at midnight redraws when it next wakes — the moment the
//    widget can be seen again. A clock or zone change re-books it
//    (ReminderReceiver.kt's broadcasts).
//  - A device with no widget service (`android.software.app_widgets` absent:
//    TV, Automotive, some ARC builds) has `AppWidgetManager.getInstance` =
//    null. Nothing is written or drawn there, as iOS's `snapshotURL` nil
//    degrades rather than unwraps.
//

package com.dredfit.widgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.glance.appwidget.GlanceAppWidgetManager
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.getAndUpdate
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

class WidgetCenter(
    private val app: Context,
    private val disk: Executor,
    /** The day on the wall — a test's own, to see the drawn day move. */
    private val today: () -> LocalDate = LocalDate::now,
) : WidgetPublishing {

    /** `read`: whether `snapshot` is this process's word on it — published
     *  here, or read from the file — rather than the unread start.
     *  `redraws` counts the refreshes, so a live session redraws even when
     *  the day did not change (a new language, contrast or zone). */
    data class Feed(val snapshot: WidgetSnapshot?, val today: LocalDate, val read: Boolean, val redraws: Int = 0)

    private val feedState = MutableStateFlow(Feed(snapshot = null, today = today(), read = false))
    val feed: StateFlow<Feed> get() = feedState

    private val file: File get() = File(app.noBackupFilesDir, WidgetSnapshot.FILE_NAME)

    private val receiver: ComponentName get() = ComponentName(app, TodayStatusWidgetReceiver::class.java)

    /** Null where the system has no widget service (see the header). */
    private val manager: AppWidgetManager? by lazy { AppWidgetManager.getInstance(app) }

    /** Once per process, on the first snapshot that changes anything
     *  (Android 15+). */
    private val previewSet = AtomicBoolean(false)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default +
        CoroutineExceptionHandler { _, e -> Log.w(TAG, "widget preview failed", e) })

    override fun publish(snapshot: WidgetSnapshot) {
        val before = feedState.getAndUpdate { it.copy(snapshot = snapshot, today = today(), read = true) }
        if (manager == null) return
        if (before.read && before.snapshot == snapshot) return
        val bytes = snapshot.encode().toByteArray(Charsets.UTF_8)
        disk.execute {
            // A fresh process's first word is mostly the file's again — the
            // widget already shows it, so neither a write nor a redraw.
            if (!before.read && read() == snapshot) return@execute
            write(bytes)
            redraw()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM && previewSet.compareAndSet(false, true)) {
                scope.launch { setPreview() }
            }
        }
    }

    /** Before a session draws: the file, when this process has published
     *  nothing yet, and the day on the wall. A publish that lands meanwhile
     *  wins over the file. Off the main thread (Glance's worker). */
    fun prepare() {
        if (!feedState.value.read) {
            val stored = read()
            feedState.update { if (it.read) it else it.copy(snapshot = stored, read = true) }
        }
        feedState.update { it.copy(today = today()) }
    }

    /** A new day on the wall — midnight, a clock or a zone change — or a new
     *  language or contrast: the same snapshot, drawn for the day and the
     *  words of now. On the caller's thread, so a receiver has sent the
     *  redraw before it returns. */
    fun refresh() {
        feedState.update { it.copy(today = today(), redraws = it.redraws + 1) }
        redraw()
    }

    /** Every placed widget redrawn — the receiver's update then books the
     *  next midnight — or the midnight unbooked when no widget is left. */
    private fun redraw() {
        val ids = manager?.getAppWidgetIds(receiver) ?: return
        if (ids.isEmpty()) return cancelMidnight()
        app.sendBroadcast(Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                              .setComponent(receiver)
                              .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
    }

    fun bookMidnight() {
        val at = TodayProvider.nextMidnight(Instant.now(), ZoneId.systemDefault())
        alarms().setWindow(AlarmManager.RTC, at.toEpochMilli(), MIDNIGHT_WINDOW_MS, midnight())
    }

    fun cancelMidnight() {
        alarms().cancel(midnight())
    }

    private fun alarms(): AlarmManager = app.getSystemService(AlarmManager::class.java)

    private fun midnight(): PendingIntent =
        PendingIntent.getBroadcast(app, 0, Intent(app, TodayStatusWidgetReceiver::class.java).setAction(ACTION_MIDNIGHT),
                                   PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    /** On `disk`, in the order the snapshots were published. Synced before
     *  the rename, as the state file is: a power cut must not leave an empty
     *  file under the old name's place. */
    private fun write(bytes: ByteArray) {
        try {
            val temp = File(app.noBackupFilesDir, "${WidgetSnapshot.FILE_NAME}.tmp")
            FileOutputStream(temp).use { out ->
                out.write(bytes)
                out.fd.sync()
            }
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: IOException) {
            // The feed already has it: only a process started later reads the
            // file, and it would draw the previous snapshot.
            Log.w(TAG, "widget snapshot not written", e)
        }
    }

    private fun read(): WidgetSnapshot? = try {
        WidgetSnapshot.decode(file.readText(Charsets.UTF_8))
    } catch (_: IOException) {
        // Absent before the first write: the widget signs itself.
        null
    }

    /** The picker's preview is the person's own day, as iOS's gallery shows
     *  it — set once per process because the system allows about two an
     *  hour; a refused one leaves the previous preview standing. */
    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    private suspend fun setPreview() {
        val result = GlanceAppWidgetManager(app).setWidgetPreviews(TodayStatusWidgetReceiver::class)
        if (result != GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_SUCCESS) Log.i(TAG, "widget preview rate-limited")
    }

    companion object {
        const val ACTION_MIDNIGHT = "com.dredfit.widgets.MIDNIGHT"

        /** The shortest window Android 12+ grants `setWindow`. */
        const val MIDNIGHT_WINDOW_MS = 10L * 60 * 1000

        private const val TAG = "WidgetCenter"
    }
}
