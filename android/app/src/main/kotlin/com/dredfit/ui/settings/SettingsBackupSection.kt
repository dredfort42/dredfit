//
//  Backup: export and import of the history file. Port of
//  ios/Dredfit/Views/Settings/SettingsBackupSection.swift.
//
//  Export goes through the system's "save to" picker (SAF CreateDocument)
//  where iOS raises its share sheet: the file is the person's own copy of
//  everything, and on Android the picker is what saves a file to a place
//  they choose — the share sheet offers apps, not folders. The file is built
//  by the TAP and only then handed over, so a failure gets an alert instead
//  of the belief that a backup exists. The bytes move on an I/O thread.
//

package com.dredfit.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.dredfit.core.SwiftDecodingException
import com.dredfit.store.AppStore
import com.dredfit.store.BackupError
import com.dredfit.store.backupFileName
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.TrayArrowGlyph
import com.dredfit.ui.tr
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

@Composable
fun BackupSection(observedStore: Observed<AppStore>) {
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

    // A frozen launch would export — or import into — the empty state that
    // stood in for the real journal.
    val frozen = store.journalFrozen
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SettingsKicker(tr("Backup"), "settings-backup")
        // Above the rows: read BEFORE the tap, because after Export the file
        // has already gone.
        SettingsCaption(tr("The file holds your history, your plan and your settings — including your weight, if you entered one. It goes only where you send it."))
        SettingsRow({ TrayArrowGlyph(c.ink, up = true, size = 16.dp) }, tr("Export history"), tag = "export-history",
                    enabled = !frozen) {
            try {
                exportBytes = store.exportBackup()
                exportPicker.launch(backupFileName(store.clock.instant()))
            } catch (_: BackupError) {
                exportFailed = true
            }
        }
        SettingsRow({ TrayArrowGlyph(c.ink, up = false, size = 16.dp) }, tr("Import history"), tag = "import-history",
                    enabled = !frozen) {
            importPicker.launch(arrayOf("application/json", "text/plain", "application/octet-stream"))
        }
        if (frozen) {
            SettingsCaption(tr("Your history couldn't be read on this launch, so it can't be backed up. Unlock the phone and open Dredfit again."))
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
