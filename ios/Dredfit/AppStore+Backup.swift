//
//  The backup, out and back in, kept out of AppStore.swift, which stands near
//  the linter's file_length ceiling — a CI error. Both directions refuse to
//  run on a frozen journal: exporting one hands the user a file that destroys
//  their history, importing into one looks like it worked and is gone next
//  launch.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Backup

    enum BackupError: Error {
        /// The journal could not be read on this launch (see journalFrozen).
        case journalUnavailable
        /// The file decoded only in part — see `importBackup`.
        case incompleteBackup
    }

    func exportURL() throws -> URL {
        // Exporting the empty in-memory state would hand the user a file that
        // looks like a backup and destroys their history when imported.
        guard !journalFrozen else { throw BackupError.journalUnavailable }
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        // The file carries the weight, so no copy should outlive the next
        // export: a folder emptied each time keeps at most one in tmp and
        // still lets the person see a dated name. The previous share sheet
        // is closed by the time the row can be tapped again.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Backup", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Dredfit-backup-\(stamp).json")
        let data = try JSONEncoder().encode(
            AppData(engineState: engineState, records: records, settings: settings))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Throws when the file is not a Dredfit backup this build can read in
    /// full — the caller alerts.
    func importBackup(from url: URL) throws {
        // Restoring into a frozen store would look like it worked and be gone
        // at the next launch.
        guard !journalFrozen else { throw BackupError.journalUnavailable }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AppData.self, from: data)
        // All or nothing. `AppData` decodes LENIENTLY because on launch the
        // file is the only copy of the journal. An import has a second copy —
        // the file itself — so one this build cannot read IN FULL is refused
        // before anything moves: a newer build's backup, a damaged one, or
        // none at all (`{"records":[]}` decodes, and would replace a whole
        // history with an empty one). Every backup a release has written reads
        // in full: v2 migrates (`Engine.migrateFromV2`).
        guard !decoded.engineStateReset, !decoded.settingsUnreadable,
              decoded.droppedRecordCount == 0 else {
            throw BackupError.incompleteBackup
        }
        // The Health mark tracks an external side effect (HKWorkouts already
        // written) and must never move backwards on import: an older backup
        // would re-export samples the export has no way to tell apart. The
        // lookup by journal id (`ownWorkoutExists`) only catches workouts
        // written since the id was tagged on — every earlier build's are
        // untagged and invisible to it, so the mark is still the guard. That
        // holds for THIS journal only — an unrelated one (another device, a
        // post-reset history) knows nothing about this device's Health store,
        // and inheriting the local mark would stamp its workouts "already
        // exported" and hide them from the backfill forever (issue #103).
        // Same lineage always shares record ids: the journal is append-only
        // and a backup is its snapshot.
        let priorHealthMark = settings.healthExportedThrough
        let currentIDs = Set(records.map(\.id))
        let sameLineage = decoded.records.contains { currentIDs.contains($0.id) }
        // Flags are facts about THIS device's Health store: an entry exported
        // here since the backup was taken stays exported, or the backfill
        // writes it a second time.
        let exportedHere = Set(records.filter { $0.healthExported == true }.map(\.id))
        update { state in
            state = PersistedState(engineState: decoded.engineState,
                                   records: decoded.records,
                                   settings: decoded.settings ?? AppSettings(),
                                   // A half-finished workout does not travel
                                   // with a restored history.
                                   pendingWorkout: nil)
            // The THIRD door into this decode: a backup taken before v3
            // migrates here exactly as it does on launch, and the settings that
            // just overwrote the flag came from that same pre-v3 file.
            // `AppStore.init` and `reloadIfNeeded` both stamp it; restoring is
            // not a quieter kind of upgrade.
            if decoded.engineStateMigrated { state.settings.migrationNoticePending = true }
            if sameLineage {
                state.settings.healthExportedThrough = max(priorHealthMark,
                                                           state.settings.healthExportedThrough)
            }
            // Whose weight it is, is a fact about THIS DEVICE — same class as
            // the export mark above and as the reminder authorization below,
            // and a backup cannot prove any of them. Left inherited, a restore
            // onto a new phone would show an imported number under "From
            // Health" while this device's Health had never been asked. The
            // flag names the origin in the caption, nothing more; a later
            // Health sample re-earns it, an older one does not
            // (`refreshBodyMassFromHealth`).
            state.settings.bodyMassFromHealth = false
            // The number's DATE does travel: it says when the weight was
            // stated, and that is a fact about the person, not the device. A
            // backup from before the date was kept gets the newest workout in
            // it as the date — the number was in force at least until then —
            // so the first activation compares it with Health's sample instead
            // of letting a stale scale reading overwrite a restored weight.
            if state.settings.bodyMassKg != nil, state.settings.bodyMassDate == nil {
                state.settings.bodyMassDate = state.records.map(\.date).max()
            }
            // Old backups carry only the mark — turn whichever won into flags.
            state.migrateHealthMarkToFlags()
            // After the mark: a flag set here first would turn that migration
            // into a no-op for a mark-only backup.
            for i in state.records.indices where exportedHere.contains(state.records[i].id) {
                state.records[i].healthExported = true
            }
        }
        // The switch is a device-local fact, like the reminder authorization
        // below: a backup cannot prove this phone ever granted the share.
        // Not asked here — the restored workouts go through the backfill
        // choice when the person turns it back on.
        reconcileHealthAuthorization()
        if settings.reminderEnabled {
            // Authorization is per-device: a backup restored onto a new phone
            // must actually ask, and a denial must flip the toggle off.
            setReminderEnabled(true)
        } else {
            rescheduleReminders()   // clears anything left behind
        }
    }
}
