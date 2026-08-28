//
//  Settings persistence and the export/import backup round trip, moved out
//  of AppStoreTests.swift to keep it under the linter's file and type-body
//  ceilings. Grouped together because both are the same claim about the same
//  data: the persisted settings survive a reload, and survive a full
//  export/import intact too. The code moved unchanged.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Settings
extension AppStoreTests {

    func testSettingsPersistAcrossReload() {
        let store = AppStore(storageURL: tempURL)
        store.toggleRestDay(3)          // Tuesday joins the Mon+Wed+Fri default
        store.setSounds(false)
        store.setReminderTime(hour: 7, minute: 30)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.settings.restWeekdays, [2, 3, 4, 6])
        XCTAssertFalse(reloaded.settings.soundsEnabled)
        XCTAssertEqual(reloaded.settings.reminderHour, 7)
        XCTAssertEqual(reloaded.settings.reminderMinute, 30)
    }

    func testRestDaysFollowSettings() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertFalse(store.isRestDay(date(2026, 7, 16)), "Thursday is not rest by default")
        store.toggleRestDay(5)          // Thursday (Calendar weekday 5)
        XCTAssertTrue(store.isRestDay(date(2026, 7, 16)), "Thursday must follow the setting")
        store.toggleRestDay(5)
        XCTAssertFalse(store.isRestDay(date(2026, 7, 16)))
    }

    func testAtLeastOneTrainingDayRemains() {
        let store = AppStore(storageURL: tempURL)
        for weekday in 1...7 { store.toggleRestDay(weekday) }   // tries to rest all week
        XCTAssertLessThanOrEqual(store.settings.restWeekdays.count, 6,
                                 "the last training day must not become rest")
        // and the next-date search always terminates
        _ = store.nextTrainingDate(from: date(2026, 7, 16))
    }

    // MARK: - Backup

    func testExportImportRoundTrip() throws {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .more,
                              date: date(2026, 7, 16))
        store.toggleRestDay(2)
        let backup = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        // a brand-new store on a different file imports the backup
        let otherURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let fresh = AppStore(storageURL: otherURL)
        XCTAssertTrue(fresh.records.isEmpty)
        try fresh.importBackup(from: backup)

        XCTAssertEqual(fresh.engineState, store.engineState)
        XCTAssertEqual(fresh.records, store.records)
        XCTAssertEqual(fresh.settings, store.settings)
        // and the import persisted
        XCTAssertEqual(AppStore(storageURL: otherURL).records.count, 1)
    }

    func testImportRejectsForeignFile() throws {
        try Data("{\"foo\": 1}".utf8).write(to: tempURL)
        let otherURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-badimport-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let store = AppStore(storageURL: otherURL)
        XCTAssertThrowsError(try store.importBackup(from: tempURL),
                             "a foreign JSON must not import")
        XCTAssertTrue(store.records.isEmpty, "state must stay intact after a failed import")
    }
}
