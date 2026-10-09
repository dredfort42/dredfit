//
//  Today, minimal: the plan ahead (or the rest day) and the door to bring a
//  history over from iOS. The full screen — cards, the workout, the rating —
//  is ported from ios/Dredfit/Views/Today with the workout flow.
//

package com.dredfit.ui.today

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dredfit.core.SwiftDecodingException
import com.dredfit.store.AppStore
import com.dredfit.store.BackupError
import com.dredfit.store.doneToday
import com.dredfit.store.importBackup
import com.dredfit.store.nextSession
import com.dredfit.store.restAppliesToday
import com.dredfit.ui.displayOf
import com.dredfit.ui.tr
import java.io.IOException

@Composable
fun TodayScreen(store: AppStore, modifier: Modifier = Modifier) {
    // The store is plain Kotlin; one counter bumped on every change is what
    // makes this composition read it again — `@Observable`'s job on iOS.
    var version by remember { mutableIntStateOf(0) }
    DisposableEffect(store) {
        val handle = store.observe { version += 1 }
        onDispose { handle.close() }
    }
    val session = remember(version) { store.nextSession }
    val done = remember(version) { store.doneToday }
    val resting = remember(version) { store.restAppliesToday } && !done
    val planOnScreen = !resting && !done
    val frozen = remember(version) { store.journalFrozen }
    // One write per SHOWING (`recordPlanShown` returns early on the renders
    // after the first): the engine remembers the plan the person saw.
    LaunchedEffect(session, planOnScreen) {
        if (planOnScreen) store.recordPlanShown(session)
    }

    Column(modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Text(
            text = if (resting) tr("Rest day") else tr("Today"),
            fontSize = 32.sp, fontWeight = FontWeight.Black,
            modifier = Modifier.testTag("today-heading"))
        if (!planOnScreen) {
            Text(tr("Next workout %@", nextTrainingDateLabel(store)),
                 style = MaterialTheme.typography.bodyLarge,
                 color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        Text(tr("Workout %lld", session.sessionNumber),
             style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f)) {
            items(session.exercises, key = { it.pattern.rawValue }) { ex ->
                Row(Modifier.fillMaxWidth().padding(vertical = 12.dp).testTag("plan-row-${ex.pattern.rawValue}"),
                    horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(tr(ex.name), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    Text(displayOf(ex), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                }
                HorizontalDivider()
            }
        }
        ImportHistoryButton(store, enabled = !frozen)
    }
}

/** "Import history", as in the iOS backup section: pick, confirm, replace —
 *  and say so when the file cannot be read in full. */
@Composable
private fun ImportHistoryButton(store: AppStore, enabled: Boolean) {
    val context = LocalContext.current
    var picked by remember { mutableStateOf<ByteArray?>(null) }
    var failed by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult   // cancelled
        picked = try {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (_: IOException) {
            null
        } catch (_: SecurityException) {
            null
        }
        // A file the picker could not hand over could not be read either.
        if (picked == null) failed = true
    }

    OutlinedButton(
        onClick = { picker.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) },
        // A frozen launch would import into the empty state that stood in for
        // the real journal.
        enabled = enabled,
        modifier = Modifier.fillMaxWidth().testTag("import-history"),
    ) { Text(tr("Import history")) }

    picked?.let { bytes ->
        AlertDialog(
            onDismissRequest = { picked = null },
            title = { Text(tr("Replace history?")) },
            text = { Text(tr("Import replaces your current history and settings.")) },
            confirmButton = {
                TextButton(onClick = {
                    picked = null
                    try {
                        store.importBackup(bytes)
                    } catch (_: BackupError) {
                        failed = true
                    } catch (_: SwiftDecodingException) {
                        failed = true
                    }
                }) { Text(tr("Replace")) }
            },
            dismissButton = { TextButton(onClick = { picked = null }) { Text(tr("Keep my history")) } },
        )
    }
    if (failed) {
        AlertDialog(
            onDismissRequest = { failed = false },
            title = { Text(tr("Couldn't read this file.")) },
            confirmButton = { TextButton(onClick = { failed = false }) { Text(tr("OK")) } },
        )
    }
}
