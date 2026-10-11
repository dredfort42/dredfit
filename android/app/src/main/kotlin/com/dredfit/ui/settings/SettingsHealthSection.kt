//
//  Health Connect: the switch, the body weight, and the calorie opt-out.
//  Port of ios/Dredfit/Views/Settings/SettingsHealthSection.swift — the
//  reasoning behind each row is there. What Android adds: Health Connect may
//  be missing (Android 10–13 without its app: a row to install it from Google
//  Play) or unusable (a work profile, a device without the service: the group
//  is not shown at all — Google's guidance for SDK_UNAVAILABLE is to hide every
//  integration point). The words name Health Connect where iOS's name Apple
//  Health; they are Android keys (android/app/Localizable.xcstrings).
//

package com.dredfit.ui.settings

import android.icu.text.MeasureFormat
import android.icu.text.NumberFormat
import android.icu.util.LocaleData
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.util.TimeZone
import android.icu.util.ULocale
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.health.connect.client.HealthConnectClient
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.dredfit.DredfitApp
import com.dredfit.health.HealthConnectWriter
import com.dredfit.store.AppSettings
import com.dredfit.store.AppStore
import com.dredfit.store.disableHealth
import com.dredfit.store.healthBackfillCount
import com.dredfit.store.setBodyMass
import com.dredfit.store.setWatchRecordsWorkouts
import com.dredfit.store.skipHealthBackfill
import com.dredfit.store.startHealthBackfill
import com.dredfit.store.turnHealthOn
import com.dredfit.ui.Observed
import com.dredfit.ui.currentLocale
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.ChevronGlyph
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.ScaleGlyph
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.TrayArrowGlyph
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import java.time.Instant
import java.util.Date
import java.util.Locale

@Composable
fun HealthSection(observedStore: Observed<AppStore>) {
    val store by observedStore
    val context = LocalContext.current
    val health = (context.applicationContext as DredfitApp).health
    val status = healthConnectStatus(health)
    if (status == HealthConnectClient.SDK_UNAVAILABLE) return
    var backfillPromptShown by remember { mutableStateOf(false) }
    var bodyMassPromptShown by remember { mutableStateOf(false) }
    // Optimistic value while the permission screen is up: without it the
    // switch visibly bounces off before Health Connect's screen appears.
    var healthSwitch by remember { mutableStateOf<Boolean?>(null) }
    val locale = currentLocale()

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SettingsKicker(tr("Health Connect"), "settings-health")
        if (status == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SettingsRow({ TrayArrowGlyph(Theme.colors.ink, up = false, size = 16.dp) },
                            tr(if (health.providerInstalled()) "Update Health Connect" else "Install Health Connect"),
                            tag = "health-install") { HealthConnectWriter.openInstallPage(context) }
                SettingsCaption(tr("Workouts appear in Health Connect. Nothing leaves your device."))
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SwitchRow(tr("Save workouts to Health Connect"), healthSwitch ?: store.settings.healthEnabled,
                          tag = "health-toggle") { on ->
                    if (!on) {
                        healthSwitch = null
                        observedStore.act { disableHealth() }
                    } else {
                        healthSwitch = true
                        // A denial leaves the switch off; on success, past
                        // history is offered once.
                        store.turnHealthOn { granted ->
                            healthSwitch = null   // reality (granted or denied) takes over
                            if (granted && observedStore.value.healthBackfillCount > 0) backfillPromptShown = true
                        }
                    }
                }
                SettingsCaption(tr("Workouts appear in Health Connect. Nothing leaves your device."))
            }
            if (store.settings.healthEnabled) {
                BodyMassRow(store.settings, locale, store.zone) { bodyMassPromptShown = true }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    SwitchRow(tr("Leave calories out"), store.settings.watchRecordsWorkouts, tag = "watch-records-toggle") { on ->
                        observedStore.act { setWatchRecordsWorkouts(on) }
                    }
                    SettingsCaption(tr("Turn it on if a smartwatch records the same workouts — otherwise the session counts twice — or if you simply want no estimate written."))
                }
            }
        }
    }

    if (backfillPromptShown) {
        val count = store.healthBackfillCount
        DredfitAlert(
            title = tr("Add past workouts to Health Connect?"),
            message = null,
            actions = listOf(
                AlertAction(tr("Export %lld workouts", count), tag = "health-backfill-all") {
                    observedStore.act { startHealthBackfill() }
                },
                // The back gesture's answer too: iOS's alert cannot be left
                // without a choice, and the choice that writes nothing into
                // Health Connect is the one a dismissal may stand for.
                AlertAction(tr("Only new ones"), tag = "health-backfill-new", cancel = true) {
                    observedStore.act { skipHealthBackfill() }
                },
            ),
            onClose = { backfillPromptShown = false },
        )
    }
    if (bodyMassPromptShown) {
        BodyMassDialog(BodyMassField.editable(store.settings.bodyMassKg, locale), locale,
                       onClose = { bodyMassPromptShown = false }) { typed ->
            when (val commit = BodyMassField.commit(typed, BodyMassField.usesPounds(locale))) {
                BodyMassField.Commit.Keep -> Unit
                BodyMassField.Commit.Clear -> observedStore.act { setBodyMass(null) }
                is BodyMassField.Commit.Set -> observedStore.act { setBodyMass(commit.kg) }
            }
        }
    }
}

/** Health Connect's state, read again on every return to the screen: the
 *  person comes back from Google Play with it installed. */
@Composable
private fun healthConnectStatus(health: HealthConnectWriter): Int {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var status by remember { mutableIntStateOf(health.status()) }
    DisposableEffect(lifecycle) {
        val watcher = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) status = health.status()
        }
        lifecycle.addObserver(watcher)
        onDispose { lifecycle.removeObserver(watcher) }
    }
    return status
}

/** The row ALWAYS opens the editor, whether the number came from Health
 *  Connect or was typed, and the caption says where the number in force came
 *  from and when. */
@Composable
private fun BodyMassRow(settings: AppSettings, locale: Locale, zone: java.time.ZoneId, open: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(14.dp)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = MinTarget).clip(shape).background(c.cardBG, shape)
                .clickable(role = Role.Button, onClick = open).testTag("body-mass-row")
                .padding(horizontal = 16.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ScaleGlyph(c.ink, 15.dp)
            Text(tr("Body weight"), style = dredfitFont(16f, Weight.medium), color = c.ink, modifier = Modifier.weight(1f))
            Text(settings.bodyMassKg?.let { BodyMassField.display(it, locale) } ?: tr("Not set"),
                 style = dredfitFont(15f), color = c.ink2, modifier = Modifier.testTag("body-mass-value"))
            ChevronGlyph(c.ink2, 12.dp)
        }
        BodyMassField.captionKey(settings)?.let { key ->
            val text = settings.bodyMassDate?.let { tr(key, BodyMassField.date(it, locale, zone)) } ?: tr(key)
            SettingsCaption(text, Modifier.testTag("body-mass-caption"))
        }
    }
}

/** iOS's alert with a text field: the unit as the placeholder, a decimal
 *  keyboard, Save and Cancel. */
@Composable
private fun BodyMassDialog(initial: String, locale: Locale, onClose: () -> Unit, save: (String) -> Unit) {
    val c = Theme.colors
    var field by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onClose,
        properties = DialogProperties(dismissOnClickOutside = false),
        containerColor = c.cardBG,
        title = { Text(tr("Body weight"), style = dredfitFont(18f, Weight.semibold), color = c.ink) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(tr("Used only to estimate the calories of each workout. Kept on this device and in the backups you export."),
                     style = dredfitFont(14.5f), color = c.ink2)
                OutlinedTextField(field, { field = it }, singleLine = true,
                                  placeholder = { Text(BodyMassField.unitLabel(locale), color = c.ink3) },
                                  keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                  colors = OutlinedTextFieldDefaults.colors(focusedTextColor = c.ink, unfocusedTextColor = c.ink,
                                                                            focusedBorderColor = c.accent, cursorColor = c.accent),
                                  modifier = Modifier.fillMaxWidth().testTag("body-mass-field"))
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onClose()
                save(field)
            }, modifier = Modifier.heightIn(min = MinTarget).testTag("body-mass-save")) {
                Text(tr("Save"), style = dredfitFont(15.5f, Weight.medium), color = c.ink)
            }
        },
        dismissButton = {
            TextButton(onClick = onClose, modifier = Modifier.heightIn(min = MinTarget)) {
                Text(tr("Cancel"), style = dredfitFont(15.5f, Weight.semibold), color = c.ink)
            }
        },
    )
}

/** The weight row's rules, out of the composable: the store keeps
 *  kilograms always, the field shows the locale's unit. */
object BodyMassField {
    /** Exact, by definition (international pound, 1959). */
    const val KG_PER_POUND = 0.45359237

    sealed interface Commit {
        /** An unreadable entry: a typo is not a request to erase the number. */
        data object Keep : Commit
        /** Only an EMPTY field clears the weight. */
        data object Clear : Commit
        data class Set(val kg: Double) : Commit
    }

    /** The comma is accepted because half the shipping languages type one. */
    fun commit(typed: String, pounds: Boolean): Commit {
        val text = typed.replace(',', '.').trim()
        if (text.isEmpty()) return Commit.Clear
        val value = text.toDoubleOrNull() ?: return Commit.Keep
        if (!value.isFinite() || value <= 0) return Commit.Keep
        return Commit.Set(if (pounds) value * KG_PER_POUND else value)
    }

    /** Absent: why that matters. Present with the switch on: where it came
     *  from and when (the date is the argument). Present with the switch
     *  off, or undated: nothing — "set in the app", not "typed here", since
     *  a restored backup sets the number too. */
    fun captionKey(settings: AppSettings): String? = when {
        settings.bodyMassKg == null -> "Without it, workouts are saved with no calorie estimate."
        !settings.healthEnabled || settings.bodyMassDate == null -> null
        settings.bodyMassFromHealth -> "From Health Connect, %@. A newer weight — typed here or logged there — takes over."
        else -> "Set in the app, %@. A newer weight logged in Health Connect takes over."
    }

    /** Pounds where the locale measures in them (iOS: `.us`). */
    fun usesPounds(locale: Locale): Boolean =
        LocaleData.getMeasurementSystem(ULocale.forLocale(locale)) == LocaleData.MeasurementSystem.US

    private fun shown(kg: Double, locale: Locale): Double = if (usesPounds(locale)) kg / KG_PER_POUND else kg

    private fun numbers(locale: Locale, grouping: Boolean): NumberFormat = NumberFormat.getInstance(locale).apply {
        minimumFractionDigits = 0
        maximumFractionDigits = 1
        isGroupingUsed = grouping
    }

    /** "72.5 kg", "160 lb" — abbreviated, up to one decimal. */
    fun display(kg: Double, locale: Locale): String =
        MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.SHORT, numbers(locale, grouping = true))
            .format(Measure(shown(kg, locale), unit(locale)))

    /** The number the editor opens on: the locale's decimal mark, no grouping. */
    fun editable(kg: Double?, locale: Locale): String = kg?.let { numbers(locale, grouping = false).format(shown(it, locale)) } ?: ""

    fun unitLabel(locale: Locale): String =
        MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.SHORT).getUnitDisplayName(unit(locale))

    private fun unit(locale: Locale): MeasureUnit = if (usesPounds(locale)) MeasureUnit.POUND else MeasureUnit.KILOGRAM

    /** The weigh-in's day, abbreviated (iOS `.abbreviated`): "Oct 11, 2026". */
    fun date(instant: Instant, locale: Locale, zone: java.time.ZoneId): String =
        android.icu.text.DateFormat.getDateInstance(android.icu.text.DateFormat.MEDIUM, locale).apply {
            timeZone = TimeZone.getTimeZone(zone.id)
        }.format(Date.from(instant))
}
