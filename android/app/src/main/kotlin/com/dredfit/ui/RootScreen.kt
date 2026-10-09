//
//  The root: Today, the settings gear over its top-trailing corner, and the
//  workout over everything while one is in flight. Port of
//  ios/Dredfit/Views/RootView.swift. Its TabView (Calendar, Progress) arrives
//  with phase 2c-2; until then Today is the whole root, with no tab bar
//  pointing at screens that do not exist yet.
//

package com.dredfit.ui

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.dredfit.signals.DeviceSignals
import com.dredfit.store.AppStore
import com.dredfit.store.AppearanceChoice
import com.dredfit.ui.settings.SettingsSheet
import com.dredfit.ui.theme.DredfitTheme
import com.dredfit.ui.theme.GearGlyph
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.today.TodayScreen
import com.dredfit.ui.workout.ActiveWorkout
import com.dredfit.ui.workout.WorkoutFlowView

/** The flow in flight, owned by the process so a recreated activity finds it. */
class FlowHolder {
    var active by mutableStateOf<ActiveWorkout?>(null)
}

@Composable
fun RootScreen(observedStore: Observed<AppStore>, holder: FlowHolder, signals: () -> DeviceSignals) {
    val store by observedStore
    // The ONE place the theme is applied, so it covers the workout, every
    // sheet and every alert.
    val dark = when (store.settings.appearance) {
        AppearanceChoice.system -> isSystemInDarkTheme()
        AppearanceChoice.light -> false
        AppearanceChoice.dark -> true
    }
    // The system bars' icons follow the app's theme, not the system's: a
    // dark choice on a light phone would otherwise draw dark icons on `bg`.
    val view = LocalView.current
    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        }
    }
    DredfitTheme(dark) {
        val c = Theme.colors
        var settingsShown by remember { mutableStateOf(false) }
        val active = holder.active
        Box(Modifier.fillMaxSize().background(c.bg)) {
            if (active != null) {
                WorkoutFlowView(active, observedStore) {
                    // The claim on the snapshot ends with the flow, not with
                    // the composition that drew it (WorkoutFlowView.kt).
                    store.workoutFlowDisappeared()
                    active.flow.value.disappear()
                    holder.active = null
                }
            } else {
                Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                    // The gear floats over the top-trailing corner.
                    SaveFailureBanner(observedStore, trailingClearance = 44.dp)
                    TodayScreen(observedStore, start = { request ->
                        // Claimed for as long as the flow lives, so a
                        // foreground hours into an idle session — or a
                        // recreated activity — cannot settle the workout out
                        // from under the athlete still in it.
                        store.workoutFlowAppeared()
                        holder.active = ActiveWorkout.start(request.session, store, signals(),
                                                            request.resume, request.settleImmediately)
                    })
                }
                val settingsLabel = tr("Settings")
                Box(Modifier.align(Alignment.TopEnd).safeDrawingPadding().padding(top = 4.dp, end = 11.dp)
                        .size(MinTarget).clickable(role = Role.Button) { settingsShown = true }
                        .semantics { contentDescription = settingsLabel }.testTag("settings"),
                    contentAlignment = Alignment.Center) {
                    GearGlyph(c.ink2, 19.dp)
                }
            }
        }
        if (settingsShown && active == null) SettingsSheet(observedStore) { settingsShown = false }
    }
}

/** Midnight inside a live screen re-anchors "today" — the DATE only; the
 *  decay stays with `activate()`. iOS listens for the significant time
 *  change; Android posts the same as ACTION_DATE_CHANGED / TIME_SET /
 *  TIMEZONE_CHANGED, which MainActivity forwards here. */
fun reanchor(observedStore: Observed<AppStore>) = observedStore.act { reanchorToday() }
