//
//  §41.7: a state written before v3 is read and carried over.
//
//  These tests guard the two halves the audit of 26.08.2026 found broken and
//  the owner then reversed: the engine used to be handed `initState` here
//  (§40.8), and the person was told nothing about it.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class MigrationV2Tests: AppStoreTestCase {

    /// A v2 file, in the shape v2 actually wrote: `[Pattern: Int]` as an
    /// UNKEYED array, because `Pattern` never adopted `CodingKeyRepresentable`.
    private func v2Payload(levels: [String: Int], counter: Int, hasBar: Bool) -> Data {
        func pairs(_ m: [String: Int]) -> String {
            m.sorted { $0.key < $1.key }.map { "\"\($0.key)\",\($0.value)" }.joined(separator: ",")
        }
        let json = """
        {"engineState":{"counter":\(counter),"hasBar":\(hasBar),
          "levels":[\(pairs(levels))],
          "failStreak":[\(pairs(levels.mapValues { _ in 1 }))]},
         "records":[],"settings":null}
        """
        return Data(json.utf8)
    }

    func testAV2StateIsCarriedOverRatherThanReset() throws {
        let data = v2Payload(levels: ["squat": 20, "push_h": 12, "pull": 8],
                             counter: 37, hasBar: true)
        let loaded = try JSONDecoder().decode(AppData.self, from: data)

        XCTAssertFalse(loaded.engineStateReset, "a v2 state must be read, not thrown away")
        XCTAssertTrue(loaded.engineStateMigrated, "and the app must know it happened")
        XCTAssertEqual(loaded.engineState.counter, 37, "rotation phase carries over")
        XCTAssertTrue(loaded.engineState.hasBar, "so does the answer about the bar")

        // L=20 is tier 3 in v2, 9 reps. squat's tier 3 maps to variation 5.
        XCTAssertEqual(loaded.engineState.vars[.squat], 5,
                       "the rung v2's tier 3 was earned on, not the first one")
        XCTAssertEqual(loaded.engineState.doses[.squat], 9,
                       "and the dose they were doing there, carried across unchanged")
        // The journal records it: without that the first descent would send
        // them to the floor of a movement they had long since passed.
        XCTAssertEqual(loaded.engineState.shown[.squat]?[5], 9,
                       "the journal has to say they were there, or a descent starts from the floor")
    }

    /// The whole v2 scale, every pattern: 480 cells, measured as REAL WORK on
    /// both sides of the upgrade — `sets × dose × sides`, the quantity
    /// `Engine.planLoad` computes for v3.
    ///
    /// The measure used to be two half-measures and saw neither thing that can
    /// go wrong here. The "before" side read `Engine.v2LevelTable`, the very
    /// table the migration takes its dose from, so an error in that snapshot
    /// cancelled itself out on both sides of the comparison. The "after" side
    /// left out `Library.sides`, so a two-sided v2 tier landing on a one-sided
    /// v3 rung — the same rep count, twice the session — read as no change at
    /// all. `V2FormatSnapshot` now supplies an independent "before", including
    /// v2's own sidedness, which v3 cannot reconstruct: v2's library is gone.
    ///
    /// Ten cells land heavier, and only because v2 could hand out a hold below
    /// v3's grid floor (accepted gap §41.6 item 4, worst ×1.50). They are
    /// LISTED and not counted: "at most ten" is satisfied by ten completely
    /// different cells.
    func test_migration_acrossTheWholeV2Scale_landsHeavierOnlyOnTheTenAcceptedCells() throws {
        var heavier: [String] = []
        var carryingVolumeHandles: [String] = []
        for p in Pattern.allCases {
            for level in V2FormatSnapshot.levelTable.indices {
                let migrated = try XCTUnwrap(
                    Engine.migrateFromV2(Engine.V2State(counter: 1, hasBar: true,
                                                        levels: [p: level])),
                    "a state carrying one level is still a v2 state")
                let pos = migrated.position(p)
                // `Engine.planLoad` also carries a sub-step and a cut. A
                // migration writes neither, and that is what makes the plain
                // product below the WHOLE plan rather than a part of it.
                if pos.sub != 0 || pos.cut != 0 {
                    carryingVolumeHandles.append("\(p.rawValue) L=\(level)")
                }
                let now = pos.sets * pos.dose * Library.sides(p, pos.variation)
                let was = try V2FormatSnapshot.work(p, level: level)
                if now > was { heavier.append("\(p.rawValue) L=\(level): \(was) -> \(now)") }
            }
        }
        XCTAssertEqual(carryingVolumeHandles, [],
                       "nothing may arrive from a migration with sets already cut or a sub-step already "
                       + "owed, or the work compared below is not the whole plan")
        XCTAssertEqual(heavier.sorted(), [
            "core_anti_ext L=24: 30 -> 45",
            "core_anti_ext L=25: 33 -> 45",
            "core_anti_ext L=26: 36 -> 45",
            "core_anti_ext L=27: 39 -> 45",
            "core_anti_ext L=28: 42 -> 45",
            "core_rot L=24: 60 -> 90",
            "core_rot L=25: 66 -> 90",
            "core_rot L=26: 72 -> 90",
            "core_rot L=27: 78 -> 90",
            "core_rot L=28: 84 -> 90",
        ], "§41.6 item 4 accepts exactly these ten: a hold v2 set below v3's floor of 15 s comes UP to "
           + "the floor, because there is nothing lower in the product to land on")
    }

    func testAV3StateIsStillReadAsV3() throws {
        var state = EngineState.initial
        state.counter = 5
        let payload = try JSONEncoder().encode(
            AppData(engineState: state, records: [], settings: AppSettings(), pendingWorkout: nil))
        let loaded = try JSONDecoder().decode(AppData.self, from: payload)
        XCTAssertFalse(loaded.engineStateMigrated, "a v3 state is not a migration")
        XCTAssertFalse(loaded.engineStateReset)
        XCTAssertEqual(loaded.engineState.counter, 5)
    }

    func testGarbageStillFallsBackToACleanStart() throws {
        let data = Data(#"{"engineState":{"nonsense":true},"records":[],"settings":null}"#.utf8)
        let loaded = try JSONDecoder().decode(AppData.self, from: data)
        XCTAssertTrue(loaded.engineStateReset, "not v2 and not v3 — clean start, as before")
        XCTAssertFalse(loaded.engineStateMigrated)
    }

    // MARK: - The one-shot card on Today

    /// The migration is announced ONCE, and the announcement is carried by the
    /// file rather than by the launch that performed it: a person who upgrades,
    /// never opens Today and gets the app killed would otherwise have spent it
    /// without ever seeing it.
    func testTheCardIsPendingAfterAMigrationAndSurvivesARelaunch() throws {
        try v2Payload(levels: ["squat": 20, "pull": 8], counter: 4, hasBar: true)
            .write(to: tempURL)

        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.showsMigrationNotice, "the upgrade must be announced")
        store.persist()   // the file is v3 from here on — the flag has to carry itself

        let onDisk = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: tempURL))
        XCTAssertFalse(onDisk.engineStateMigrated,
                       "the file is v3 from here on, so nothing migrates a second time")
        XCTAssertTrue(AppStore(storageURL: tempURL).showsMigrationNotice,
                      "and the card is still owed")
    }

    func testDismissingTheCardSpendsItForGood() throws {
        try v2Payload(levels: ["squat": 20], counter: 4, hasBar: false).write(to: tempURL)

        let store = AppStore(storageURL: tempURL)
        store.dismissMigrationNotice()
        XCTAssertFalse(store.showsMigrationNotice)
        XCTAssertFalse(AppStore(storageURL: tempURL).showsMigrationNotice,
                       "and it must not come back on the next launch")
    }

    func testAFreshInstallIsNeverToldAboutAMigration() {
        XCTAssertFalse(AppStore(storageURL: tempURL).showsMigrationNotice,
                       "there is nothing to announce to someone with no history")
    }

    /// The THIRD door into the same decode. `AppStore.init` and
    /// `reloadIfNeeded` both stamp the card; `importBackup` did not — and it
    /// then overwrote the flag with the settings out of the very pre-v3 file
    /// it had just migrated. Someone who backs up on 1.9.x, updates, resets
    /// and restores gets their positions carried over and is told nothing —
    /// exactly the silence §41.7 reversed §40.8 to end.
    func testRestoringAPreV3BackupAnnouncesTheMigrationToo() throws {
        let backup = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-v2-backup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: backup) }
        try v2Payload(levels: ["squat": 20, "pull": 8], counter: 4, hasBar: true)
            .write(to: backup)

        let store = AppStore(storageURL: tempURL)
        XCTAssertFalse(store.showsMigrationNotice, "nothing to announce before the restore")

        try store.importBackup(from: backup)

        XCTAssertEqual(store.engineState.vars[.squat], 5,
                       "the restore really did carry the positions over")
        XCTAssertTrue(store.showsMigrationNotice,
                      "restoring a pre-v3 backup is an upgrade too, and has to say so")
        XCTAssertTrue(AppStore(storageURL: tempURL).showsMigrationNotice,
                      "and the card outlives the launch that owed it, like the other two doors")
    }
}
