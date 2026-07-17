//
//  AppStoreTests.swift
//  DredfitTests (unit tests for the app target; @testable import Dredfit)
//
//  Persistence, calendar logic, migration of legacy records.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class AppStoreTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-test-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    // MARK: - Initial state and persistence

    func testFreshStoreStartsEmpty() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.totalLevel, 0)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(store.doneToday)
        XCTAssertEqual(store.nextSession.sessionNumber, 1)
    }

    func testCompleteWorkoutPersistsAndReloads() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let skippedPattern = session.exercises[1].pattern
        store.completeWorkout(session: session, result: .more,
                              overrides: [session.exercises[0].pattern: 6],
                              skipped: [skippedPattern])

        // a separate store on the same file sees the same state
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.engineState, store.engineState)
        XCTAssertEqual(reloaded.records.last?.result, .more)
        XCTAssertEqual(reloaded.records.last?.exercises?.count,
                       session.exercises.count, "workout snapshot was not saved")
        XCTAssertEqual(reloaded.records.last?.actuals?[session.exercises[0].pattern], 6)
        // v1.1: skips and the per-pattern level snapshot survive the reload
        XCTAssertEqual(reloaded.records.last?.skipped, [skippedPattern])
        XCTAssertEqual(reloaded.records.last?.levelsAfter, store.engineState.levels)
    }

    func testSkippedExerciseKeepsItsLevel() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let skippedPattern = session.exercises[2].pattern
        store.completeWorkout(session: session, result: .more, skipped: [skippedPattern])
        XCTAssertEqual(store.engineState.levels[skippedPattern], 0,
                       "a skipped pattern must not level up")
        XCTAssertEqual(store.engineState.levels[session.exercises[0].pattern], 2,
                       "a trained pattern must still move by the rating")
        XCTAssertEqual(store.records.last?.skipped, [skippedPattern])
    }

    func testCorruptedStorageFallsBackToInitial() throws {
        try Data("{not a json".utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.records.isEmpty, "a corrupted file should give a clean start, not a crash")
        XCTAssertEqual(store.totalLevel, 0)
    }

    // MARK: - Migration: records without a snapshot

    func testLegacyRecordsWithoutSnapshotDecode() throws {
        // a record format without the exercises/actuals fields.
        // [Pattern: Int] dictionaries are encoded by JSONEncoder as arrays
        // of alternating key/value (Pattern is not CodingKeyRepresentable),
        // not as objects — the fixture must mirror the real format.
        let legacy = """
        {"engineState":{"counter":1,
          "levels":["squat",2,"push_h",2,"hinge",2,"pull",2,"push_v",2,"lunge",2,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[{"sessionNumber":1,"date":700000000,"result":"more","totalLevelAfter":12}]}
        """
        try Data(legacy.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.records.count, 1, "the legacy record did not decode")
        XCTAssertNil(store.records[0].exercises, "a legacy record should have no snapshot")
        XCTAssertNil(store.records[0].actuals)
        XCTAssertNil(store.records[0].skipped, "v1.0 records have no skips")
        XCTAssertNil(store.records[0].levelsAfter, "v1.0 records have no level snapshot")
        XCTAssertEqual(store.totalLevel, 12)
        XCTAssertEqual(store.settings, AppSettings(), "v1.0 files load with default settings")
        // v2.2: pre-bar files load with the bar module off and the branch at zero
        XCTAssertFalse(store.engineState.hasBar, "legacy files must decode with hasBar off")
        XCTAssertEqual(store.engineState.levels[.pullBar], 0)
        XCTAssertEqual(store.engineState.failStreak[.pullBar], 0)
    }

    // MARK: - Pull-up bar (v2.2)

    func testHasBarPersistsAndDrivesAlternation() {
        let store = AppStore(storageURL: tempURL)
        store.setHasBar(true)
        // session 1 (counter 0) stays horizontal even with the bar on
        XCTAssertFalse(store.nextSession.exercises.contains { $0.pattern == .pullBar })
        store.completeWorkout(session: store.nextSession, result: .plan)
        // session 2 (counter 1) trains the vertical branch
        let second = store.nextSession
        XCTAssertTrue(second.exercises.contains { $0.pattern == .pullBar },
                      "with the bar on, the second session must swap in the vertical pull")
        XCTAssertFalse(second.exercises.contains { $0.pattern == .pull })

        // the toggle and the branch snapshot survive a reload
        store.completeWorkout(session: second, result: .more)
        XCTAssertEqual(store.records.last?.levelsAfter?[.pullBar], 2,
                       "the journal snapshot must include the pull_bar level")
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertTrue(reloaded.engineState.hasBar)
        XCTAssertEqual(reloaded.engineState.levels[.pullBar], 2)

        // turning the bar off freezes the branch but keeps its progress
        reloaded.setHasBar(false)
        XCTAssertFalse(reloaded.nextSession.exercises.contains { $0.pattern == .pullBar })
        XCTAssertEqual(reloaded.engineState.levels[.pullBar], 2)
    }

    // MARK: - Calendar logic

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 10))!
    }

    func testIsRestDayOnSundays() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.isRestDay(date(2026, 7, 19)), "Sunday should be a rest day")
        XCTAssertFalse(store.isRestDay(date(2026, 7, 16)), "Thursday is not a rest day")
    }

    func testNextTrainingDateFromFreeWeekday() {
        let store = AppStore(storageURL: tempURL)
        let thursday = date(2026, 7, 16)
        XCTAssertEqual(store.nextTrainingDate(from: thursday), thursday,
                       "no workout today and not a rest day → today")
    }

    func testNextTrainingDateSkipsSunday() {
        let store = AppStore(storageURL: tempURL)
        let sunday = date(2026, 7, 19)
        let next = store.nextTrainingDate(from: sunday)
        XCTAssertTrue(Calendar.current.isDate(next, inSameDayAs: date(2026, 7, 20)),
                      "from Sunday the next workout is on Monday")
    }

    func testNextTrainingDateAfterDoneSaturdaySkipsToMonday() {
        let store = AppStore(storageURL: tempURL)
        let saturday = date(2026, 7, 18)
        store.completeWorkout(session: store.nextSession, result: .plan, date: saturday)
        let next = store.nextTrainingDate(from: saturday)
        XCTAssertTrue(Calendar.current.isDate(next, inSameDayAs: date(2026, 7, 20)),
                      "Saturday completed → next on Monday (Sun is a rest day)")
    }

    func testDoneTodayAndRecordLookup() {
        let store = AppStore(storageURL: tempURL)
        let day = date(2026, 7, 16)
        store.completeWorkout(session: store.nextSession, result: .plan, date: day)
        XCTAssertTrue(store.isDone(on: day))
        XCTAssertFalse(store.isDone(on: date(2026, 7, 17)),
                       "the next day, done should reset without migrations")
        XCTAssertNotNil(store.record(on: day))
        XCTAssertNil(store.record(on: date(2026, 7, 15)))
    }

    // MARK: - A full month of workouts

    func testMonthOfWorkoutsAccumulatesConsistently() {
        let store = AppStore(storageURL: tempURL)
        var day = date(2026, 7, 1)
        var completed = 0
        while completed < 24 {
            if !store.isRestDay(day) {
                store.completeWorkout(session: store.nextSession, result: .plan, date: day)
                completed += 1
            }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        XCTAssertEqual(store.records.count, 24)
        // session numbers are strictly sequential
        XCTAssertEqual(store.records.map(\.sessionNumber), Array(1...24))
        // the progress chart is non-decreasing with a constant "on plan"
        let chart = store.records.map(\.totalLevelAfter)
        XCTAssertEqual(chart, chart.sorted(), "the total level must not drop with \"on plan\"")
        // and survives a reload
        XCTAssertEqual(AppStore(storageURL: tempURL).records.count, 24)
    }

    // MARK: - Settings (v1.1)

    func testSettingsPersistAcrossReload() {
        let store = AppStore(storageURL: tempURL)
        store.toggleRestDay(2)          // Monday joins Sunday
        store.setSounds(false)
        store.setReminderTime(hour: 7, minute: 30)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.settings.restWeekdays, [1, 2])
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

    // MARK: - Backup (v1.1)

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
