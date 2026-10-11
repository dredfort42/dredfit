//
//  Port of ios/DredfitTests/SkipKeepsNumberTests.swift: a number the person
//  entered for a set is never discarded by skipping it — whatever the number,
//  and however the set is skipped.
//
//  All six tests, the history line included (`HistorySheet.setFacts`,
//  ui/progress/HistorySheet.kt).
//

package com.dredfit

import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.ui.progress.HistorySheet
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.completeSet
import com.dredfit.workout.finishNow
import com.dredfit.workout.setsPerformedHere
import com.dredfit.workout.skipRest
import com.dredfit.workout.skipRestOfExercise
import com.dredfit.workout.skipSet
import com.dredfit.workout.startAdjusting
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SkipKeepsNumberTest : WorkoutSessionTestCase() {

    /** "Went differently" → `value` → OK on the set in front of the person. */
    private fun enter(value: Int, flow: WorkoutSession) {
        flow.startAdjusting()
        flow.adjustValue = value
        flow.commitSetEdit()
    }

    /** A number on the plan is a number too: "8, entered 8 then Skip this
     *  set, 6" on 3×8 is 8, 8, 6 — 7.33, and the history reads 8-8-6 — though
     *  a record that lands back on the plan leaves nothing in the facts. */
    @Test
    fun aNumberEnteredOnThePlanIsKeptBySkippingTheSet() {
        val (flow, store) = squatFlow()
        val squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        enter(8, flow)
        assertNull(flow.actuals[Pattern.squat], "the premise: a number on the plan leaves no record")
        flow.skipSet()
        enter(6, flow)
        assertEquals(22.0 / 3.0, assertNotNull(flow.overrides[Pattern.squat]), 1e-9)
        assertEquals(listOf(8, 8, 6), flow.actualSets[Pattern.squat])
        flow.completeSet()
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        assertEquals(listOf(8, 8, 6), HistorySheet.setFacts(squat, assertNotNull(store.records.lastOrNull()))?.first)
    }

    /** The number last confirmed is the one entered: 6, corrected back to 8
     *  before the skip, still counts as the person's 8. */
    @Test
    fun aNumberCorrectedBackToThePlanBeforeTheSkipStillCounts() {
        val (flow, _) = squatFlow()
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        enter(8, flow)
        assertNull(flow.actuals[Pattern.squat], "the premise: back on the plan, nothing is left in the facts")
        flow.skipSet()
        enter(6, flow)
        assertEquals(22.0 / 3.0, assertNotNull(flow.overrides[Pattern.squat]), 1e-9)
    }

    /** A number turned on the stepper and never confirmed with OK is not
     *  entered: the skip leaves the set out — 8, 6. */
    @Test
    fun aNumberNeverConfirmedIsNotEntered() {
        val (flow, _) = squatFlow()
        flow.completeSet()
        flow.skipRest()
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.skipSet()
        assertNull(flow.editing)
        enter(6, flow)
        assertEquals(7.0, flow.overrides[Pattern.squat])
    }

    /** "8, 8, entered 6 on set 3, Skip the remaining sets" on 4×8, where the
     *  screen offers that escape: set 3 keeps its 6, and set 4 is named with
     *  no number and stays out of the fold, the rating's "actual" and the
     *  history line — 8, 8, 6. "Finish now" there folds set 4 at what was in
     *  force instead (7.0): nobody skipped it. */
    @Test
    fun skippingTheRemainingSetsKeepsTheNumberOfTheSetInFrontOnly() {
        val (flow, store) = fourSetSquatFlow()
        val squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        assertTrue(!flow.isLastSet && flow.setsPerformedHere >= EngineConfig.setsFloor,
                   "the premise: the screen offers the escape here")
        flow.skipRestOfExercise()
        assertEquals(setOf(2, 3), flow.skippedSetIndices[Pattern.squat])
        assertEquals(setOf(2), flow.skippedWithNumber[Pattern.squat], "set 4 had no number to keep")
        assertEquals(22.0 / 3.0, assertNotNull(flow.overrides[Pattern.squat]), 1e-9)
        assertEquals(listOf(8, 8, 6), flow.actualSets[Pattern.squat])
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        assertEquals(listOf(8, 8, 6), HistorySheet.setFacts(squat, assertNotNull(store.records.lastOrNull()))?.first)
    }

    /** The same escape with no number for the set in front — 6 was entered
     *  for set 2 — names both remaining sets with none, and both stay out:
     *  8, 6. */
    @Test
    fun skippingTheRemainingSetsWithNoNumberLeavesThemOut() {
        val (flow, store) = fourSetSquatFlow()
        val squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        flow.completeSet()
        flow.skipRest()
        flow.skipRestOfExercise()
        assertEquals(setOf(2, 3), flow.skippedSetIndices[Pattern.squat])
        assertNull(flow.skippedWithNumber[Pattern.squat])
        assertEquals(7.0, flow.overrides[Pattern.squat])
        assertEquals(listOf(8, 6), flow.actualSets[Pattern.squat])
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        assertEquals(listOf(8, 6), HistorySheet.setFacts(squat, assertNotNull(store.records.lastOrNull()))?.first)
    }

    /** A process death between the OK and the skip: a number off the plan is
     *  still in the facts, and the skip still keeps it — 8, 6, 6. */
    @Test
    fun aNumberOffThePlanSurvivesAProcessDeathBeforeTheSkip() {
        val (flow, store) = squatFlow()
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        val back = makeFlow(store, resume = assertNotNull(store.pendingWorkout))
        assertEquals(1, back.setIndex)
        back.skipSet()
        back.completeSet()
        assertEquals(20.0 / 3.0, assertNotNull(back.overrides[Pattern.squat]), 1e-9)
    }
}
