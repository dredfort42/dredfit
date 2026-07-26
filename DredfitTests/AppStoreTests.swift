//
//  AppStoreTests.swift
//  DredfitTests
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

    func testCorruptedStorageFallsBackToInitial() throws {
        try Data("{not a json".utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.records.isEmpty, "a corrupted file should give a clean start, not a crash")
        XCTAssertEqual(store.totalLevel, 0)
    }

    /// An unreadable state file is moved aside, not silently replaced —
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

    /// Regression: a state file that exists but cannot be read (data
    /// protection before the first unlock, a transient I/O failure) must
    /// never be overwritten by the empty state that replaced it — and must
    /// load for real once it becomes readable again.
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

    /// A frozen launch the user has already used stays frozen: reloading over
    /// their work would erase it without a word, and mid-workout it would move
    /// the engine counter out from under the running session.
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

    /// Files written by older versions must keep loading losslessly.
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

    /// A file with the Health fields but no onboarding/review fields must
    /// keep every existing value and gain the new ones at their defaults.
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

    // MARK: - Widget snapshot

    /// The snapshot URL is injected so this runs on unsigned (CI) builds too.
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

    /// The medium and large families need more than day statuses, and the
    /// numbers must be the ones the app itself is showing.
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
        XCTAssertEqual(snap.nextDateLabel, store.nextTrainingDateLabel)

        let plan = try XCTUnwrap(snap.plan)
        XCTAssertEqual(plan.count, store.nextSession.exercises.count)
        XCTAssertEqual(plan.first?.name, store.nextSession.exercises.first?.name)
        XCTAssertFalse(plan.contains { $0.detail.isEmpty },
                       "the widget cannot format loads itself — they arrive ready")
    }

    /// Right after an update the file on disk is still the one the previous
    /// build wrote. It has to decode, or the widget blanks out until the app
    /// is next opened.
    func testWidgetSnapshotFromAnOlderBuildStillDecodes() throws {
        let legacy = #"{"days":[{"date":768614400,"status":"workout","sessionNumber":3}]}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))

        XCTAssertEqual(snap.days.count, 1)
        XCTAssertEqual(snap.days[0].status, .workout)
        XCTAssertEqual(snap.days[0].sessionNumber, 3)
        XCTAssertNil(snap.totalLevel)
        XCTAssertNil(snap.week)
        XCTAssertNil(snap.plan)
        XCTAssertNil(snap.nextDateLabel)
    }

    /// The home screen must not be told "nothing done" over a history the
    /// launch merely failed to read.
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
        XCTAssertEqual(store.records.map(\.sessionNumber), Array(1...24))
        let chart = store.records.map(\.totalLevelAfter)
        XCTAssertEqual(chart, chart.sorted(), "the total level must not drop with \"on plan\"")
        XCTAssertEqual(AppStore(storageURL: tempURL).records.count, 24)
    }

    // MARK: - Settings

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
