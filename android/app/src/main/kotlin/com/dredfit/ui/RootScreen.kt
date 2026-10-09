//
//  The root: three tabs (Today, Calendar, Progress — the iOS order), the
//  settings gear over the top-trailing corner of every tab, the first-run
//  onboarding over everything, and the workout over everything while one is
//  in flight. Port of ios/Dredfit/Views/RootView.swift; the TabView is a
//  bottom NavigationBar here.
//

package com.dredfit.ui

import android.app.Activity
import android.app.UiModeManager
import android.content.Context
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import com.dredfit.signals.DeviceSignals
import com.dredfit.store.AppStore
import com.dredfit.store.AppearanceChoice
import com.dredfit.store.completeOnboarding
import com.dredfit.store.shouldShowOnboarding
import com.dredfit.ui.progress.CalendarScreen
import com.dredfit.ui.progress.ProgressScreen
import com.dredfit.ui.settings.OnboardingView
import com.dredfit.ui.settings.SettingsSheet
import com.dredfit.ui.theme.CalendarGlyph
import com.dredfit.ui.theme.ChartGlyph
import com.dredfit.ui.theme.DredfitTheme
import com.dredfit.ui.theme.GearGlyph
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.TodayGlyph
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.today.TodayScreen
import com.dredfit.ui.workout.ActiveWorkout
import com.dredfit.ui.workout.ReviewPrompt
import com.dredfit.ui.workout.WorkoutFlowView

/** The flow in flight, owned by the process so a recreated activity finds it. */
class FlowHolder {
    var active by mutableStateOf<ActiveWorkout?>(null)
}

enum class RootTab { today, calendar, progress }

@Composable
fun RootScreen(observedStore: Observed<AppStore>, holder: FlowHolder, signals: () -> DeviceSignals,
               reviewPrompt: ReviewPrompt) {
    val store by observedStore
    // The ONE place the theme is applied, so it covers the workout, every
    // sheet and every alert.
    val dark = when (store.settings.appearance) {
        AppearanceChoice.system -> isSystemInDarkTheme()
        AppearanceChoice.light -> false
        AppearanceChoice.dark -> true
    }
    // The system bars' icons follow the app's theme, not the system's.
    val view = LocalView.current
    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        }
    }
    DredfitTheme(dark, highContrast = rememberHighContrast()) {
        val c = Theme.colors
        var tab by rememberSaveable { mutableStateOf(RootTab.today) }
        var settingsShown by remember { mutableStateOf(false) }
        // Decided once, when the root first appears — as `onAppear` does.
        // Read in the first composition, so a fresh install's first frame is
        // already the onboarding and Today is never composed under it.
        var onboardingShown by rememberSaveable { mutableStateOf(store.shouldShowOnboarding) }
        val active = holder.active
        Box(Modifier.fillMaxSize().background(c.bg)) {
            when {
                active != null -> WorkoutFlowView(active, observedStore, reviewPrompt) {
                    // The claim on the snapshot ends with the flow, not with
                    // the composition that drew it (WorkoutFlowView.kt).
                    store.workoutFlowDisappeared()
                    active.flow.value.disappear()
                    holder.active = null
                }
                onboardingShown -> OnboardingView {
                    observedStore.act { completeOnboarding() }
                    onboardingShown = false
                }
                else -> {
                    // Android's back from another tab returns to the first,
                    // as a bottom bar does; from Today it leaves the app.
                    BackHandler(enabled = tab != RootTab.today) { tab = RootTab.today }
                    Column(Modifier.fillMaxSize()) {
                        Column(Modifier.weight(1f).fillMaxWidth()
                                   .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))) {
                            // The gear floats over the top-trailing corner.
                            SaveFailureBanner(observedStore, trailingClearance = 44.dp)
                            when (tab) {
                                RootTab.today -> TodayScreen(observedStore, start = { request ->
                                    // Claimed for as long as the flow lives, so a
                                    // foreground hours into an idle session — or a
                                    // recreated activity — cannot settle the workout
                                    // out from under the athlete still in it.
                                    store.workoutFlowAppeared()
                                    holder.active = ActiveWorkout.start(request.session, store, signals(),
                                                                        request.resume, request.settleImmediately)
                                })
                                RootTab.calendar -> CalendarScreen(observedStore)
                                RootTab.progress -> ProgressScreen(observedStore)
                            }
                        }
                        TabBar(tab) { tab = it }
                    }
                    val settingsLabel = tr("Settings")
                    Box(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(top = 4.dp, end = 11.dp)
                            .size(MinTarget).clickable(role = Role.Button) { settingsShown = true }
                            .semantics { contentDescription = settingsLabel }.testTag("settings"),
                        contentAlignment = Alignment.Center) {
                        GearGlyph(c.ink2, 19.dp)
                    }
                }
            }
        }
        if (settingsShown && active == null) SettingsSheet(observedStore) { settingsShown = false }
    }
}

/** The tab bar: the palette's ground under a hairline, ink for the tab in
 *  view and ink2 for the others (a word, so a text tone). */
@Composable
private fun TabBar(tab: RootTab, select: (RootTab) -> Unit) {
    val c = Theme.colors
    Column {
        HorizontalDivider(color = c.hairline)
        NavigationBar(containerColor = c.bg, tonalElevation = 0.dp) {
            val colors = NavigationBarItemDefaults.colors(
                selectedIconColor = c.ink, selectedTextColor = c.ink, indicatorColor = c.cardBG,
                unselectedIconColor = c.ink2, unselectedTextColor = c.ink2)
            for ((item, title) in listOf(RootTab.today to tr("Today"), RootTab.calendar to tr("Calendar"),
                                         RootTab.progress to tr("Progress"))) {
                val selected = tab == item
                val tint = if (selected) c.ink else c.ink2
                NavigationBarItem(
                    selected = selected, onClick = { select(item) }, colors = colors,
                    icon = {
                        when (item) {
                            RootTab.today -> TodayGlyph(tint)
                            RootTab.calendar -> CalendarGlyph(tint)
                            RootTab.progress -> ChartGlyph(tint)
                        }
                    },
                    label = { Text(title, style = dredfitFont(11f)) },
                    modifier = Modifier.testTag("tab-${item.name}"),
                )
            }
        }
    }
}

/** Android 14's contrast setting stands in for iOS's Increased Contrast:
 *  any raised level (medium or high) takes the palette's second column.
 *  Read live, because changing it is not a configuration change. */
@Composable
private fun rememberHighContrast(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
    val context = LocalContext.current
    val manager = remember(context) { context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager }
        ?: return false
    var contrast by remember { mutableStateOf(manager.contrast) }
    DisposableEffect(manager) {
        val listener = UiModeManager.ContrastChangeListener { contrast = it }
        manager.addContrastChangeListener(context.mainExecutor, listener)
        onDispose { manager.removeContrastChangeListener(listener) }
    }
    return contrast > 0f
}

/** Midnight inside a live screen re-anchors "today" — the DATE only; the
 *  decay stays with `activate()`. iOS listens for the significant time
 *  change; Android posts the same as ACTION_DATE_CHANGED / TIME_SET /
 *  TIMEZONE_CHANGED, which MainActivity forwards here. */
fun reanchor(observedStore: Observed<AppStore>) = observedStore.act { reanchorToday() }
