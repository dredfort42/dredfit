//
//  HealthExportTests.swift
//  DredfitTests
//
//  Apple Health export: the contiguous backfill, its failure and retry
//  behaviour, and what happens when the journal moves under an in-flight run.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class HealthExportTests: XCTestCase {

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

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 10))!
    }

    /// A Health spy: records saved intervals, grants or denies on demand,
    /// can simulate save failures (all, or from a given 1-based call), and
    /// can hold one save mid-flight on `gate` so a test can interleave store
    /// mutations with a suspended backfill.
    private final class HealthSpy: WorkoutHealthWriting, @unchecked Sendable {
        var available = true
        var grant = true
        var allFail = false
        var failFromCall: Int?
        var gate: Gate?
        var gateAtCall: Int?
        var saved: [(start: Date, end: Date)] = []
        private(set) var callCount = 0
        var isAvailable: Bool { available }
        func requestWriteAuthorization() async -> Bool { grant }
        func saveWorkout(start: Date, end: Date) async -> Bool {
            callCount += 1
            if callCount == gateAtCall { await gate?.wait() }
            saved.append((start, end))
            if start >= end { return false }   // HealthKit rejects such intervals
            if allFail { return false }
            if let f = failFromCall, callCount >= f { return false }
            return true
        }
    }

    /// A one-shot async gate: `wait()` suspends until `open()`.
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            guard !opened else { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// Runs `backfillHealth` in a child task and returns once the spy's gated
    /// save is actually in flight (suspended inside the gate).
    private func startBackfillAndWaitForGatedSave(
        _ store: AppStore, _ spy: HealthSpy) async -> Task<Void, Never> {
        let backfill = Task { await store.backfillHealth() }
        var spins = 0
        while spy.callCount < (spy.gateAtCall ?? 0) && spins < 10_000 {
            spins += 1
            await Task.yield()
        }
        XCTAssertEqual(spy.callCount, spy.gateAtCall, "the gated save must be in flight")
        return backfill
    }

    /// A failed save must not flag the workout exported — it stays retriable
    /// via a later backfill (no silent data loss).
    func testHealthFailedSaveKeepsWorkoutRetriable() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        spy.allFail = true
        store.completeWorkout(session: store.nextSession, result: .plan, durationSec: 30 * 60)
        await store.healthExportTask?.value
        XCTAssertEqual(spy.saved.count, 1, "the save was attempted")
        XCTAssertEqual(store.healthBackfillCount, 1,
                       "a failed save must not mark the workout exported")
        // the retry succeeds and clears the backlog
        spy.allFail = false
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "the retry exported the missed workout")
        XCTAssertEqual(spy.saved.count, 2)
    }

    /// Regression: a failed live export of workout N followed by a successful
    /// workout N+1 must not advance the high-water mark past N, which would
    /// exclude N from every future backfill.
    func testHealthLaterSuccessDoesNotLoseEarlierFailedExport() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()

        spy.allFail = true
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: date(2026, 7, 14))
        await store.healthExportTask?.value
        XCTAssertEqual(store.healthBackfillCount, 1, "workout 1 stays pending")

        spy.allFail = false
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: date(2026, 7, 16))
        await store.healthExportTask?.value
        XCTAssertEqual(store.healthBackfillCount, 0,
                       "the next workout's export must retry the failed one first")
        XCTAssertEqual(spy.saved.count, 3, "one failed attempt plus both real exports")
        XCTAssertEqual(spy.saved[1].end, date(2026, 7, 14),
                       "the older workout exports before the newer one")
        XCTAssertEqual(spy.saved[2].end, date(2026, 7, 16))
    }

    /// After "Start from scratch" session numbers repeat — record identity
    /// must stay unique and the export state of old workouts must survive.
    func testResetProgressKeepsRecordIdentityAndHealthStateSound() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 10))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 12))
        _ = await store.enableHealth()
        await store.backfillHealth()
        XCTAssertEqual(spy.saved.count, 2)

        store.resetProgress()
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))
        XCTAssertEqual(store.records.last?.sessionNumber, 1,
                       "after the reset the journal reuses session numbers")
        XCTAssertEqual(Set(store.records.map(\.id)).count, store.records.count,
                       "record ids must stay unique across a reset")

        await store.healthExportTask?.value
        XCTAssertEqual(store.healthBackfillCount, 0)
        XCTAssertEqual(spy.saved.count, 3, "only the new workout exports — no duplicates")
        // "Only new ones" after the reset must not unmark or re-export anything
        store.skipHealthBackfill()
        await store.backfillHealth()
        XCTAssertEqual(spy.saved.count, 3, "skip must never re-export handled workouts")
    }

    /// A backfill stops at the first failure and keeps the mark at the last
    /// confirmed export, so the unexported tail can resume later.
    func testHealthBackfillStopsAtFirstFailure() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 15))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))
        _ = await store.enableHealth()

        spy.failFromCall = 2               // session 1 exports, session 2 fails
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 2,
                       "backfill must stop at the first failure, not mark the tail exported")

        spy.failFromCall = nil             // resume
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "the resumed backfill exports the rest")
    }

    /// Regression: replacing the journal (importBackup) while a backfill is
    /// suspended inside a save must not flag, by stale index, a record that
    /// was never exported — the flag must land by record identity or not at
    /// all.
    func testImportDuringInFlightBackfillDoesNotMisflagByStaleIndex() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        for day in [10, 12, 14, 16] {
            store.completeWorkout(session: store.nextSession, result: .plan,
                                  date: date(2026, 7, day))
        }
        _ = await store.enableHealth()

        // A donor backup: three records, Health never enabled there. After
        // the import the high-water mark (2 confirmed saves below) flags the
        // donor's sessions 1–2; session 3 must stay unexported.
        let donorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-donor-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: donorURL) }
        let donor = AppStore(storageURL: donorURL)
        for day in 1...3 {
            donor.completeWorkout(session: donor.nextSession, result: .plan,
                                  date: date(2026, 7, day))
        }
        let backup = try donor.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        // Hold the third save mid-flight (the loop sits past index 2), then
        // replace the journal under it and let the save finish.
        let gate = Gate()
        spy.gate = gate
        spy.gateAtCall = 3
        let backfill = await startBackfillAndWaitForGatedSave(store, spy)
        try store.importBackup(from: backup)
        gate.open()
        await backfill.value

        XCTAssertEqual(store.records.count, 3, "the imported journal must be intact")
        XCTAssertEqual(spy.saved.count, 3, "no further exports against the replaced journal")
        XCTAssertNotEqual(store.records.last?.healthExported, true,
                          "a record that was never saved must not be flagged exported")
        XCTAssertEqual(store.healthBackfillCount, 1,
                       "the imported session 3 stays pending for a real export")
    }

    /// Switching Health off must stop an in-flight backfill at the record
    /// boundary instead of exporting the whole remaining tail.
    func testDisablingHealthStopsAnInFlightBackfill() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        for day in [10, 12, 14] {
            store.completeWorkout(session: store.nextSession, result: .plan,
                                  date: date(2026, 7, day))
        }
        _ = await store.enableHealth()

        let gate = Gate()
        spy.gate = gate
        spy.gateAtCall = 2
        let backfill = await startBackfillAndWaitForGatedSave(store, spy)
        store.disableHealth()
        gate.open()
        await backfill.value

        // The save already in flight lands (it did reach Health) — but the
        // third record must not follow it after the toggle went off.
        XCTAssertEqual(spy.saved.count, 2, "no exports after the toggle went off")
        XCTAssertEqual(store.healthBackfillCount, 1, "the tail stays pending for a re-enable")
    }

    /// A record with a corrupt (negative) duration must not poison the
    /// pipeline: the export interval is clamped to a positive length, so the
    /// save succeeds and the records behind it keep exporting.
    func testNegativeDurationDoesNotPoisonHealthBackfill() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: -20 * 60, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: date(2026, 7, 16))
        _ = await store.enableHealth()
        await store.backfillHealth()

        XCTAssertEqual(store.healthBackfillCount, 0, "both records must export")
        XCTAssertTrue(spy.saved.allSatisfy { $0.start < $0.end },
                      "every exported interval must move forward")
    }

    /// Importing an older backup (no Health mark) must not move the mark
    /// backwards — otherwise re-enabling would re-export samples already in
    /// Health, which the write-only design cannot detect.
    func testImportKeepsHealthMarkMonotonic() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .more, date: date(2026, 7, 16))
        _ = await store.enableHealth()
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "both workouts start out exported")

        // a backup of the same two workouts predating Health support — no healthExportedThrough
        let old = """
        {"engineState":{"counter":2,
          "levels":["squat",2,"push_h",2,"hinge",2,"pull",4,"push_v",2,"lunge",2,
                    "core_anti_ext",1,"core_rot",1,"calf",1],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[
           {"sessionNumber":1,"date":700000000,"result":"plan","totalLevelAfter":12},
           {"sessionNumber":2,"date":700100000,"result":"more","totalLevelAfter":18}],
         "settings":{"restWeekdays":[1],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-oldbackup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try Data(old.utf8).write(to: backupURL)
        try store.importBackup(from: backupURL)

        XCTAssertEqual(store.healthBackfillCount, 0,
                       "an old backup must not reset the mark and re-export handled workouts")
    }

    func testHealthDenialLeavesToggleOff() async {
        let spy = HealthSpy()
        spy.grant = false
        let store = AppStore(storageURL: tempURL, health: spy)
        let granted = await store.enableHealth()
        XCTAssertFalse(granted)
        XCTAssertFalse(store.settings.healthEnabled, "denial must leave the toggle off")
    }

    func testHealthBackfillExportsOnceAndNeverDuplicates() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))

        let granted = await store.enableHealth()
        XCTAssertTrue(granted)
        XCTAssertEqual(store.healthBackfillCount, 2)
        await store.backfillHealth()
        XCTAssertEqual(spy.saved.count, 2, "the backfill must export both past workouts")
        XCTAssertEqual(store.healthBackfillCount, 0)

        // toggling off and on again must not re-export old workouts
        store.disableHealth()
        _ = await store.enableHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "re-enabling must not duplicate")

        // estimate fallback: records without a stored duration — the interval
        // still ends at the record date and has a positive length
        let last = spy.saved.last!
        XCTAssertEqual(last.end, date(2026, 7, 16))
        XCTAssertGreaterThan(last.end.timeIntervalSince(last.start), 10 * 60)
    }

    func testHealthSkipBackfillMarksHistoryHandled() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        _ = await store.enableHealth()
        store.skipHealthBackfill()
        XCTAssertEqual(store.healthBackfillCount, 0)
        XCTAssertTrue(spy.saved.isEmpty, "\"only new ones\" must not export the past")

        // a new workout with a captured duration exports automatically
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 40 * 60, date: date(2026, 7, 16))
        await store.healthExportTask?.value
        XCTAssertEqual(spy.saved.count, 1, "a completed workout must land in Health")
        XCTAssertEqual(spy.saved[0].end.timeIntervalSince(spy.saved[0].start),
                       40 * 60, accuracy: 1, "the actual duration must be used")
    }
}
