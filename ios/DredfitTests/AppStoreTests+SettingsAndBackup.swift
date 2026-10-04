//
//  Settings persistence and the export/import backup round trip, in their
//  own file to keep AppStoreTests.swift under the linter's file and
//  type-body ceilings. Grouped together because both are the same claim about
//  the same data: the persisted settings survive a reload, and survive a full
//  export/import intact too.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Settings
extension AppStoreTests {

    func testSettingsPersistAcrossReload() {
        let store = makeStore()
        store.toggleRestDay(3)          // Tuesday joins the Mon+Wed+Fri default
        store.setSounds(false)
        store.setReminderTime(hour: 7, minute: 30)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.settings.restWeekdays, [2, 3, 4, 6])
        XCTAssertFalse(reloaded.settings.soundsEnabled)
        XCTAssertEqual(reloaded.settings.reminderHour, 7)
        XCTAssertEqual(reloaded.settings.reminderMinute, 30)
    }

    func testRestDaysFollowSettings() {
        let store = makeStore()
        XCTAssertFalse(store.isRestDay(date(2026, 7, 16)), "Thursday is not rest by default")
        store.toggleRestDay(5)          // Thursday (Calendar weekday 5)
        XCTAssertTrue(store.isRestDay(date(2026, 7, 16)), "Thursday must follow the setting")
        store.toggleRestDay(5)
        XCTAssertFalse(store.isRestDay(date(2026, 7, 16)))
    }

    func testAtLeastOneTrainingDayRemains() {
        let store = makeStore()
        for weekday in 1...7 { store.toggleRestDay(weekday) }   // tries to rest all week
        XCTAssertLessThanOrEqual(store.settings.restWeekdays.count, 6,
                                 "the last training day must not become rest")
        // and the next-date search always terminates
        _ = store.nextTrainingDate(from: date(2026, 7, 16))
    }

    // MARK: - Backup

    func testExportImportRoundTrip() throws {
        let store = makeStore()
        store.completeWorkout(session: store.nextSession, result: .more,
                              date: date(2026, 7, 16))
        store.toggleRestDay(2)
        let backup = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        // a brand-new store on a different file imports the backup
        let otherURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let fresh = makeStore(storageURL: otherURL)
        XCTAssertTrue(fresh.records.isEmpty)
        try fresh.importBackup(from: backup)

        XCTAssertEqual(fresh.engineState, store.engineState)
        XCTAssertEqual(fresh.records, store.records)
        XCTAssertEqual(fresh.settings, store.settings)
        // and the import persisted
        XCTAssertEqual(makeStore(storageURL: otherURL).records.count, 1)
    }

    /// The file carries the weight: an export replaces the previous one
    /// instead of leaving a copy behind in tmp.
    func testExportKeepsOnlyTheLatestFile() throws {
        let store = makeStore()
        let first = try store.exportURL()
        let second = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }
        let folder = second.deletingLastPathComponent()
        XCTAssertEqual(first.deletingLastPathComponent(), folder)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(left, [second.lastPathComponent])
        XCTAssertNoThrow(try Data(contentsOf: second))
    }

    func testImportRejectsForeignFile() throws {
        try Data("{\"foo\": 1}".utf8).write(to: tempURL)
        let otherURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-badimport-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let store = makeStore(storageURL: otherURL)
        XCTAssertThrowsError(try store.importBackup(from: tempURL),
                             "a foreign JSON must not import")
        XCTAssertTrue(store.records.isEmpty, "state must stay intact after a failed import")
    }

    /// One setting of an unexpected shape costs that setting, never the
    /// journal beside it.
    func testAMalformedSettingDoesNotCostTheJournal() throws {
        let store = makeStore()
        store.completeWorkout(session: store.nextSession, result: .plan)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: tempURL))
            as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings["soundsEnabled"] = "loud"
        settings["reminderHour"] = 99
        json["settings"] = settings
        try JSONSerialization.data(withJSONObject: json).write(to: tempURL)

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.records.count, 1, "the journal must survive")
        XCTAssertTrue(relaunched.settings.soundsEnabled, "the bad field falls back to its default")
        XCTAssertEqual(relaunched.settings.reminderHour, 23, "held to the clock")
    }

    /// The lenient launch decode reads `{"records":[]}` as a clean start. As
    /// an import it would replace a whole history with nothing.
    func testImportRefusesAFileItCannotReadInFull() throws {
        let otherURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-partial-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let store = makeStore(storageURL: otherURL)
        store.completeWorkout(session: store.nextSession, result: .plan)
        let before = store.engineState
        for junk in [#"{"records":[]}"#, #"{"engineState":{"nonsense":true},"records":[]}"#] {
            try Data(junk.utf8).write(to: tempURL)
            XCTAssertThrowsError(try store.importBackup(from: tempURL), junk)
            XCTAssertEqual(store.records.count, 1, "the journal must survive a refused import")
            XCTAssertEqual(store.engineState, before)
        }
        // A whole backup whose settings block is not an object: on launch
        // that costs the settings their defaults, as an import it is refused.
        let backup = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: backup))
            as? [String: Any])
        json["settings"] = 42
        try JSONSerialization.data(withJSONObject: json).write(to: tempURL)
        XCTAssertThrowsError(try store.importBackup(from: tempURL))
        XCTAssertEqual(store.records.count, 1)
    }
}
