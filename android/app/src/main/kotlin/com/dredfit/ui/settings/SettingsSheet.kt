//
//  The settings sheet the gear opens — in THIS phase only the two groups the
//  workout needs to be usable on a phone that came from iPhone: Sounds (the
//  one switch every countdown signal answers to) and Backup (bringing the iOS
//  history over, and taking one out). Ports of SoundsSection and
//  BackupSection (ios/Dredfit/Views/Settings/SettingsSections.swift,
//  SettingsBackupSection.swift); the rest of SettingsSheet.swift — rhythm,
//  equipment, appearance, Health, how it works, about — arrives in phase
//  2c-2, and the sheet grows into it rather than pretending to be it now.
//
//  Not ported from SoundsSection: "Play tones in Silent mode". Its captions
//  talk about the iPhone's ringer switch; the Android wording is a
//  translation job of its own. The setting itself is honoured (an imported
//  backup carries it; signals/CountdownSounds.kt reads it).
//

package com.dredfit.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.dredfit.core.SwiftDecodingException
import com.dredfit.store.AppStore
import com.dredfit.store.BackupError
import com.dredfit.store.backupFileName
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import com.dredfit.store.setSounds
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.DredfitSheet
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

@Composable
fun SettingsSheet(observedStore: Observed<AppStore>, onDismiss: () -> Unit) {
    val c = Theme.colors
    DredfitSheet(onDismiss) {
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
               verticalArrangement = Arrangement.spacedBy(28.dp)) {
            Text(tr("Settings"), style = dredfitFont(28f, Weight.heavy, tracking = -0.5f), color = c.ink,
                 modifier = Modifier.padding(top = 14.dp))
            SoundsSection(observedStore)
            BackupSection(observedStore)
        }
        // Keyed: the same English word as the workout's set button.
        PrimaryButton(tr("settings.done"), tag = "settings-done",
                      modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp), onClick = onDismiss)
    }
}

@Composable
private fun SoundsSection(observedStore: Observed<AppStore>) {
    val store by observedStore
    val c = Theme.colors
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Kicker(tr("Sounds"), Modifier.testTag("settings-sounds"))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("Sounds and haptics"), style = dredfitFont(16f, Weight.medium), color = c.ink,
                 modifier = Modifier.weight(1f))
            Switch(checked = store.settings.soundsEnabled, onCheckedChange = { on -> observedStore.act { setSounds(on) } },
                   colors = SwitchDefaults.colors(checkedTrackColor = c.accent), modifier = Modifier.testTag("sounds-toggle"))
        }
    }
}

/** Export and import of the history file. The file is built by the TAP and
 *  only then handed to the picker, so a failure gets an alert instead of the
 *  belief that a backup exists. The bytes move on an I/O thread. */
@Composable
private fun BackupSection(observedStore: Observed<AppStore>) {
    val store by observedStore
    val c = Theme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<ByteArray?>(null) }
    var importFailed by remember { mutableStateOf(false) }
    var exportFailed by remember { mutableStateOf(false) }
    var exportBytes by remember { mutableStateOf<ByteArray?>(null) }

    val importPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult   // cancelled
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                try {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (_: IOException) {
                    null
                } catch (_: SecurityException) {
                    null
                }
            }
            // A file the picker could not hand over could not be read either.
            if (bytes == null) importFailed = true else picked = bytes
        }
    }
    val exportPicker = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val bytes = exportBytes
        exportBytes = null
        if (uri == null || bytes == null) return@rememberLauncherForActivityResult
        scope.launch {
            val written = withContext(Dispatchers.IO) {
                try {
                    context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } != null
                } catch (_: IOException) {
                    false
                } catch (_: SecurityException) {
                    false
                }
            }
            if (!written) exportFailed = true
        }
    }

    val frozen = store.journalFrozen
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Kicker(tr("Backup"), Modifier.testTag("settings-backup"))
        // Above the rows: read BEFORE the tap, because after Export the file
        // has already gone.
        Text(tr("The file holds your history, your plan and your settings — including your weight, if you entered one. It goes only where you send it."),
             style = dredfitFont(12.5f), color = c.ink2)
        BackupRow(tr("Export history"), "export-history", enabled = !frozen) {
            try {
                exportBytes = store.exportBackup()
                exportPicker.launch(backupFileName(store.clock.instant()))
            } catch (_: BackupError) {
                exportFailed = true
            }
        }
        // A frozen launch would import into the empty state that stood in for
        // the real journal.
        BackupRow(tr("Import history"), "import-history", enabled = !frozen) {
            importPicker.launch(arrayOf("application/json", "text/plain", "application/octet-stream"))
        }
        if (frozen) {
            Text(tr("Your history couldn't be read on this launch, so it can't be backed up. Unlock the phone and open Dredfit again."),
                 style = dredfitFont(12.5f), color = c.ink2)
        }
    }

    picked?.let { bytes ->
        DredfitAlert(
            title = tr("Replace history?"),
            message = tr("Import replaces your current history and settings."),
            actions = listOf(
                AlertAction(tr("Keep my history"), tag = null, cancel = true) {},
                AlertAction(tr("Replace"), tag = "import-replace", destructive = true) {
                    try {
                        observedStore.act { importBackup(bytes) }
                    } catch (_: BackupError) {
                        importFailed = true
                    } catch (_: SwiftDecodingException) {
                        importFailed = true
                    }
                },
            ),
            onClose = { picked = null },
        )
    }
    if (importFailed) {
        DredfitAlert(tr("Couldn't read this file."), null,
                     listOf(AlertAction(tr("OK"), tag = null, cancel = true) {})) { importFailed = false }
    }
    if (exportFailed) {
        DredfitAlert(tr("Couldn't build the backup file."), null,
                     listOf(AlertAction(tr("OK"), tag = null, cancel = true) {})) { exportFailed = false }
    }
}

@Composable
private fun BackupRow(title: String, tag: String, enabled: Boolean, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(14.dp)
    Row(
        Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.4f).background(c.cardBG, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick).testTag(tag)
            .padding(horizontal = 16.dp, vertical = 13.dp),
    ) {
        Text(title, style = dredfitFont(16f, Weight.medium), color = c.ink)
    }
}
