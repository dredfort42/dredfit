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

    /// v1.6: an unreadable state file is moved aside, not silently replaced —
    /// the journal must stay recoverable after the next persist().
    func testCorruptedStorageIsQuarantinedNotOverwritten() throws {
        try Data("{not a json".utf8).write(to: tempURL)
        let corruptURL = tempURL.deletingLastPathComponent()
            .appendingPathComponent(tempURL.deletingPathExtension().lastPathComponent + ".corrupt.json")
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        let store = AppStore(storageURL: tempURL)
        store.setSounds(false)   // any persisted mutation
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path),
                      "the unreadable file must be kept aside")
        XCTAssertEqual(try Data(contentsOf: corruptURL), Data("{not a json".utf8),
                       "the quarantined copy must be the original bytes")
    }

    /// v1.6: one unreadable journal entry (e.g. written by a newer version)
    /// must not throw away the readable rest of the file.
    func testOneBadRecordDoesNotDropTheJournal() throws {
        let mixed = """
        {"engineState":{"counter":2,
          "levels":["squat",2,"push_h",2,"hinge",2,"pull",2,"push_v",2,"lunge",2,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[
           {"sessionNumber":1,"date":700000000,"result":"plan","totalLevelAfter":12},
           {"sessionNumber":2,"date":"not-a-date","result":"someday","totalLevelAfter":18}]}
        """
        try Data(mixed.utf8).write(to: tempURL)
        let corruptURL = tempURL.deletingLastPathComponent()
            .appendingPathComponent(tempURL.deletingPathExtension().lastPathComponent + ".corrupt.json")
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.records.count, 1, "the readable record must survive")
        XCTAssertEqual(store.records.first?.sessionNumber, 1)
        XCTAssertEqual(store.totalLevel, 12, "engine state must load untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path),
                      "the full original must be kept aside when entries are dropped")
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

    // MARK: - Apple Health (v1.3)

    /// A Health spy: records saved intervals, grants or denies on demand,
    /// and can simulate save failures (all, or from a given 1-based call).
    private final class HealthSpy: WorkoutHealthWriting, @unchecked Sendable {
        var available = true
        var grant = true
        var allFail = false
        var failFromCall: Int?
        var saved: [(start: Date, end: Date)] = []
        private var callCount = 0
        var isAvailable: Bool { available }
        func requestWriteAuthorization() async -> Bool { grant }
        func saveWorkout(start: Date, end: Date) async -> Bool {
            callCount += 1
            saved.append((start, end))
            if allFail { return false }
            if let f = failFromCall, callCount >= f { return false }
            return true
        }
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

    /// Regression (v1.6): a failed live export of workout N followed by a
    /// successful workout N+1 used to advance the high-water mark past N,
    /// excluding it from every future backfill — a permanent, invisible hole.
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

    /// v1.6: after "Start from scratch" session numbers repeat, which used to
    /// poison every mechanism keyed on them — record identity stays unique and
    /// the export state of old workouts survives untouched.
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

        // a pre-1.3 backup of the same two workouts — no healthExportedThrough
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

        // estimate fallback: pre-1.3 records carry no duration — the interval
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

    func testV11SettingsFileLoadsWithHealthDefaults() throws {
        // a v1.1-era file: settings exist but know nothing about Health
        let v11 = """
        {"engineState":{"counter":0,
          "levels":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[],
         "settings":{"restWeekdays":[1,2],"soundsEnabled":false,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(v11.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.settings.restWeekdays, [1, 2], "old settings must survive")
        XCTAssertFalse(store.settings.soundsEnabled)
        XCTAssertFalse(store.settings.healthEnabled, "Health defaults off for old files")
        XCTAssertEqual(store.settings.healthExportedThrough, 0)
        XCTAssertFalse(store.settings.onboardingCompleted, "v1.4 onboarding flag defaults off")
        XCTAssertNil(store.settings.lastReviewRequestAt, "v1.4 review stamp defaults to never")
    }

    /// A v1.3-era file knows about Health but not about the v1.4 fields. It must
    /// keep every v1.3 value and gain the new ones at their defaults.
    func testV13SettingsFileLoadsWithWaveFourDefaults() throws {
        let v13 = """
        {"engineState":{"counter":4,
          "levels":["squat",3,"push_h",2,"hinge",1,"pull",4,"push_v",0,"lunge",2,
                    "core_anti_ext",1,"core_rot",0,"calf",3,"pull_bar",5],
          "failStreak":["squat",0,"push_h",1,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0,"pull_bar",0],
          "hasBar":true},
         "records":[],
         "settings":{"restWeekdays":[1,4],"soundsEnabled":true,
                     "reminderEnabled":true,"reminderHour":7,"reminderMinute":30,
                     "healthEnabled":true,"healthExportedThrough":3}}
        """
        try Data(v13.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        // everything v1.3 knew about survives untouched
        XCTAssertEqual(store.settings.restWeekdays, [1, 4])
        XCTAssertEqual(store.settings.reminderHour, 7)
        XCTAssertEqual(store.settings.reminderMinute, 30)
        XCTAssertTrue(store.settings.healthEnabled)
        XCTAssertEqual(store.settings.healthExportedThrough, 3)
        XCTAssertTrue(store.engineState.hasBar)
        XCTAssertEqual(store.engineState.levels[.pullBar], 5)
        // and the v1.4 fields arrive at their defaults
        XCTAssertFalse(store.settings.onboardingCompleted)
        XCTAssertNil(store.settings.lastReviewRequestAt)
    }

    // MARK: - Onboarding gate (v1.4)

    func testOnboardingShowsOnceOnAFreshInstall() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.shouldShowOnboarding, "a fresh install must see it")

        store.completeOnboarding()
        XCTAssertFalse(store.shouldShowOnboarding, "not twice in the same run")
        XCTAssertFalse(AppStore(storageURL: tempURL).shouldShowOnboarding,
                       "and not after a relaunch either")
    }

    func testOnboardingIsSkippedForUsersWithHistory() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan)
        // a user upgrading from 1.3 has history but no flag — still no onboarding
        XCTAssertFalse(store.settings.onboardingCompleted)
        XCTAssertFalse(store.shouldShowOnboarding,
                       "history means the app has already been learned")
    }

    // MARK: - App Store review gate (v1.4)

    /// Every condition satisfied — and only then — produces a request.
    func testReviewGateAsksWhenEveryConditionHolds() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<AppStore.reviewMinWorkouts {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertEqual(store.engineState.counter, 5)
        XCTAssertTrue(store.shouldRequestReview(lastResult: .plan))
        XCTAssertTrue(store.shouldRequestReview(lastResult: .more))
    }

    func testReviewGateStaysSilentBelowTheWorkoutFloor() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<(AppStore.reviewMinWorkouts - 1) {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertEqual(store.engineState.counter, 4)
        XCTAssertFalse(store.shouldRequestReview(lastResult: .plan),
                       "four workouts is too early to ask")
    }

    /// A workout the user found too hard is the wrong moment to ask.
    func testReviewGateStaysSilentAfterAToughSession() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<AppStore.reviewMinWorkouts {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertFalse(store.shouldRequestReview(lastResult: .less))
        XCTAssertFalse(store.shouldRequestReview(lastResult: nil))
    }

    func testReviewGateRespectsTheSixtyDayCooldown() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<AppStore.reviewMinWorkouts {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        store.recordReviewRequest(at: now)

        let cal = Calendar.current
        let justUnder = cal.date(byAdding: .day, value: AppStore.reviewMinDaysBetween - 1, to: now)!
        let exactly = cal.date(byAdding: .day, value: AppStore.reviewMinDaysBetween, to: now)!
        XCTAssertFalse(store.shouldRequestReview(lastResult: .plan, now: justUnder),
                       "59 days is still inside the cooldown")
        XCTAssertTrue(store.shouldRequestReview(lastResult: .plan, now: exactly),
                      "60 days clears it")
    }

    /// The v1.4 fields must round-trip through a save/reload like every other
    /// setting — the onboarding must not reappear after a relaunch.
    func testWaveFourSettingsSurviveReload() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertFalse(store.settings.onboardingCompleted)
        store.completeOnboarding()
        let stamp = Date(timeIntervalSince1970: 1_784_000_000)
        store.recordReviewRequest(at: stamp)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertTrue(reloaded.settings.onboardingCompleted,
                      "the onboarding flag must survive a relaunch")
        XCTAssertEqual(reloaded.settings.lastReviewRequestAt, stamp)
    }

    // MARK: - Widget snapshot (v1.3)

    /// v1.6: the snapshot URL is injected, so this runs everywhere — it used
    /// to XCTSkip on every unsigned (CI) run and read as green coverage.
    func testWidgetSnapshotMirrorsWeekStatuses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        store.completeWorkout(session: store.nextSession, result: .plan)   // today → done

        let snap = try JSONDecoder().decode(WidgetSnapshot.self,
                                            from: Data(contentsOf: url))
        XCTAssertEqual(snap.days.count, 7, "the snapshot must cover 7 days")
        XCTAssertEqual(snap.days[0].date, Calendar.current.startOfDay(for: .now))
        XCTAssertEqual(snap.days[0].status, .done)
        for day in snap.days.dropFirst() {
            XCTAssertEqual(day.status, store.isRestDay(day.date) ? .rest : .workout,
                           "future days must mirror the rest-day settings")
            XCTAssertNil(day.sessionNumber, "only today carries a session number")
        }
    }

    // MARK: - Week summary (v1.3)

    func testWeekSummaryUsesMondayFirstIsoWeeks() {
        let store = AppStore(storageURL: tempURL)
        // Sunday Jul 12, 2026 closes the ISO week Mon Jul 6 – Sun Jul 12.
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 12))
        let sundayLevel = store.records.last!.totalLevelAfter
        // Monday Jul 13 opens the next ISO week Mon Jul 13 – Sun Jul 19.
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .more, date: date(2026, 7, 16))
        let last = store.records.last!.totalLevelAfter

        // The week of Wed Jul 15 must contain ONLY the two Mon–Sun workouts.
        // A Sunday-first calendar (US default) would wrongly pull in Jul 12 —
        // this asserts the Monday boundary, which the old Fri/Tue dates could not.
        let thisWeek = store.weekSummary(for: date(2026, 7, 15))
        XCTAssertEqual(thisWeek.workouts, 2,
                       "the Sunday-Jul-12 workout must fall in the previous ISO week")
        XCTAssertEqual(thisWeek.levelsDelta, last - sundayLevel,
                       "the delta counts from the last record before Monday")

        // The Sunday workout belongs to the previous ISO week on its own.
        let prevWeek = store.weekSummary(for: date(2026, 7, 12))
        XCTAssertEqual(prevWeek.workouts, 1, "Sunday closes the previous ISO week")
        XCTAssertEqual(prevWeek.levelsDelta, sundayLevel, "the first week counts from zero")
    }

    func testWeekSummaryEmptyWeekIsZero() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .more, date: date(2026, 7, 10))
        let week = store.weekSummary(for: date(2026, 7, 22))
        XCTAssertEqual(week, AppStore.WeekSummary(workouts: 0, levelsDelta: 0),
                       "a week without workouts must read 0 · +0, not carry old gains")
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
