//
//  Tests for records and settings files written by earlier app versions,
//  moved out of AppStoreTests.swift to keep it under the linter's file and
//  type-body ceilings. Grouped here because they all pin the same promise:
//  an upgrade must read an old file's fields exactly as they were, and fill
//  in only what that file never carried. The code moved unchanged.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Migration: records without a snapshot
extension AppStoreTests {

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
        XCTAssertNil(store.records[0].positionsAfter, "v1.0 records have no position snapshot")
        XCTAssertNil(store.records[0].totalProgressAfter,
                     "and none of them carries a number on the v3 scale")
        // RE-MARKED §41.7 (v3.1, 26.08.2026), class: the test pinned the defect.
        // See the twin note in `testOneBadRecordDoesNotDropTheJournal`.
        XCTAssertGreaterThan(store.totalProgress, Engine.totalProgress(.initial),
                             "the v2 rungs migrate, so progress is above a clean start")
        // Every settings key this file never carried comes out at its default.
        // The one exception is the announcement the migration itself owes the
        // person (§41.7) — it is not a decoded setting, it is a consequence.
        var expected = AppSettings()
        expected.migrationNoticePending = true
        XCTAssertEqual(store.settings, expected, "v1.0 files load with default settings")
        // Pre-bar files load with the bar module off and the branch at zero —
        // because this file predates the pattern and carries no level for it,
        // NOT because the state was discarded. A file that does carry one keeps
        // it: `testV13SettingsFileLoadsWithWaveFourDefaults` is that case.
        XCTAssertFalse(store.engineState.hasBar, "legacy files must decode with hasBar off")
        XCTAssertEqual(store.engineState.vars[.pullBar], 1)
        XCTAssertEqual(store.engineState.failStreak[.pullBar], 0)
    }

    // MARK: - Legacy settings files

    /// A fresh install starts with three spread-out rest days — four workouts
    /// a week. Issue #36 shipped two, which put the default one workout above
    /// what the app itself recommends on two screens.
    func testFreshInstallDefaultsToThreeSpreadRestDays() {
        let store = AppStore(storageURL: tempURL)   // no file → fresh install
        let rest = store.settings.restWeekdays
        XCTAssertEqual(rest, [2, 4, 6],
                       "fresh installs rest on Monday, Wednesday and Friday")
        // The spread is the point, not the count: two adjacent rest days would
        // leave a run of three training days, which is where Today stops
        // offering the plan and starts offering rest.
        XCTAssertFalse(rest.contains { rest.contains($0 % 7 + 1) },
                       "no two default rest days may be adjacent")
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
        // RE-MARKED §41.7 (v3.1, 26.08.2026), class: the test pinned the defect.
        // `hasBar` lives in the ENGINE state, not in the settings, and used to
        // go down with it — the person said they have a bar, the upgrade said
        // they do not, pull-ups vanished from every plan and the toggle in
        // settings read "off". §40.8 was reversed for exactly this. The answer
        // now survives, and this line is its guard.
        XCTAssertTrue(store.engineState.hasBar, "the answer about the bar is carried over")
        // Old level 5 is tier 1 of the removed encoding, and tier 1 of pull_bar
        // maps to variation 1 (§41.7) — a MIGRATED one, not a reset one.
        XCTAssertEqual(store.engineState.vars[.pullBar], 1)
        XCTAssertEqual(store.engineState.doses[.pullBar], 30,
                       "and its hold of 32 s floors onto the 5 s grid, never up")
        // and the onboarding/review fields arrive at their defaults
        XCTAssertFalse(store.settings.onboardingCompleted)
        XCTAssertNil(store.settings.lastReviewRequestAt)
    }
}
