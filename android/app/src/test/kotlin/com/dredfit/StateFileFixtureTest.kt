//
//  Port of ios/DredfitTests/StateFileFixtureTests.swift: the state file
//  exactly as release 2.4.4 writes it, frozen as bytes. Every optional field
//  is read leniently, so a renamed key or a changed wire shape would fail no
//  other test — the field would just be forgotten on the next launch. This is
//  also the file an iPhone hands an Android phone, so it is the iOS literal,
//  character for character.
//
//  Hand-written on purpose, never regenerated from the current types.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.AppearanceChoice
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.time.Instant
import kotlin.io.path.writeText
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StateFileFixtureTest : AppStoreTestCase() {

    private fun loadFixture(): AppStore {
        tempPath.writeText(RELEASE_244_STATE_FILE)
        val store = makeStore()
        // Both a reset engine state and a dropped record copy the file aside,
        // so its absence is the whole-file verdict.
        assertFalse(Files.exists(corruptPath), "the 2.4.4 file must decode without anything set aside")
        assertEquals(12, store.engineState.counter, "the engine state must not start clean")
        assertEquals(2, store.records.size)
        return store
    }

    /** Swift's `Date(timeIntervalSinceReferenceDate:)`. */
    private fun sinceReference(seconds: Long): Instant = Instant.ofEpochSecond(978_307_200L + seconds)

    @Test
    fun release244EngineStateReadsEveryKey() {
        val state = loadFixture().engineState
        assertTrue(state.hasBar)
        assertEquals(4, state.vars[Pattern.lunge])
        assertEquals(30, state.doses[Pattern.coreAntiExt])
        assertEquals(4, state.sets[Pattern.lunge])
        assertEquals(1, state.sub[Pattern.squat])
        assertEquals(1, state.cut[Pattern.pull])
        assertEquals(15, state.shownDose(Pattern.squat, variation = 2))
        assertEquals(45, state.shownDose(Pattern.coreAntiExt, variation = 1))
        assertEquals(2, state.setsHold[Pattern.lunge])
        assertEquals(27, state.shownWork[Pattern.squat])
        assertEquals(17, state.shownOrd[Pattern.squat])
        assertEquals(1, state.failStreak[Pattern.pull])
        assertEquals(setOf(Pattern.pull), state.lastHard)
        assertEquals(1, state.lessRun)
        assertEquals(setOf(Pattern.pullBar), state.creditPaused)
        assertEquals(1, state.returnRun)
        assertEquals(5, state.lessHist[Pattern.pull])
        assertEquals(4, state.rampWindow)
        assertEquals(2, state.weekGain[Pattern.squat])
        assertEquals(3.5, state.weekAgeDays)
    }

    @Test
    fun release244RecordReadsEveryKey() {
        val record = assertNotNull(loadFixture().records.lastOrNull())
        assertEquals(12, record.sessionNumber)
        assertEquals(sinceReference(780_000_000), record.date)
        assertEquals(FeedbackResult.more, record.result)
        assertEquals(143, record.totalProgressAfter)
        val squat = assertNotNull(record.exercises?.firstOrNull())
        assertEquals(3, squat.variation)
        assertEquals(listOf(10, 9, 9), squat.loads)
        assertEquals(4, squat.probe?.variation)
        assertEquals(9, record.actuals?.get(Pattern.squat))
        assertEquals(listOf(10, 9, 8), record.setActuals?.get(Pattern.squat))
        assertEquals(6, record.probes?.get(Pattern.squat))
        assertEquals(1, record.setsSkipped?.get(Pattern.pull))
        assertEquals(setOf(Pattern.calf), record.skipped)
        assertEquals(1, record.positionsAfter?.get(Pattern.squat)?.sub)
        assertEquals(1, record.positionsAfter?.get(Pattern.pull)?.cut)
        assertEquals(1980, record.durationSec)
        assertEquals(300, record.warmupSec)
        assertEquals(240, record.cooldownSec)
        assertEquals(true, record.healthExported)
        assertEquals(Pattern.calf, record.interrupted)
        assertEquals(1, record.raisedSteps?.get(Pattern.squat))
        assertEquals(1, record.raisedLanded?.get(Pattern.squat))
    }

    @Test
    fun release244SettingsReadEveryKey() {
        val settings = loadFixture().settings
        assertEquals(setOf(1, 4), settings.restWeekdays)
        assertFalse(settings.soundsEnabled)
        assertTrue(settings.reminderEnabled)
        assertEquals(19, settings.reminderHour)
        assertEquals(30, settings.reminderMinute)
        assertTrue(settings.healthEnabled)
        assertEquals(12, settings.healthExportedThrough)
        assertEquals(78.5, settings.bodyMassKg)
        assertTrue(settings.bodyMassFromHealth)
        assertEquals(sinceReference(779_990_000), settings.bodyMassDate)
        assertTrue(settings.onboardingCompleted)
        assertTrue(settings.hasOpenedTechnique)
        assertTrue(settings.hasReportedOwnNumber)
        assertTrue(settings.playsTonesInSilentMode)
        assertEquals(AppearanceChoice.dark, settings.appearance)
        assertEquals(listOf(Pattern.squat), settings.planMoves?.byHand)
        assertEquals(listOf(Pattern.pull), settings.ratingMoves?.byRating)
        assertNull(settings.migrationNoticePending, "a v3 file is not a migration")
    }

    private companion object {
        /** `[Pattern: X]` is an UNKEYED array alternating raw value and value;
         *  the inner `[Int: Int]` of `shown` is a keyed object, because Swift
         *  special-cases integer keys. Dates are seconds since the reference
         *  date. `discomfort` and `pendingWorkout` are left out. */
        const val RELEASE_244_STATE_FILE = """
    {"engineState":{"counter":12,"hasBar":true,
      "vars":["squat",3,"push_h",2,"hinge",2,"pull",2,"push_v",1,"lunge",4,
              "core_anti_ext",2,"core_rot",1,"calf",2,"pull_bar",1],
      "doses":["squat",9,"push_h",8,"hinge",10,"pull",7,"push_v",6,"lunge",10,
               "core_anti_ext",30,"core_rot",20,"calf",12,"pull_bar",15],
      "sets":["lunge",4],
      "sub":["squat",1],
      "cut":["pull",1],
      "shown":["squat",{"2":15,"3":9},"core_anti_ext",{"1":45,"2":30}],
      "setsHold":["lunge",2],
      "shownWork":["squat",27],
      "shownOrd":["squat",17],
      "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",1,"push_v",0,"lunge",0,
                    "core_anti_ext",0,"core_rot",0,"calf",0,"pull_bar",0],
      "lastHard":["pull"],
      "lessRun":1,
      "creditPaused":["pull_bar"],
      "returnRun":1,
      "lessHist":["pull",5],
      "rampWindow":4,
      "weekGain":["squat",2],
      "weekAgeDays":3.5},
     "records":[
      {"sessionNumber":11,"date":779900000,"result":"plan","totalProgressAfter":140,
       "healthExported":true},
      {"sessionNumber":12,"date":780000000,"result":"more","totalProgressAfter":143,
       "exercises":[{"pattern":"squat","name":"Split squat","variation":3,"unit":"reps",
                     "load":9,"perSide":true,"sets":3,"restSetSec":60,"restExerciseSec":90,
                     "loads":[10,9,9],
                     "probe":{"variation":4,"name":"Bulgarian split squat","unit":"reps",
                              "load":6,"perSide":true}}],
       "actuals":["squat",9],
       "setActuals":["squat",[10,9,8]],
       "probes":["squat",6],
       "setsSkipped":["pull",1],
       "skipped":["calf"],
       "positionsAfter":["squat",{"variation":3,"sets":3,"dose":9,"sub":1},
                         "pull",{"variation":2,"sets":3,"dose":7,"cut":1}],
       "durationSec":1980,"warmupSec":300,"cooldownSec":240,
       "healthExported":true,
       "interrupted":"calf",
       "raisedSteps":["squat",1],
       "raisedLanded":["squat",1]}],
     "settings":{"restWeekdays":[1,4],"soundsEnabled":false,"reminderEnabled":true,
      "reminderHour":19,"reminderMinute":30,"healthEnabled":true,"healthExportedThrough":12,
      "bodyMassKg":78.5,"bodyMassFromHealth":true,"bodyMassDate":779990000,
      "watchRecordsWorkouts":false,"onboardingCompleted":true,"hasOpenedTechnique":true,
      "hasReportedOwnNumber":true,"playsTonesInSilentMode":true,"appearance":"dark",
      "planMoves":{"session":13,"byHand":["squat"],"byRating":[]},
      "ratingMoves":{"session":12,"byHand":[],"byRating":["pull"]}}}
    """
    }
}
