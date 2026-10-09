//
//  The one activity. Coming to the foreground is iOS's scene becoming
//  active: `activate()` runs the same sequence there and here. Until the
//  store has loaded (off the main thread, DredfitApp) the window shows only
//  the ground — a few milliseconds on a normal journal — and the activation
//  of a cold start runs the moment the store arrives.
//

package com.dredfit

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import com.dredfit.review.PlayReviewPrompt
import com.dredfit.store.AppStore
import com.dredfit.store.DeviceMark
import com.dredfit.store.activate
import com.dredfit.store.recheckRemindersOnANewDevice
import com.dredfit.ui.Observed
import com.dredfit.ui.RootScreen
import com.dredfit.ui.reanchor
import com.dredfit.ui.theme.Palette
import java.io.IOException

class MainActivity : ComponentActivity() {

    private val app get() = application as DredfitApp
    private var store by mutableStateOf<Observed<AppStore>?>(null)

    /** "Open Today" from a tapped reminder, counted so the same request twice
     *  is two requests (RootScreen reads the change). */
    private var todayRequests by mutableIntStateOf(0)

    /** The reminder's question for POST_NOTIFICATIONS. Registered by every
     *  activity, so an answer that comes back to a recreated one still
     *  reaches the waiting store (the waiting list is the process's). */
    private val notificationQuestion = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        app.reminders.answered()
    }
    private val askForNotifications = { notificationQuestion.launch(Manifest.permission.POST_NOTIFICATIONS) }

    /** Per activity: Play launches its card over the activity that asks. */
    private val reviewPrompt by lazy { app.reviewPromptForTests ?: PlayReviewPrompt(this) }

    /** Midnight, a clock change or a zone change while the screen is up —
     *  `UIApplication.significantTimeChangeNotification` on iOS. */
    private val timeChanged = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            store?.let(::reanchor)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        app.reminders.ask = askForNotifications
        app.withStore { loaded ->
            store = loaded
            // A cold start: onResume has already run without a store. A
            // recreated activity gets the store inline here, and its own
            // onResume activates it.
            if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                loaded.act { activate() }
                recheckAfterARestore(loaded)
            }
        }
        setContent {
            val loaded = store
            if (loaded == null) {
                Box(Modifier.fillMaxSize().background(if (isSystemInDarkTheme()) Palette.dark.bg else Palette.light.bg))
            } else {
                RootScreen(loaded, app.flows, app::signals, reviewPrompt, todayRequests)
            }
        }
    }

    /** The first launch on this device of a state that came from a backup:
     *  the reminder's permission is re-checked (`recheckRemindersOnANewDevice`),
     *  once — the mark is written only when the check ran. */
    private fun recheckAfterARestore(loaded: Observed<AppStore>) {
        val mark = DeviceMark.file(noBackupFilesDir)
        if (mark.exists()) return
        var checked = false
        loaded.act { checked = recheckRemindersOnANewDevice() }
        if (!checked) return
        try {
            mark.createNewFile()
        } catch (unwritable: IOException) {
            // Unmarked, the next return checks again: a question at worst.
            Log.w("MainActivity", "the device mark could not be written", unwritable)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_OPEN_TODAY) todayRequests += 1
    }

    override fun onDestroy() {
        if (app.reminders.ask === askForNotifications) {
            app.reminders.ask = null
            // Leaving for good with the question unanswered: the store must
            // not wait for a dialog that has no screen any more.
            if (isFinishing) app.reminders.answered()
        }
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        store?.let {
            it.act { activate() }
            recheckAfterARestore(it)
        }
    }

    override fun onStart() {
        super.onStart()
        registerReceiver(timeChanged, IntentFilter().apply {
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        })
    }

    override fun onStop() {
        unregisterReceiver(timeChanged)
        super.onStop()
    }

    companion object {
        /** A tapped reminder (reminders/SystemNotificationScheduler.kt). */
        const val ACTION_OPEN_TODAY = "com.dredfit.OPEN_TODAY"
    }
}
