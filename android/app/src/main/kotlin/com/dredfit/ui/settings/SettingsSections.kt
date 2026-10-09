//
//  The smaller groups of the settings screen: the week, the equipment,
//  sounds, the theme and the footer. Port of
//  ios/Dredfit/Views/Settings/SettingsSections.swift.
//
//  Left out, each for a reason of its own (android/CLAUDE.md, Deferred):
//  the reminder under the rest days (reminders/, phase 3) and the Appearance
//  caption about widgets and the Lock Screen (no widget exists here yet).
//
//  Said differently on Android (owner decisions, 09.10.2026), from the
//  Android-only catalog android/app/Localizable.xcstrings: both captions of
//  "Play tones in Silent mode" — iOS's name the iPhone's ringer SWITCH and
//  Silent mode alone, Android's the phone's sound mode, where vibrate mutes
//  the tones as silent does — and About's rate row, which goes
//  to Google Play. Both About rows wait for the Play listing behind
//  `BuildConfig.PLAY_LISTING_LIVE`.
//

package com.dredfit.ui.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dredfit.BuildConfig
import com.dredfit.store.AppStore
import com.dredfit.store.AppearanceChoice
import com.dredfit.store.barToggleWouldDiscardWorkout
import com.dredfit.store.setAppearance
import com.dredfit.store.setPlaysTonesInSilentMode
import com.dredfit.store.setSounds
import com.dredfit.store.swiftWeekday
import com.dredfit.store.toggleRestDay
import com.dredfit.ui.Observed
import com.dredfit.ui.currentLocale
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.HeartGlyph
import com.dredfit.ui.theme.StarGlyph
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import java.time.DayOfWeek
import java.time.format.TextStyle
import java.time.temporal.WeekFields

/** The chip rules, plain so a unit test reaches them. Weekdays are iOS
 *  numbers, 1 = Sunday, as `restWeekdays` stores them. */
object RhythmSection {

    /** The week as the locale starts it. */
    fun displayOrder(firstWeekday: Int): List<Int> = (0 until 7).map { ((firstWeekday - 1 + it) % 7) + 1 }

    /** Turning the LAST training day into rest is what cannot happen, so
     *  that chip is dimmed rather than silently refusing (`toggleRestDay`). */
    fun isLocked(restWeekdays: Set<Int>, weekday: Int): Boolean = weekday !in restWeekdays && restWeekdays.size == 6

    /** iOS weekday number → `DayOfWeek`. */
    fun dayOfWeek(weekday: Int): DayOfWeek = DayOfWeek.of(((weekday + 5) % 7) + 1)
}

/** The rest days under the name "How it works" gives the rule. No length
 *  control, on purpose: the session shortens on the work screen, set by set. */
@Composable
fun RhythmSection(observedStore: Observed<AppStore>) {
    val store by observedStore
    val locale = currentLocale()
    val first = swiftWeekday(WeekFields.of(locale).firstDayOfWeek)
    val todayWeekday = swiftWeekday(store.today.atZone(store.zone).dayOfWeek)
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SettingsKicker(tr("Weekly rhythm"), "settings-rhythm")
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(tr("Rest days"), style = dredfitFont(16f, Weight.medium), color = Theme.colors.ink,
                 modifier = Modifier.padding(bottom = 4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (wd in RhythmSection.displayOrder(first)) {
                    val symbol = RhythmSection.dayOfWeek(wd).getDisplayName(TextStyle.SHORT, locale)
                    val isRest = wd in store.settings.restWeekdays
                    // The ring the calendar uses for today: which column is
                    // the day you are standing in.
                    val isToday = wd == todayWeekday
                    Chip(symbol, on = isRest, enabled = !RhythmSection.isLocked(store.settings.restWeekdays, wd),
                         ringed = isToday, label = if (isToday) tr("%@, today", symbol) else symbol,
                         tag = "weekday-$wd", modifier = Modifier.weight(1f)) {
                        observedStore.act { toggleRestDay(wd) }
                    }
                }
            }
            SettingsCaption(tr("Highlighted days are rest days"))
            SettingsCaption(tr("3–4 rest days a week is the recommended rhythm. At least one training day always stays."))
        }
    }
}

/** The day chips and the appearance chips: accentSoft with an accent edge
 *  when on, words in ink (accent text on accentSoft is under 4.5:1). */
@Composable
private fun Chip(title: String, on: Boolean, enabled: Boolean, ringed: Boolean, label: String, tag: String,
                 modifier: Modifier, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(12.dp)
    val ring = if (ringed) Modifier.border(2.dp, c.accent, RoundedCornerShape(15.dp)).padding(3.dp) else Modifier
    Box(modifier.alpha(if (enabled) 1f else 0.4f).then(ring)) {
        Box(Modifier.fillMaxWidth().heightIn(min = 38.dp).clip(shape).background(if (on) c.accentSoft else c.bg, shape)
                .border(1.5.dp, if (on) c.accent else c.hairline, shape)
                .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
                // Colour alone does not reach TalkBack. The tag is set INSIDE:
                // a testTag modifier after this one would be cleared with the rest.
                .clearAndSetSemantics { contentDescription = label; selected = on; role = Role.Button; testTag = tag },
            contentAlignment = Alignment.Center) {
            Text(title, style = dredfitFont(13f, Weight.semibold), color = if (on) c.ink else c.ink2, maxLines = 1,
                 overflow = TextOverflow.Clip)
        }
    }
}

// MARK: - Equipment

/** The switch regenerates today's session, and a workout in flight is
 *  fingerprinted against the OLD one: a switch that would silently spend it
 *  asks first. The mirror is what the switch shows while the question is up;
 *  both ways out clear it. */
@Composable
fun EquipmentSection(observedStore: Observed<AppStore>) {
    val store by observedStore
    var pendingBarToggle by remember { mutableStateOf<Boolean?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SettingsKicker(tr("Equipment"), "settings-equipment")
        Box(Modifier.padding(top = 2.dp)) {
            SwitchRow(tr("Pull-up bar"), pendingBarToggle ?: store.engineState.hasBar, tag = "hasbar-toggle") { on ->
                if (store.barToggleWouldDiscardWorkout(on)) pendingBarToggle = on
                else observedStore.act { setHasBar(on) }
            }
        }
        SettingsCaption(tr("Every other workout swaps the horizontal pull for a vertical one"))
    }
    pendingBarToggle?.let { on ->
        DredfitAlert(
            title = tr("Drop today's unfinished workout?"),
            message = tr("The bar changes today's plan, so the workout you started can't be picked up again and the sets already done won't be recorded. Finish it first and nothing is lost."),
            actions = listOf(
                AlertAction(tr("Keep the workout"), tag = null, cancel = true) {},
                AlertAction(tr("Switch the bar"), tag = "hasbar-switch", destructive = true) {
                    observedStore.act { setHasBar(on) }
                },
            ),
            onClose = { pendingBarToggle = null },
        )
    }
}

// MARK: - Sounds

/** The caption under "Play tones in Silent mode". Android has no ringer
 *  switch: the phone's sound mode is what `CountdownSounds.play` reads, and
 *  silent AND vibrate both mute the tones unless the switch lets them
 *  through — the haptics fire either way. Both captions are Android's own:
 *  iOS's OFF one names Silent mode alone, and on Android vibrate mutes the
 *  tones too (owner decision, 09.10.2026). */
object SilentModeCaption {
    fun key(playsTonesInSilentMode: Boolean): String =
        if (playsTonesInSilentMode) "The tones play even when the phone is set to silent or vibrate."
        else "When the phone is set to silent or vibrate, the tones go quiet — the vibration keeps going."
}

@Composable
fun SoundsSection(observedStore: Observed<AppStore>) {
    val store by observedStore
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SettingsKicker(tr("Sounds"), "settings-sounds")
        SwitchRow(tr("Sounds and haptics"), store.settings.soundsEnabled, tag = "sounds-toggle") { on ->
            observedStore.act { setSounds(on) }
        }
        // Only under the ON switch: with sounds off the ringer mode has
        // nothing to silence. Off by default — a phone silenced on purpose.
        if (store.settings.soundsEnabled) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SwitchRow(tr("Play tones in Silent mode"), store.settings.playsTonesInSilentMode, tag = "silent-mode-toggle",
                          titleSize = 15f) { on -> observedStore.act { setPlaysTonesInSilentMode(on) } }
                SettingsCaption(tr(SilentModeCaption.key(store.settings.playsTonesInSilentMode)))
            }
        }
    }
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, tag: String, titleSize: Float = 16f, onChange: (Boolean) -> Unit) {
    val c = Theme.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = dredfitFont(titleSize, if (titleSize >= 16f) Weight.medium else Weight.regular), color = c.ink,
             modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange,
               colors = SwitchDefaults.colors(checkedTrackColor = c.accent, checkedThumbColor = c.bg,
                                              uncheckedTrackColor = c.restFill, uncheckedThumbColor = c.ink2,
                                              uncheckedBorderColor = c.ink2),
               modifier = Modifier.testTag(tag))
    }
}

// MARK: - Appearance

/** A theme of its own, applied by the one place RootScreen reads it — so it
 *  covers the workout, every sheet and every alert. Three chips, the rest
 *  days' own. Tagged by the raw value, the wire name in the settings file. */
@Composable
fun AppearanceSection(observedStore: Observed<AppStore>) {
    val store by observedStore
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SettingsKicker(tr("Appearance"), "settings-appearance")
        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((choice, key) in listOf(AppearanceChoice.system to "appearance.system", AppearanceChoice.light to "appearance.light",
                                         AppearanceChoice.dark to "appearance.dark")) {
                val title = tr(key)
                val on = store.settings.appearance == choice
                Chip(title, on = on, enabled = true, ringed = false, label = title, tag = "appearance-${choice.name}",
                     modifier = Modifier.weight(1f)) { observedStore.act { setAppearance(choice) } }
            }
        }
    }
}

// MARK: - About

/** Where About's two rows lead: the app's Google Play page, where iOS's lead
 *  to the App Store. */
object AboutLinks {
    /** The RELEASE application id — the listing's, whatever a test or debug
     *  build calls itself. AboutLinksTest holds it to build.gradle.kts. */
    const val LISTING_ID = "com.dredfit.dredfit"

    /** The Play Store app's own page for the app ("Rate"). */
    const val PLAY_STORE_APP = "market://details?id=$LISTING_ID"

    /** The same page on the web: Rate's fallback without the Play Store, and
     *  what "Recommend" hands on — a link anyone can open, on any phone. */
    const val PLAY_LISTING_WEB = "https://play.google.com/store/apps/details?id=$LISTING_ID"
}

/** ink2, not ink3: a version line is the string a bug report is read off.
 *  The rows show only once the listing is live — a link to a page that does
 *  not exist is worse than none. */
@Composable
fun AboutSection(listingLive: Boolean = BuildConfig.PLAY_LISTING_LIVE) {
    val context = LocalContext.current
    val c = Theme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SettingsKicker(tr("About"), "settings-about")
        if (listingLive) {
            SettingsRow({ StarGlyph(c.ink, 16.dp) }, tr("Rate on Google Play"), tag = "rate-app") {
                openPlayListing(context)
            }
            val recommend = tr("Recommend Dredfit")
            SettingsRow({ HeartGlyph(c.ink, 16.dp) }, recommend, tag = "recommend-app") {
                recommendDredfit(context, recommend)
            }
        }
        SettingsCaption(versionLine(context), Modifier.testTag("version-line"))
    }
}

/** The Play Store app where there is one; the web page where there is not.
 *  Internal for AboutSectionTest, which has no phone without a store. */
internal fun openPlayListing(context: Context) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(AboutLinks.PLAY_STORE_APP)))
    } catch (_: ActivityNotFoundException) {
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(AboutLinks.PLAY_LISTING_WEB)))
        } catch (_: ActivityNotFoundException) {
            // Neither a store nor a browser: nothing on the phone can open a
            // link, and no message would give it one.
        }
    }
}

/** The share sheet over the listing's link — iOS's `ShareLink(item: URL)`. */
private fun recommendDredfit(context: Context, title: String) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, AboutLinks.PLAY_LISTING_WEB)
    }
    context.startActivity(Intent.createChooser(send, title))
}

private fun versionLine(context: Context): String = try {
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    "Dredfit ${info.versionName ?: "—"} (${info.longVersionCode})"
} catch (_: PackageManager.NameNotFoundException) {
    "Dredfit — (—)"
}
