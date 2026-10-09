//
//  Port of ios/DredfitTests/AppStoreTests+LegacyMigration.swift. One promise:
//  an upgrade must read an old file's fields exactly as they were, and fill
//  in only what that file never carried.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.store.AppSettings
import com.dredfit.store.totalProgress
import org.junit.jupiter.api.Test
import kotlin.io.path.writeText
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AppStoreTestLegacyMigration : AppStoreTestCase() {

    // MARK: - Migration: records without a snapshot

    @Test
    fun legacyRecordsWithoutSnapshotDecode() {
        // A record format without the exercises/actuals fields. [Pattern: Int]
        // is an alternating array, not an object — the fixture mirrors the
        // real format.
        val legacy = """
        {"engineState":{"counter":1,
          "levels":["squat",2,"push_h",2,"hinge",2,"pull",2,"push_v",2,"lunge",2,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[{"sessionNumber":1,"date":700000000,"result":"more","totalLevelAfter":12}]}
        """.trimIndent()
        tempPath.writeText(legacy)
        val store = makeStore()
        assertEquals(1, store.records.size, "the legacy record did not decode")
        assertNull(store.records[0].exercises, "a legacy record should have no snapshot")
        assertNull(store.records[0].actuals)
        assertNull(store.records[0].skipped, "v1.0 records have no skips")
        assertNull(store.records[0].positionsAfter, "v1.0 records have no position snapshot")
        assertNull(store.records[0].totalProgressAfter, "and none of them carries a number on the v3 scale")
        assertTrue(store.totalProgress > Engine.totalProgress(EngineState.initial),
                   "the v2 rungs migrate, so progress is above a clean start")
        // Every settings key this file never carried comes out at its default —
        // except the announcement the migration itself owes the person.
        assertEquals(AppSettings(migrationNoticePending = true), store.settings,
                     "v1.0 files load with default settings")
        // Pre-bar files load with the bar off and the branch at zero because
        // this file carries no level for it, NOT because the state was
        // discarded (v13SettingsFileLoadsWithOnboardingAndReviewDefaults).
        assertFalse(store.engineState.hasBar, "legacy files must decode with hasBar off")
        assertEquals(1, store.engineState.vars[Pattern.pullBar])
        assertEquals(0, store.engineState.failStreak[Pattern.pullBar])
    }

    // MARK: - Legacy settings files

    /** A fresh install starts with three spread-out rest days — four workouts
     *  a week; two would put the default above what the app recommends. */
    @Test
    fun freshInstallDefaultsToThreeSpreadRestDays() {
        val store = makeStore()   // no file → fresh install
        val rest = store.settings.restWeekdays
        assertEquals(setOf(2, 4, 6), rest, "fresh installs rest on Monday, Wednesday and Friday")
        // The spread is the point: two adjacent rest days leave a run of three
        // training days, where Today stops offering the plan.
        assertFalse(rest.any { (it % 7 + 1) in rest }, "no two default rest days may be adjacent")
    }

    /** A stored file WITHOUT the restWeekdays key belongs to an install that
     *  lived with Sunday-only — an upgrade must not add a rest day. */
    @Test
    fun settingsWithoutRestDaysKeyKeepTheOldSundayDefault() {
        val noKey = """
        {"engineState":{"counter":0,
          "levels":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[],
         "settings":{"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """.trimIndent()
        tempPath.writeText(noKey)
        val store = makeStore()
        assertEquals(setOf(1), store.settings.restWeekdays, "an upgrade must not change an existing week")
    }

    @Test
    fun v11SettingsFileLoadsWithHealthDefaults() {
        // a settings file from before Health support
        val v11 = """
        {"engineState":{"counter":0,
          "levels":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[],
         "settings":{"restWeekdays":[1,2],"soundsEnabled":false,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """.trimIndent()
        tempPath.writeText(v11)
        val store = makeStore()
        assertEquals(setOf(1, 2), store.settings.restWeekdays, "old settings must survive")
        assertFalse(store.settings.soundsEnabled)
        assertFalse(store.settings.healthEnabled, "Health defaults off for old files")
        assertEquals(0, store.settings.healthExportedThrough)
        assertFalse(store.settings.onboardingCompleted, "v1.4 onboarding flag defaults off")
        assertNull(store.settings.lastReviewRequestAt, "v1.4 review stamp defaults to never")
    }

    @Test
    fun v13SettingsFileLoadsWithOnboardingAndReviewDefaults() {
        val v13 = """
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
        """.trimIndent()
        tempPath.writeText(v13)
        val store = makeStore()
        // everything the old file knew about survives untouched
        assertEquals(setOf(1, 4), store.settings.restWeekdays)
        assertEquals(7, store.settings.reminderHour)
        assertEquals(30, store.settings.reminderMinute)
        assertTrue(store.settings.healthEnabled)
        assertEquals(3, store.settings.healthExportedThrough)
        // `hasBar` lives in the ENGINE state, so it migrates with the engine:
        // lost, someone who said they have a bar would lose pull-ups.
        assertTrue(store.engineState.hasBar, "the answer about the bar is carried over")
        // Old level 5 is tier 1 of the removed encoding, which maps pull_bar
        // to variation 1 — a MIGRATED one, not a reset one.
        assertEquals(1, store.engineState.vars[Pattern.pullBar])
        assertEquals(30, store.engineState.doses[Pattern.pullBar],
                     "and its hold of 32 s floors onto the 5 s grid, never up")
        // and the onboarding/review fields arrive at their defaults
        assertFalse(store.settings.onboardingCompleted)
        assertNull(store.settings.lastReviewRequestAt)
    }
}
