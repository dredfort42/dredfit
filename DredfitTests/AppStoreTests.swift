//
//  AppStoreTests.swift
//  DredfitTests
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
        // skips and the per-pattern level snapshot survive the reload
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

    // MARK: - Discomfort

    func testDiscomfortFreezesThePatternAndIsRecorded() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let sore = session.exercises[2].pattern
        store.completeWorkout(session: session, result: .more, discomfort: [sore])

        XCTAssertEqual(store.engineState.levels[sore], 0, "a painful pattern must not level up")
        XCTAssertEqual(store.engineState.freezeRemaining(sore),
                       EngineConfig.freezeAppearances, "and it is resting afterwards")
        XCTAssertEqual(store.engineState.levels[session.exercises[0].pattern], 2,
                       "its neighbours still move by the rating")

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.records.last?.discomfort, [sore],
                       "the journal keeps the report apart from a plain skip")
        XCTAssertEqual(reloaded.engineState.freezeRemaining(sore),
                       EngineConfig.freezeAppearances, "the freeze survives a reload")
    }

    /// Today only mentions a resting movement while it is actually in the plan.
    func testRestingPatternsFollowTheUpcomingPlan() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let sore = session.exercises[2].pattern
        store.completeWorkout(session: session, result: .plan, discomfort: [sore])

        let inNextPlan = store.nextSession.exercises.map(\.pattern).contains(sore)
        XCTAssertEqual(store.restingPatterns.contains(sore), inNextPlan)
        XCTAssertTrue(store.restingPatterns.allSatisfy {
            store.engineState.freezeRemaining($0) > 0
        })
    }

    /// A painful exercise was not performed, so it cannot earn a "new
    /// variation" badge either.
    func testAPainfulExerciseIsNotCountedAsPerformed() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let sore = session.exercises[2].pattern
        store.completeWorkout(session: session, result: .plan, discomfort: [sore])
        XCTAssertFalse(store.records.last?.exercises == nil)
        XCTAssertEqual(store.records.last?.skipped, nil, "a report is not a skip")
    }

    // MARK: - Hold this level (#78)

    /// Mirror of the discomfort case with the one difference that defines the
    /// input: the session is processed — growth clamps instead of the session
    /// being voided — and the journal keeps the request apart from both.
    func testAPinFreezesThePatternAndIsRecorded() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let heldPattern = session.exercises[2].pattern
        store.completeWorkout(session: session, result: .more, pinned: [heldPattern])

        XCTAssertEqual(store.engineState.levels[heldPattern], 0, "a pinned pattern must not level up")
        XCTAssertEqual(store.engineState.freezeRemaining(heldPattern),
                       EngineConfig.freezeAppearances, "and it is not climbing afterwards")
        XCTAssertEqual(store.engineState.levels[session.exercises[0].pattern], 2,
                       "its neighbours still move by the rating")

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.records.last?.pinned, [heldPattern],
                       "the journal keeps the request apart from a skip and a report")
        XCTAssertEqual(reloaded.records.last?.skipped, nil, "a pin is not a skip")
        XCTAssertEqual(reloaded.engineState.freezeRemaining(heldPattern),
                       EngineConfig.freezeAppearances, "the rest survives a reload")
    }

    /// Today's horizon line covers both entrances — a pin arms the same rest.
    func testRestingPatternsCoverAPinnedMovement() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let heldPattern = session.exercises[2].pattern
        store.completeWorkout(session: session, result: .plan, pinned: [heldPattern])
        let inNextPlan = store.nextSession.exercises.map(\.pattern).contains(heldPattern)
        XCTAssertEqual(store.restingPatterns.contains(heldPattern), inNextPlan)
    }

    /// The sign that flips against discomfort: a pinned exercise WAS
    /// performed, so its tier counts toward the debut history — while the
    /// painful one was not. v2.11 (spec §21) moves where that shows: the
    /// report unloads the movement to the previous tier, so the badge
    /// question returns only when the user climbs back — and tier 2, never
    /// actually performed, debuts then.
    func testAPinnedExerciseCountsAsPerformedWhereAPainfulOneDoesNot() {
        let hurtURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: hurtURL) }
        for (url, pin) in [(tempURL!, true), (hurtURL, false)] {
            let store = AppStore(storageURL: url)
            // Walk pull to tier 2: it is in every session, and its cells
            // allow +2 below tier 4, so four easy workouts reach level 8.
            for _ in 0..<4 { store.completeWorkout(session: store.nextSession, result: .more) }
            let session = store.nextSession
            XCTAssertEqual(session.exercises.first { $0.pattern == .pull }?.tier, 2, "seeding")
            store.completeWorkout(session: session, result: .plan,
                                  discomfort: pin ? [] : [.pull], pinned: pin ? [.pull] : [])
            if pin {
                XCTAssertFalse(store.debutPatterns.contains(.pull),
                               "performed under a pin — tier 2 is no debut")
                continue
            }
            // The report unloaded pull to tier 1 — performed before, no badge.
            XCTAssertEqual(store.nextSession.exercises.first { $0.pattern == .pull }?.tier, 1,
                           "the pain report lands on the previous variation")
            XCTAssertFalse(store.debutPatterns.contains(.pull),
                           "the unloaded tier was performed — no badge")
            // Serve the freeze (3 appearances — pull is in every session),
            // confirm recovery with a fact at the plan, then climb back.
            for _ in 0..<3 { store.completeWorkout(session: store.nextSession, result: .plan) }
            let confirm = store.nextSession
            let load = confirm.exercises.first { $0.pattern == .pull }!.load
            store.completeWorkout(session: confirm, result: .plan, overrides: [.pull: load])
            while store.nextSession.exercises.first(where: { $0.pattern == .pull })!.tier < 2 {
                store.completeWorkout(session: store.nextSession, result: .more)
            }
            XCTAssertTrue(store.debutPatterns.contains(.pull),
                          "back at tier 2 after the pain: it was never performed — it debuts")
        }
    }

    func testCorruptedStorageFallsBackToInitial() throws {
        try Data("{not a json".utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.records.isEmpty, "a corrupted file should give a clean start, not a crash")
        XCTAssertEqual(store.totalLevel, 0)
    }

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

    /// Regression: a state file that exists but cannot be read (data
    /// protection before the first unlock, a transient I/O failure) must
    /// never be overwritten by the empty state that replaced it — and must
    func testUnreadableStateFileFreezesPersistenceUntilReloaded() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let seed = AppStore(storageURL: tempURL)
        seed.completeWorkout(session: seed.nextSession, result: .plan)
        let original = try Data(contentsOf: tempURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }

        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.records.isEmpty, "the unreadable launch degrades to empty state")
        XCTAssertFalse(store.shouldShowOnboarding, "an unread journal is not a fresh install")
        XCTAssertTrue(store.journalFrozen)
        XCTAssertThrowsError(try store.exportURL(),
                             "a frozen launch has nothing honest to export")
        store.setSounds(false)   // any mutation that would persist

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        XCTAssertEqual(try Data(contentsOf: tempURL), original,
                       "the journal on disk must survive the frozen launch byte-for-byte")

        // A launch nobody touched yet takes the file the moment it can read
        // it — that is the prewarm-before-first-unlock case this is all for.
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        let untouched = AppStore(storageURL: tempURL)
        XCTAssertTrue(untouched.journalFrozen)
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        untouched.reloadIfNeeded()
        XCTAssertEqual(untouched.records.count, 1, "the journal must load once readable")
        untouched.setSounds(false)
        XCTAssertFalse(AppStore(storageURL: tempURL).settings.soundsEnabled,
                       "persistence must resume after a successful reload")
    }

    func testUsedFrozenLaunchIsNotReplacedByTheFileItCouldNotRead() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let seed = AppStore(storageURL: tempURL)
        for _ in 0..<3 { seed.completeWorkout(session: seed.nextSession, result: .plan) }
        let original = try Data(contentsOf: tempURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }

        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan)
        XCTAssertEqual(store.records.count, 1, "the frozen launch keeps its own work in memory")

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        store.reloadIfNeeded()
        XCTAssertEqual(store.records.count, 1, "a used launch must not be swapped mid-flight")
        XCTAssertEqual(store.engineState.counter, 1,
                       "the counter must stay where the running session expects it")
        XCTAssertEqual(try Data(contentsOf: tempURL), original,
                       "and the real journal on disk stays untouched")
    }

    /// One unreadable journal entry (e.g. written by a newer version)
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
        // pre-bar files load with the bar module off and the branch at zero
        XCTAssertFalse(store.engineState.hasBar, "legacy files must decode with hasBar off")
        XCTAssertEqual(store.engineState.levels[.pullBar], 0)
        XCTAssertEqual(store.engineState.failStreak[.pullBar], 0)
    }

    // MARK: - Legacy settings files

    /// A fresh install starts with two spread-out rest days (issue #36): the
    func testFreshInstallDefaultsToTwoRestDays() {
        let store = AppStore(storageURL: tempURL)   // no file → fresh install
        XCTAssertEqual(store.settings.restWeekdays, [1, 4],
                       "fresh installs rest on Sunday and Wednesday")
    }

    /// A stored file WITHOUT the restWeekdays key belongs to an install that
    /// lived with Sunday-only — an upgrade must not add a rest day the person
    /// never chose.
    func testSettingsWithoutRestDaysKeyKeepTheOldSundayDefault() throws {
        let noKey = """
        {"engineState":{"counter":0,
          "levels":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[],
         "settings":{"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(noKey.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.settings.restWeekdays, [1],
                       "an upgrade must not change an existing week")
    }

    func testV11SettingsFileLoadsWithHealthDefaults() throws {
        // a settings file from before Health support
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
        // everything the old file knew about survives untouched
        XCTAssertEqual(store.settings.restWeekdays, [1, 4])
        XCTAssertEqual(store.settings.reminderHour, 7)
        XCTAssertEqual(store.settings.reminderMinute, 30)
        XCTAssertTrue(store.settings.healthEnabled)
        XCTAssertEqual(store.settings.healthExportedThrough, 3)
        XCTAssertTrue(store.engineState.hasBar)
        XCTAssertEqual(store.engineState.levels[.pullBar], 5)
        // and the onboarding/review fields arrive at their defaults
        XCTAssertFalse(store.settings.onboardingCompleted)
        XCTAssertNil(store.settings.lastReviewRequestAt)
    }

    // MARK: - Onboarding gate

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
        // an upgrading user has history but no flag — still no onboarding
        XCTAssertFalse(store.settings.onboardingCompleted)
        XCTAssertFalse(store.shouldShowOnboarding,
                       "history means the app has already been learned")
    }

    // MARK: - App Store review gate

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

    /// The onboarding and review fields must round-trip through a save/reload
    /// like every other setting — the onboarding must not reappear after a relaunch.
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

    // MARK: - Level curve

    func testLevelCurveIsCutAtTheGivenDate() throws {
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: nil)
        store.completeWorkout(session: store.nextSession, result: .plan)

        XCTAssertEqual(store.levelCurve(), store.records.map(\.totalLevelAfter))
        XCTAssertEqual(store.levelCurve(through: .distantPast), [],
                       "nothing was recorded before the cut, so there is no curve")
        XCTAssertEqual(store.levelCurve(through: .distantFuture).count,
                       store.records.count)
    }

    // MARK: - Week summary

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
        // A Sunday-first calendar (US default) would wrongly pull in Jul 12.
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

    // MARK: - Pull-up bar

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
        // v2.10 (spec §20.1): the cross-credit moves the branch on pull
        // sessions too, so the level is read from the engine rather than
        // spelled out — this test is about the snapshot and the reload.
        let barLevel = store.engineState.levels[.pullBar]
        XCTAssertEqual(store.records.last?.levelsAfter?[.pullBar], barLevel,
                       "the journal snapshot must include the pull_bar level")
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertTrue(reloaded.engineState.hasBar)
        XCTAssertEqual(reloaded.engineState.levels[.pullBar], barLevel)

        // turning the bar off freezes the branch but keeps its progress
        reloaded.setHasBar(false)
        XCTAssertFalse(reloaded.nextSession.exercises.contains { $0.pattern == .pullBar })
        XCTAssertEqual(reloaded.engineState.levels[.pullBar], barLevel,
                       "turning the bar off keeps the branch where it was")
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
        XCTAssertEqual(store.records.map(\.sessionNumber), Array(1...24))
        let chart = store.records.map(\.totalLevelAfter)
        XCTAssertEqual(chart, chart.sorted(), "the total level must not drop with \"on plan\"")
        XCTAssertEqual(AppStore(storageURL: tempURL).records.count, 24)
    }

    // MARK: - Settings

    func testSettingsPersistAcrossReload() {
        let store = AppStore(storageURL: tempURL)
        store.toggleRestDay(2)          // Monday joins the Sunday+Wednesday default
        store.setSounds(false)
        store.setReminderTime(hour: 7, minute: 30)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.settings.restWeekdays, [1, 2, 4])
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

    // MARK: - Silent decay for the 7–13 day blind zone (issue #37)

    /// A store whose last workout happened `daysAgo` days ago. Several
    /// sessions, so the levels sit clear of the zero clamp.
    private func storeWithWorkout(daysAgo: Int, at url: URL, sessions: Int = 4) -> AppStore {
        let store = AppStore(storageURL: url)
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        for _ in 0..<sessions {
            _ = store.completeWorkout(session: store.nextSession, result: .plan, date: date)
        }
        return store
    }

    func testSilentDecayAppliesExactlyOncePerBreak() {
        let store = storeWithWorkout(daysAgo: 10, at: tempURL)
        let before = store.engineState.levels
        store.applySilentDecayIfNeeded()
        for p in Pattern.allCases {
            XCTAssertEqual(store.engineState.levels[p], max(0, (before[p] ?? 0) - 1),
                           "\(p): −1 clamped at 0")
        }
        let once = store.engineState.levels
        store.applySilentDecayIfNeeded()
        XCTAssertEqual(store.engineState.levels, once, "the same break must not decay twice")
        // The stamp survives a relaunch — persisted, not in-memory.
        let reloaded = AppStore(storageURL: tempURL)
        reloaded.applySilentDecayIfNeeded()
        XCTAssertEqual(reloaded.engineState.levels, once,
                       "a relaunch inside the same break must not decay again")
    }

    func testSilentDecayIgnoresGapsOutsideTheBlindZone() {
        for days in [0, 6, 14, 30] {
            let url = tempURL.deletingPathExtension().appendingPathExtension("\(days).json")
            defer { try? FileManager.default.removeItem(at: url) }
            let store = storeWithWorkout(daysAgo: days, at: url)
            let before = store.engineState
            store.applySilentDecayIfNeeded()
            XCTAssertEqual(store.engineState, before,
                           "gap \(days): outside [7, 14) nothing may change")
        }
    }

    func testDecayedBreakComebackTotalsExactlyTheTable() {
        let cal = Calendar.current
        let day16 = cal.date(byAdding: .day, value: 6, to: .now)!  // 10 + 6 = 16-day gap
        // Break that got peeked at on day 10: decay, then a weakened comeback.
        let peeked = storeWithWorkout(daysAgo: 10, at: tempURL)
        peeked.applySilentDecayIfNeeded()
        XCTAssertEqual(peeked.comebackDrop(now: day16), 1,
                       "the card must show the weakened remainder, not the full table")
        peeked.acceptComeback(now: day16)
        // The same break with the app never opened: one plain comeback.
        let otherURL = tempURL.deletingPathExtension().appendingPathExtension("control.json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let control = storeWithWorkout(daysAgo: 10, at: otherURL)
        control.acceptComeback(now: day16)
        XCTAssertEqual(peeked.engineState.levels, control.engineState.levels,
                       "peeking mid-break must not cost more than staying away")
    }

    func testDecayStampGoesStaleAfterTheNextWorkout() {
        let store = storeWithWorkout(daysAgo: 10, at: tempURL)
        store.applySilentDecayIfNeeded()
        // The break ends: a workout today re-anchors the stamp's reference.
        _ = store.completeWorkout(session: store.nextSession, result: .plan)
        let after = store.engineState.levels
        // A fresh 8-day break decays again — the old stamp must not block it.
        let day8 = Calendar.current.date(byAdding: .day, value: 8, to: .now)!
        store.applySilentDecayIfNeeded(now: day8)
        for p in Pattern.allCases {
            XCTAssertEqual(store.engineState.levels[p], max(0, (after[p] ?? 0) - 1),
                           "\(p): a new break must decay independently")
        }
    }

}

// MARK: - Widget snapshot
//
// A same-file extension keeps the test class itself within the linter's
// type-body bound; XCTest discovers test methods in extensions just fine.
extension AppStoreTests {
    func testWidgetSnapshotMirrorsWeekStatuses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        store.completeWorkout(session: store.nextSession, result: .plan)   // today → done

        let snap = try JSONDecoder().decode(WidgetSnapshot.self,
                                            from: Data(contentsOf: url))
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = cal.timeZone
        let monday = try XCTUnwrap(iso.dateInterval(of: .weekOfYear, for: today)).start

        XCTAssertEqual(snap.days.count, 14, "the snapshot must cover two weeks")
        XCTAssertEqual(snap.days[0].date, monday,
                       "it must start on Monday so any entry can draw its own week")
        let todayEntry = try XCTUnwrap(snap.days.first { $0.date == today })
        XCTAssertEqual(todayEntry.status, .done)

        for day in snap.days where day.date > today {
            XCTAssertEqual(day.status, store.isRestDay(day.date) ? .rest : .workout,
                           "future days must mirror the rest-day settings")
        }
        for day in snap.days where day.date < today {
            XCTAssertEqual(day.status, store.isRestDay(day.date) ? .rest : .unmarked,
                           "a past training day with nothing recorded stays unmarked — "
                           + "the Calendar does not accuse and neither does the widget")
        }
        for day in snap.days {
            XCTAssertNil(day.sessionNumber, "a finished day carries no session number")
        }
    }

    func testWidgetSnapshotCarriesTheLevelWeekAndPlan() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        store.completeWorkout(session: store.nextSession, result: .plan)

        let snap = try JSONDecoder().decode(WidgetSnapshot.self,
                                            from: Data(contentsOf: url))
        XCTAssertEqual(snap.totalLevel, store.totalLevel)
        XCTAssertEqual(snap.week?.workouts, store.weekSummary().workouts)
        XCTAssertEqual(snap.week?.levelsDelta, store.weekSummary().levelsDelta)
        XCTAssertEqual(snap.planSessionNumber, store.nextSession.sessionNumber)
        // The write day's own label is the one the app shows right now; the
        // week tally is stamped with its Monday so the widget can keep it
        // inside the week it belongs to.
        let today = Calendar.current.startOfDay(for: .now)
        let todayEntry = try XCTUnwrap(snap.days.first { $0.date == today })
        XCTAssertEqual(todayEntry.nextLabel, store.nextTrainingDateLabel)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = Calendar.current.timeZone
        XCTAssertEqual(snap.weekStart,
                       try XCTUnwrap(iso.dateInterval(of: .weekOfYear, for: today)).start)

        let plan = try XCTUnwrap(snap.plan)
        XCTAssertEqual(plan.count, store.nextSession.exercises.count)
        XCTAssertEqual(plan.first?.name, store.nextSession.exercises.first?.name)
        XCTAssertFalse(plan.contains { $0.detail.isEmpty },
                       "the widget cannot format loads itself — they arrive ready")
    }

    /// Relative words are per day, not per write: a rest-day entry rendered
    /// days after the app was last opened must not repeat the write day's
    func testWidgetSnapshotLabelsSpeakFromTheirOwnDay() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let tomorrowWD = cal.component(.weekday,
                                       from: try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: today)))
        for wd in [1, 4] where wd != tomorrowWD { store.toggleRestDay(wd) }
        if ![1, 4].contains(tomorrowWD) { store.toggleRestDay(tomorrowWD) }
        store.completeWorkout(session: store.nextSession, result: .plan)

        let snap = try JSONDecoder().decode(WidgetSnapshot.self,
                                            from: Data(contentsOf: url))
        let todayEntry = try XCTUnwrap(snap.days.first { $0.date == today })
        XCTAssertNotEqual(todayEntry.nextLabel, "tomorrow",
                          "from the write day the rest day is in the way — its label is \"on X\"")
        for day in snap.days {
            switch day.status {
            case .rest where day.date > today:
                XCTAssertEqual(day.nextLabel, "tomorrow",
                               "\(day.date): a rest-day entry must speak from its own day")
            case .workout:
                XCTAssertNil(day.nextLabel,
                             "\(day.date): a planned day IS the workout — no label")
            default:
                break   // past days and today are covered elsewhere
            }
        }
    }

    func testWidgetSnapshotFromAnOlderBuildStillDecodes() throws {
        let legacy = #"{"days":[{"date":768614400,"status":"workout","sessionNumber":3}]}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))

        XCTAssertEqual(snap.days.count, 1)
        XCTAssertEqual(snap.days[0].status, .workout)
        XCTAssertEqual(snap.days[0].sessionNumber, 3)
        XCTAssertNil(snap.totalLevel)
        XCTAssertNil(snap.week)
        XCTAssertNil(snap.plan)
        XCTAssertNil(snap.weekStart)
        XCTAssertNil(snap.days[0].nextLabel)
    }

    /// The home screen must not be told "nothing done" over a history the
    func testFrozenLaunchLeavesTheWidgetSnapshotAlone() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let seed = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        seed.completeWorkout(session: seed.nextSession, result: .plan)
        let published = try Data(contentsOf: url)

        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }
        let frozen = AppStore(storageURL: tempURL, widgetSnapshotURL: url)
        frozen.refreshWidgetSnapshot()   // what backgrounding does
        XCTAssertEqual(try Data(contentsOf: url), published,
                       "the widget must keep showing the last state that was real")
    }
}
