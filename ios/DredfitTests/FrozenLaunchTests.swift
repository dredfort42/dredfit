//
//  The frozen launch meeting a state written before v3.
//
//  A launch that cannot READ its state file — data protection before the
//  first unlock, usually — degrades to an empty state and waits for
//  `reloadIfNeeded()`. The rule this suite guards lives in `AppStore.adopt`,
//  the one path a launch and a reload share: a frozen launch is exactly the one
//  that must not swallow the migration announcement.
//
//  It had no test. The cold path was covered (MigrationV2Tests), the freeze
//  was covered (AppStoreTests), and the crossing of the two — the case the
//  line exists for — was reached by nothing: all four callers of
//  `reloadIfNeeded()` in the suite work on a v3 file.
//
//  It matters because the migration card is the ONLY thing that explains the
//  new shape to an upgrading trainee.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class FrozenLaunchTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-frozen" }

    // MARK: - Fixtures

    /// A v2 file in the shape v2 actually wrote: `[Pattern: Int]` as an
    /// UNKEYED array, because `Pattern` never adopted `CodingKeyRepresentable`.
    ///
    /// Deliberately a second copy of MigrationV2Tests' fixture rather than a
    /// shared helper: this suite has to keep asserting against the bytes an
    /// OLD BUILD wrote, and a shared factory is the thing most likely to be
    /// "improved" into the current shape by whoever next touches the other
    /// suite — at which point both suites would still pass and neither would
    /// be testing a migration any more.
    private func v2Payload(levels: [String: Int], counter: Int, hasBar: Bool) -> Data {
        func pairs(_ map: [String: Int]) -> String {
            map.sorted { $0.key < $1.key }.map { "\"\($0.key)\",\($0.value)" }.joined(separator: ",")
        }
        let json = """
        {"engineState":{"counter":\(counter),"hasBar":\(hasBar),
          "levels":[\(pairs(levels))],
          "failStreak":[\(pairs(levels.mapValues { _ in 1 }))]},
         "records":[],"settings":null}
        """
        return Data(json.utf8)
    }

    private func v3Payload(counter: Int) throws -> Data {
        var state = EngineState.initial
        state.counter = counter
        return try JSONEncoder().encode(
            AppData(engineState: state, records: [], settings: AppSettings(), pendingWorkout: nil))
    }

    private func setPermissions(_ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode],
                                              ofItemAtPath: tempURL.path)
    }

    /// A store built over a file it cannot read, with the file left unreadable
    /// for the caller to restore. Asserts the freeze itself: a launch that
    /// quietly READ the file would make every assertion after it vacuous.
    private func frozenStore(over payload: Data) throws -> AppStore {
        try payload.write(to: tempURL)
        try setPermissions(0o000)
        let store = makeStore()
        XCTAssertTrue(store.journalFrozen,
                      "the fixture must actually freeze, or this suite is testing the cold path twice")
        XCTAssertFalse(store.showsMigrationNotice,
                       "nothing has been read yet, so there is nothing to announce yet")
        return store
    }

    // MARK: - The announcement

    func test_frozenLaunch_reloadingAV2StateOnceReadable_stillAnnouncesTheMigration() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let store = try frozenStore(over: v2Payload(levels: ["squat": 20, "pull": 8],
                                                    counter: 37, hasBar: true))
        defer { try? setPermissions(0o644) }

        try setPermissions(0o644)
        store.reloadIfNeeded()

        XCTAssertFalse(store.journalFrozen, "the reload must lift the freeze it was written for")
        XCTAssertEqual(store.engineState.counter, 37,
                       "the v2 state must actually have been carried over, or the flag below means nothing")
        XCTAssertTrue(store.showsMigrationNotice,
                      "a frozen launch is exactly the launch that must not swallow the announcement: "
                      + "the card is the only thing that explains the new shape to an upgrading trainee")
    }

    func test_frozenLaunch_reloadingAV3StateOnceReadable_announcesNothing() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let payload = try v3Payload(counter: 5)
        let store = try frozenStore(over: payload)
        defer { try? setPermissions(0o644) }

        try setPermissions(0o644)
        store.reloadIfNeeded()

        XCTAssertEqual(store.engineState.counter, 5, "the v3 state loads on the reload as it always did")
        XCTAssertFalse(store.showsMigrationNotice,
                       "nothing migrated, so nobody is told anything — without this the test above would "
                       + "pass just as well against a flag that is always true")
    }

    func test_frozenLaunch_thatWasAlreadyUsed_defersTheAnnouncementInsteadOfSpendingIt() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let payload = v2Payload(levels: ["squat": 20, "pull": 8], counter: 37, hasBar: true)
        let store = try frozenStore(over: payload)
        defer { try? setPermissions(0o644) }
        store.setSounds(false)   // any mutation — from here the launch owns state of its own

        try setPermissions(0o644)
        store.reloadIfNeeded()

        XCTAssertTrue(store.journalFrozen,
                      "a used launch stays frozen: reloading over work already done erases it silently")
        XCTAssertFalse(store.showsMigrationNotice,
                       "and it announces nothing, because it has still not read the v2 state")
        XCTAssertEqual(try Data(contentsOf: tempURL), payload,
                       "the v2 file itself must be untouched — that is what carries the announcement on")
        XCTAssertTrue(makeStore().showsMigrationNotice,
                      "so the very next launch announces it: deferred, never spent")
    }

    // MARK: - Starting a workout

    func test_frozenLaunch_cannotStartAWorkout_andRetryingTheReadLiftsThat() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let store = try frozenStore(over: v3Payload(counter: 5))
        defer { try? setPermissions(0o644) }
        XCTAssertFalse(store.canStartWorkout,
                       "a workout done now is kept in memory only, and the person must be told instead")

        store.activate()   // what the card's Try again calls — still unreadable
        XCTAssertFalse(store.canStartWorkout, "a read that fails again changes nothing")

        try setPermissions(0o644)
        store.activate()
        XCTAssertTrue(store.canStartWorkout, "the second read lifts the freeze, and Start comes back")
    }

    func test_frozenLaunch_retryingTheWrite_doesNotPinTheFreeze() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let store = try frozenStore(over: v3Payload(counter: 5))
        defer { try? setPermissions(0o644) }

        store.retryPersist()
        try setPermissions(0o644)
        store.reloadIfNeeded()

        XCTAssertFalse(store.journalFrozen,
                       "an empty retry is not work done on this launch — counting it would pin the freeze "
                       + "and leave only a relaunch")
        XCTAssertEqual(store.engineState.counter, 5)
    }

    // MARK: - What the reload finds

    /// The copies a read put aside for this test's file.
    private func corruptCopies() throws -> [URL] {
        let stem = tempURL.deletingPathExtension().lastPathComponent + ".corrupt"
        return try FileManager.default
            .contentsOfDirectory(at: tempURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(stem) }
    }

    private func removeCorruptCopies() {
        for url in (try? corruptCopies()) ?? [] { try? FileManager.default.removeItem(at: url) }
    }

    func test_frozenLaunch_reloadingAFileThatNoLongerDecodes_movesItAsideAndThaws() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let garbage = Data("not a state file".utf8)
        let store = try frozenStore(over: garbage)
        defer { removeCorruptCopies() }

        try setPermissions(0o644)
        store.reloadIfNeeded()

        XCTAssertFalse(store.journalFrozen,
                       "a file that will never decode must not keep the launch frozen for good")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "moved, so the next write cannot land on the only copy")
        XCTAssertEqual(try corruptCopies().map { try Data(contentsOf: $0) }, [garbage])
    }

    func test_frozenLaunch_reloadingAPartlyReadableFile_keepsWhatReadsAndACopyOfTheRest() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let record = WorkoutRecord(sessionNumber: 1, date: Date(timeIntervalSince1970: 1_800_000_000),
                                   result: .plan)
        let payload = try JSONSerialization.data(withJSONObject: [
            "engineState": ["from": "a future build"],
            "records": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)),
                        ["from": "a future build"]]
        ])
        let store = try frozenStore(over: payload)
        defer { try? setPermissions(0o644); removeCorruptCopies() }

        try setPermissions(0o644)
        store.reloadIfNeeded()

        XCTAssertFalse(store.journalFrozen)
        XCTAssertEqual(store.records.count, 1, "the readable entry loads on the reload")
        XCTAssertEqual(store.engineState, .initial, "a state neither shape reads starts clean")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "copied, not moved")
        XCTAssertEqual(try corruptCopies().map { try Data(contentsOf: $0) }, [payload],
                       "the state and the dropped entry can still be recovered from the copy")
    }
}
