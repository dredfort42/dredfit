//
//  Port of ios/DredfitTests/CleanStartTests.swift: a state written before v3
//  is READ AND CARRIED OVER; the journal survives untouched, an old exercise
//  line keeps the movement it was written with, and a state that is neither
//  v2 nor v3 still gives a clean start.
//
//  Expectations come from `V2FormatSnapshot` (MigrationV2TestTable.kt) and
//  never from `Engine.v2TierToVariation`, which would make them unfailable.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CleanStartTest : AppStoreTestCase() {

    /** A storage file exactly as a v2 build wrote it: engine state keyed by
     *  `levels`, and a journal of two workouts beside it. */
    private fun storeFromBefore(): AppStore = storeFrom("""
        {"engineState":{"counter":40,"levels":[${pairs { 24 }}],"failStreak":[${pairs { 0 }}],
                        "hasBar":true,"lessRun":0,"returnRun":0,"rampWindow":0,
                        "weekAgeDays":0},
         "records":[
           {"sessionNumber":39,"date":0,"result":"plan","totalLevelAfter":170,
            "exercises":[{"pattern":"squat","name":"Bulgarian split squat","tier":3,
                          "unit":"reps","load":9,"perSide":true,"sets":3,
                          "restSetSec":90,"restExerciseSec":60,"display":"3×9 per side"}]},
           {"sessionNumber":40,"date":86400,"result":"more","totalLevelAfter":180}],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
    """)

    private fun tier4Landing(p: Pattern): Int =
        assertNotNull(V2FormatSnapshot.tierToVariation[p]?.getOrNull(3), "${p.rawValue} has no tier-4 landing in the v2 snapshot")

    /** L=24 is tier 4 in v2 at 4 reps: every pattern lands on its tier-4
     *  variation, not its first, and the journal records the dose there. */
    @Test
    fun aV2StateIsCarriedOverNotReset() {
        val store = storeFromBefore()
        for (p in Pattern.allCases) {
            val expected = tier4Landing(p)
            assertEquals(expected, store.engineState.vars[p], "${p.rawValue}: its own rung")
            assertNotNull(store.engineState.shown[p]?.get(expected), "${p.rawValue}: what was done there is on record")
        }
        assertEquals(40, store.engineState.counter, "the rotation phase carries over too")
        assertTrue(store.engineState.hasBar, "and the answer about the bar")
    }

    /** What carries over is the RUNG. The dose sits at the floor because
     *  L=24 is the BOTTOM of v2's tier 4 (4 reps, a 10-second hold). */
    @Test
    fun planAfterMigration_fromTheBottomOfV2sTopTier_standsOnTheEarnedRung() {
        val session = storeFromBefore().nextSession

        assertEquals(41, session.sessionNumber, "the count continues where v2 left it")
        assertFalse(session.exercises.isEmpty(), "a session must carry slots, or the loop below asserts nothing at all")
        for (ex in session.exercises) {
            val name = ex.pattern.rawValue
            assertEquals(tier4Landing(ex.pattern), ex.variation, "$name: the rung v2's tier 4 was earned on, not the first one")
            assertEquals(3, ex.sets, "$name: v2 planned three sets at L=24, and sets above the base exist only on the top rung")
            assertEquals(Dose.grid(ex.unit).min, ex.load, "$name: the bottom of v2's tier 4 is already v3's grid floor")
            assertNull(ex.probe, "$name: a probe is offered from the dose CEILING, and they stand at the floor")
        }
    }

    /** The history survives whole — the half a decode failure could most
     *  easily take. */
    @Test
    fun theWorkoutJournalSurvivesIntact() {
        val store = storeFromBefore()
        assertEquals(2, store.records.size, "both workouts are still there")
        assertEquals(listOf(39, 40), store.records.map { it.sessionNumber })
        assertEquals(FeedbackResult.more, store.records.last().result)
        // A record from before v3 carries no point on the v3 scale.
        assertNull(store.records.first().totalProgressAfter)
        assertNull(store.records.first().positionsAfter)
    }

    /** An old exercise line renders the movement it was done at: its `tier`
     *  is NOT read as a v3 variation, which would rewrite the history. */
    @Test
    fun anOldExerciseLineKeepsTheNameItWasWrittenWith() {
        val squat = assertNotNull(storeFromBefore().records.first().exercises?.firstOrNull())
        assertEquals(Pattern.squat, squat.pattern)
        assertEquals(9, squat.load)
        assertEquals(0, squat.variation, "a record from before v3 marks itself as predating the ladders")
        assertNull(squat.probe)
    }

    /** A workout on the carried-over state writes a v3 record beside the old ones. */
    @Test
    fun theStoreIsUsableImmediatelyAfterMigration() {
        val store = storeFromBefore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        assertEquals(3, store.records.size)
        assertNotNull(store.records.last().positionsAfter)
        assertEquals(41, store.records.last().sessionNumber)
    }

    @Test
    fun garbageStillGivesACleanStart() {
        val store = storeFrom("""{"engineState":{"nonsense":1},"records":[],"settings":null}""")
        for (p in Pattern.allCases) assertEquals(1, store.engineState.vars[p], "${p.rawValue}: first rung")
        assertEquals(0, store.engineState.counter)
    }
}
