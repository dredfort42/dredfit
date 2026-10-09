//
//  The one activity. Coming to the foreground is iOS's scene becoming
//  active: `activate()` runs the same sequence there and here. Until the
//  store has loaded (off the main thread, DredfitApp) the window shows only
//  the ground — a few milliseconds on a normal journal — and the activation
//  of a cold start runs the moment the store arrives.
//

package com.dredfit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import com.dredfit.review.PlayReviewPrompt
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.ui.Observed
import com.dredfit.ui.RootScreen
import com.dredfit.ui.reanchor
import com.dredfit.ui.theme.Palette

class MainActivity : ComponentActivity() {

    private val app get() = application as DredfitApp
    private var store by mutableStateOf<Observed<AppStore>?>(null)

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
        app.withStore { loaded ->
            store = loaded
            // A cold start: onResume has already run without a store. A
            // recreated activity gets the store inline here, and its own
            // onResume activates it.
            if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) loaded.act { activate() }
        }
        setContent {
            val loaded = store
            if (loaded == null) {
                Box(Modifier.fillMaxSize().background(if (isSystemInDarkTheme()) Palette.dark.bg else Palette.light.bg))
            } else {
                RootScreen(loaded, app.flows, app::signals, reviewPrompt)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        store?.act { activate() }
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
}
