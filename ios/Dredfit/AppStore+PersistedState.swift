//
//  What the store reads from and writes to its one JSON file, and the
//  four persisted fields as the one value `update` hands a change.
//

import Foundation
import DredfitCore

struct AppData: Codable {
    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings?
    var pendingWorkout: WorkoutSnapshot?
    // How many journal entries failed to decode (not encoded) — the caller
    // keeps the original file aside when this is nonzero.
    var droppedRecordCount = 0

    init(engineState: EngineState, records: [WorkoutRecord],
         settings: AppSettings?, pendingWorkout: WorkoutSnapshot? = nil) {
        self.engineState = engineState
        self.records = records
        self.settings = settings
        self.pendingWorkout = pendingWorkout
    }

    private enum CodingKeys: String, CodingKey {
        case engineState, records, settings, pendingWorkout
    }

    /// True when the engine state on disk was neither v3 nor v2 (a v2 state
    /// is carried over) and the engine started clean; the loader copies the
    /// original aside, and an import refuses the file.
    var engineStateReset = false

    /// True when a settings block was present but not an object this build
    /// can read. On launch it costs the settings their defaults; an import
    /// refuses the file instead.
    var settingsUnreadable = false

    /// True when a state written before v3 was read and carried over.
    /// A property of THIS decode, not of the file: the loader turns it into
    /// `settings.migrationNoticePending`, which is what the file carries and
    /// what the card on Today is spent against.
    var engineStateMigrated = false

    /// The journal decodes record-by-record — one unreadable entry (e.g.
    /// written by a newer version) must not throw away the whole file.
    ///
    /// And the ENGINE STATE decodes leniently for the same reason: a state
    /// written before v3 carries `levels` instead of positions and is read and
    /// carried over, and a state from some future build must not take the
    /// journal and the settings down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let state = try? c.decode(EngineState.self, forKey: .engineState) {
            engineState = state
        } else if let migrated = try? c.decode(V2EngineState.self, forKey: .engineState),
                  let carried = Engine.migrateFromV2(migrated.asEngineInput) {
            // A state written before v3 is READ and carried over, not thrown
            // away: an upgrade must never start anyone over (`MigrationV2`).
            engineState = carried
            engineStateMigrated = true
        } else {
            engineState = .initial
            engineStateReset = true
        }
        // try?, and every field inside it too: one setting of a shape this
        // build does not know must cost that setting, never the journal.
        settings = try? c.decodeIfPresent(AppSettings.self, forKey: .settings)
        settingsUnreadable = settings == nil && c.contains(.settings)
            && !((try? c.decodeNil(forKey: .settings)) ?? false)
        // try?, not try: a snapshot written by a newer version must degrade
        // to "nothing to resume", never to a quarantined journal.
        pendingWorkout = try? c.decodeIfPresent(WorkoutSnapshot.self, forKey: .pendingWorkout)
        var decoded: [WorkoutRecord] = []
        var uc = try c.nestedUnkeyedContainer(forKey: .records)
        while !uc.isAtEnd {
            let index = uc.currentIndex
            if let record = try? uc.decode(WorkoutRecord.self) {
                decoded.append(record)
            } else {
                // Discard's empty init always succeeds, consuming the element.
                _ = try? uc.decode(Discard.self)
                droppedRecordCount += 1
            }
            if uc.currentIndex == index { break }   // safety: never spin in place
        }
        records = decoded
    }

    private struct Discard: Decodable { init(from decoder: Decoder) {} }
}

/// The four things the store persists, as one value a change is made to —
/// see `AppStore.update`.
struct PersistedState {
    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings
    var pendingWorkout: WorkoutSnapshot?

    /// Legacy high-water mark → per-record flags. The mark keeps being
    /// written so a downgraded build still sees a sane value. Runs only on a
    /// journal that carries no flags at all — a pre-flag legacy file. Once
    /// any record is flagged, the flags are the source of truth, and
    /// re-applying the mark could stamp workouts it was never about: a
    /// foreign import's records, or a post-reset session 1 sitting under an
    /// old high mark (issue #103).
    mutating func migrateHealthMarkToFlags() {
        guard settings.healthExportedThrough > 0,
              !records.contains(where: { $0.healthExported != nil }) else { return }
        for i in records.indices
        where records[i].sessionNumber <= settings.healthExportedThrough {
            records[i].healthExported = true
        }
    }
}
