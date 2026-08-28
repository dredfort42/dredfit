//
//  Lifted out of AppStore.swift, which sits against the linter's class-body
//  ceiling — a CI error, not a style opinion. Both directions refuse to run on
//  a frozen journal: exporting one hands the user a file that destroys their
//  history, importing into one looks like it worked and is gone next launch.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Backup

    enum BackupError: Error {
        /// The journal could not be read on this launch (see journalFrozen).
        case journalUnavailable
    }

    func exportURL() throws -> URL {
        // Exporting the empty in-memory state would hand the user a file that
        // looks like a backup and destroys their history when imported.
        guard !journalFrozen else { throw BackupError.journalUnavailable }
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dredfit-backup-\(stamp).json")
        let data = try JSONEncoder().encode(
            AppData(engineState: engineState, records: records, settings: settings))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Throws when the file is not a Dredfit backup — the caller alerts.
    func importBackup(from url: URL) throws {
        // Restoring into a frozen store would look like it worked and be gone
        // at the next launch.
        guard !journalFrozen else { throw BackupError.journalUnavailable }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AppData.self, from: data)
        // The Health mark tracks an external side effect (HKWorkouts already
        // written) and must never move backwards on import: an older backup
        // would re-export samples the export has no way to notice are already
        // there. The app DOES read workouts now — but only to find one another
        // app recorded over the same minutes, and it filters its own out by
        // bundle id on purpose, so that read is not a duplicate check and
        // cannot become one (`HealthKitWorkoutWriter.foreignIntervals`). That
        // holds for THIS journal only — an unrelated one (another device, a
        // post-reset history) knows nothing about this device's Health store,
        // and inheriting the local mark would stamp its workouts "already
        // exported" and hide them from the backfill forever (issue #103).
        // Same lineage always shares record ids: the journal is append-only
        // and a backup is its snapshot.
        let priorHealthMark = settings.healthExportedThrough
        let currentIDs = Set(records.map(\.id))
        let sameLineage = decoded.records.contains { currentIDs.contains($0.id) }
        engineState = decoded.engineState
        records = decoded.records
        settings = decoded.settings ?? AppSettings()
        // The THIRD door into this decode, and the one that used to drop the
        // announcement: a backup taken before v3 migrates here exactly as it
        // does on launch (§41.7), and the settings that just overwrote the
        // flag came from that same pre-v3 file. `AppStore.init` and
        // `reloadIfNeeded` both stamp it; restoring is not a quieter kind of
        // upgrade.
        if decoded.engineStateMigrated { settings.migrationNoticePending = true }
        // A half-finished workout does not travel with a restored history.
        pendingWorkout = nil
        if sameLineage {
            settings.healthExportedThrough = max(priorHealthMark, settings.healthExportedThrough)
        }
        // Old backups carry only the mark — turn whichever won into flags.
        migrateHealthMarkToFlags()
        persist()
        if settings.reminderEnabled {
            // Authorization is per-device: a backup restored onto a new phone
            // must actually ask, and a denial must flip the toggle off.
            setReminderEnabled(true)
        } else {
            rescheduleReminders()   // clears anything left behind
        }
    }
}
