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
        XCTAssertEqual(loaded.engineState.vars[.squat], 5)
        XCTAssertEqual(loaded.engineState.doses[.squat], 9)
        // The journal records it: without that the first descent would send
        // them to the floor of a movement they had long since passed.
        XCTAssertEqual(loaded.engineState.shown[.squat]?[5], 9)
    }

    func testTheMigrationNeverLandsHeavierAcrossTheWholeScale() throws {
        // The whole v2 scale, every pattern: 480 cells. Ten of them land
        // heavier and only because v2 could hand out a hold below v3's grid
        // floor — accepted gap §41.6 item 4, worst ×1.50.
        var heavier = 0
        for p in Pattern.allCases {
            for level in 0...47 {
                let migrated = try XCTUnwrap(
                    Engine.migrateFromV2(Engine.V2State(counter: 1, hasBar: true,
                                                        levels: [p: level])))
                let pos = migrated.position(p)
                let unit = Library.unit(p, pos.variation)
                let entry = Engine.v2LevelTable[level]
                let was = entry[1] * (unit == .hold ? entry[3] : entry[2])
                // The port exposes no public measure of work and does not need
                // one for this: after a migration the set count is either the
                // base band or the top variation's, and both are read off the
                // state.
                let now = (migrated.sets[p] ?? EngineConfig.setsBase) * pos.dose
                if now > was { heavier += 1 }
            }
        }
        XCTAssertLessThanOrEqual(heavier, 10,
                                 "§41.6 item 4 names ten cells; more means the mapping slipped")
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
}
