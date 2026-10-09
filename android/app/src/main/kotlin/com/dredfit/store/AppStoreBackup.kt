//
//  The backup, out and back in — the bridge between the two ports: a file
//  exported on iOS imports here and the other way round, because both sides
//  write the one JSON shape. Both directions refuse to run on a frozen
//  journal: exporting one hands the person a file that destroys their
//  history, importing into one looks like it worked and is gone next launch.
//  Port of ios/Dredfit/AppStore+Backup.swift.
//
//  Bytes in, bytes out: where they come from (the system file picker) is the
//  screen's business, so the rules here run in a JVM test.
//

package com.dredfit.store

import com.dredfit.core.SwiftDecodingException
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

sealed class BackupError(message: String) : Exception(message) {
    /** The journal could not be read on this launch (see `journalFrozen`). */
    class JournalUnavailable : BackupError("the journal could not be read on this launch")

    /** The file decoded only in part — see `importBackup`. */
    class IncompleteBackup : BackupError("the backup cannot be read in full")
}

/** What `exportURL` writes: the engine state, the journal and the settings —
 *  never the workout in progress. */
@Throws(BackupError::class)
fun AppStore.exportBackup(): ByteArray {
    if (journalFrozen) throw BackupError.JournalUnavailable()
    return AppData(engineState, records, settings).encode().toByteArray(Charsets.UTF_8)
}

/** iOS's dated name. The ISO date style there formats in GMT, so this does. */
fun backupFileName(now: Instant): String =
    "Dredfit-backup-${DateTimeFormatter.ISO_LOCAL_DATE.format(now.atOffset(ZoneOffset.UTC))}.json"

/**
 * Restores a backup — ALL OR NOTHING. `AppData` decodes leniently because at
 * launch the file is the only copy of the journal; an import has a second
 * copy — the file itself — so one this build cannot read IN FULL is refused
 * before anything moves: a newer build's backup, a damaged one, or none at all
 * (`{"records":[]}` decodes, and would replace a whole history with an empty
 * one). A file that is not a backup at all throws its decoding error.
 */
@Throws(BackupError::class, SwiftDecodingException::class)
fun AppStore.importBackup(bytes: ByteArray) {
    if (journalFrozen) throw BackupError.JournalUnavailable()
    val decoded = AppData.decode(bytes.toString(Charsets.UTF_8))
    if (decoded.engineStateReset || decoded.settingsUnreadable || decoded.droppedRecordCount != 0) {
        throw BackupError.IncompleteBackup()
    }
    // The Health mark tracks an external side effect and must never move
    // backwards on import — for THIS journal only: an unrelated one knows
    // nothing about this device's Health store (#103). Same lineage always
    // shares record ids: the journal is append-only and a backup is its snapshot.
    val priorHealthMark = settings.healthExportedThrough
    val currentIDs = records.map { it.id }.toSet()
    val sameLineage = decoded.records.any { it.id in currentIDs }
    // Flags are facts about THIS device's Health store.
    val exportedHere = records.filter { it.healthExported == true }.map { it.id }.toSet()
    update {
        var settings = decoded.settings ?: AppSettings()
        // The THIRD door into this decode: a backup taken before v3 migrates
        // here exactly as it does on launch.
        if (decoded.engineStateMigrated) settings = settings.copy(migrationNoticePending = true)
        if (sameLineage) {
            settings = settings.copy(healthExportedThrough = maxOf(priorHealthMark, settings.healthExportedThrough))
        }
        // Whose weight it is, is a fact about THIS DEVICE; the number's date
        // travels, and a backup from before the date gets its newest workout.
        settings = settings.copy(bodyMassFromHealth = false)
        if (settings.bodyMassKg != null && settings.bodyMassDate == null) {
            settings = settings.copy(bodyMassDate = decoded.records.maxOfOrNull { r -> r.date })
        }
        // A half-finished workout does not travel with a restored history.
        val restored = PersistedState(engineState = decoded.engineState, records = decoded.records,
                                      settings = settings, pendingWorkout = null)
            // Old backups carry only the mark — turn whichever won into flags.
            .migratingHealthMarkToFlags()
        // After the mark: a flag set here first would turn that migration
        // into a no-op for a mark-only backup.
        restored.copy(records = restored.records.map { r ->
            if (r.id in exportedHere) r.copy(healthExported = true) else r
        })
    }
    // On iOS the Health switch and the reminder authorization are re-checked
    // here — device-local facts a backup cannot prove. They join with health/
    // and reminders/.
}
