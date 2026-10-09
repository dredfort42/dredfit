//
//  Port of ios/DredfitTests/SkippedSetsHistoryTests.swift: the history line
//  of a record that names its skipped sets, beside the sets a workout ended
//  before reaching — counted, never named, and never printed as sets that ran.
//
//  Not ported: the history line itself. Every test ends on
//  `HistorySheet.setFacts(squat, in: record)`, a screen's read
//  (ios/Dredfit/Views/Progress/HistorySheet.swift) that nothing on Android
//  computes yet; those four assertions are dropped. What the store and the
//  flow decide — the record's count of sets off and the indices it names —
//  is ported in all four tests.
//

package com.dredfit

import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.settleAbandonedWorkout
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSessionStore
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.finishNow
import com.dredfit.workout.skipRest
import com.dredfit.workout.skipSet
import com.dredfit.workout.startAdjusting
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A 4×8 squat — the top of its ladder, the only rung that takes a fourth
 *  set — in the store's own state: session 1 opens on it. Top-level, as
 *  SkipKeepsNumberTest calls it too (a Swift extension's helper). */
fun WorkoutSessionTestCase.fourSetSquatFlow(): Pair<WorkoutSession, AppStore> {
    val state = EngineState.initial
    state.vars[Pattern.squat] = Library.count(Pattern.squat)
    state.doses[Pattern.squat] = 8
    state.sets[Pattern.squat] = 4
    val store = makeStore()
    store.update { it.copy(engineState = state) }
    val flow = makeFlow(store)
    flow.declineWarmup()
    flow.exIndex = index(Pattern.squat, flow)
    assertEquals(LoadUnit.reps, flow.exercise.unit, "the premise: reps")
    assertEquals(listOf(4, 8), listOf(flow.exercise.sets, flow.exercise.load), "the premise: 4×8")
    assertNull(flow.exercise.loads)
    return flow to store
}

class SkippedSetsHistoryTest : WorkoutSessionTestCase() {

    /** Set 1 at 6, set 2 skipped with nothing entered for it, set 3 done at
     *  the 6 in force for it, and set 4 in front of the person. */
    private fun sixSkippedSixToTheFourthSet(flow: WorkoutSession) {
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        flow.skipRest()
        assertEquals(3, flow.setIndex)
        assertEquals(listOf(6), flow.actuals[Pattern.squat])
    }

    /** …then "Finish now": set 4 was never reached. The record counts two
     *  sets off and names one; the history line is the two sets that ran,
     *  2×6 — not a third 6 for a set nobody got to. */
    @Test
    fun theHistoryLineLeavesOutASetFinishNowNeverReached() {
        val (flow, store) = fourSetSquatFlow()
        sixSkippedSixToTheFourthSet(flow)
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        val record = assertNotNull(store.records.lastOrNull())
        assertEquals(2, record.setsSkipped?.get(Pattern.squat))
        assertEquals(listOf(1), record.skippedSetIndices?.get(Pattern.squat))
    }

    /** The same workout forgotten on set 4 and settled later. */
    @Test
    fun theHistoryLineLeavesOutASetAForgottenWorkoutNeverReached() {
        val (flow, store) = fourSetSquatFlow()
        sixSkippedSixToTheFourthSet(flow)
        val snap = assertNotNull(store.pendingWorkout)
        assertTrue(store.settleAbandonedWorkout(now = snap.savedAt.plus(WorkoutSessionStore.forgottenAfter)))
        val record = assertNotNull(store.records.lastOrNull())
        assertEquals(2, record.setsSkipped?.get(Pattern.squat))
    }

    /** A skipped set that kept its number is still a named skip, so the
     *  count past the named ones is still only the set never reached: 8, a
     *  skipped set with its 6, the 6 in force for set 3, set 4 never reached
     *  — 8-6-6. */
    @Test
    fun aNumberedSkipLeavesTheCountOfSetsNeverReachedRight() {
        val (flow, store) = fourSetSquatFlow()
        flow.completeSet()
        flow.skipRest()
        enterSixAndSkipTheSet(flow)
        flow.completeSet()
        flow.skipRest()
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        val record = assertNotNull(store.records.lastOrNull())
        assertEquals(2, record.setsSkipped?.get(Pattern.squat))
    }

    /** The cut never goes below what was recorded: 6 entered for set 4, the
     *  set in progress, then "Finish now" — the line keeps it, 8-8-6. */
    @Test
    fun theHistoryLineKeepsANumberEnteredForTheSetInProgress() {
        val (flow, store) = fourSetSquatFlow()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        flow.skipRest()
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        val record = assertNotNull(store.records.lastOrNull())
        assertEquals(2, record.setsSkipped?.get(Pattern.squat))
    }
}
