//
//  Port of ios/DredfitTests/PerformedSetsTests.swift: a skipped set does not
//  count — no card on the summary, and no part in the fold the engine takes,
//  the rating screen's "actual" or the history line. A set the workout ended
//  before reaching is not a skipped one.
//
//  The Swift file is an extension of WorkoutSessionTests plus the class
//  PerformedSetsFoldTests; here they are `PerformedSetsTest` (on the flow's
//  harness) and `PerformedSetsFoldTest` (on the store's), in this one file.
//
//  Not ported: every `HistorySheet.setFacts(…)` assertion — the history
//  line is a screen's (ios/Dredfit/Views/Progress/HistorySheet.swift), and
//  nothing on Android computes it yet. Dropped from
//  `theHistoryLineIsTheSetsThatWereDone` (both reads; the record's skipped
//  indices are still checked), `aSkippedSetKeepsTheNumberEnteredForIt` (its
//  last line), `theLastSetSkippedKeepsTheNumberEnteredForIt` (both reads; the
//  folds and the changed rating's 7 are still checked) and
//  `aRecordWithoutTheIndicesReadsAsItAlwaysDid` (one read; the plank premise
//  still runs). Every test is ported.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.generateSession
import com.dredfit.journal.WorkoutRecord
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.store.previewPlan
import com.dredfit.store.settleAbandonedWorkout
import com.dredfit.workout.GetReady
import com.dredfit.workout.HeldSet
import com.dredfit.workout.SetFacts
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.WorkoutSessionStore
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.finishNow
import com.dredfit.workout.heldSets
import com.dredfit.workout.holdUnderWay
import com.dredfit.workout.leaveExercise
import com.dredfit.workout.leaveExerciseSummary
import com.dredfit.workout.leftOutHere
import com.dredfit.workout.nextPlan
import com.dredfit.workout.skipRest
import com.dredfit.workout.skipRestOfExercise
import com.dredfit.workout.skipSet
import com.dredfit.workout.startAdjusting
import com.dredfit.workout.startDeclaringHoldTime
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.stopHoldEarly
import kotlinx.serialization.json.Json
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PerformedSetsTest : WorkoutSessionTestCase() {

    /** "Plank" 3×30 s in the store's own state: session 2 carries it. */
    private fun plankFlow(): Pair<WorkoutSession, AppStore> {
        val state = EngineState.initial
        state.counter = 1
        state.vars[Pattern.coreAntiExt] = 3
        state.doses[Pattern.coreAntiExt] = 30
        val store = makeStore()
        store.update { it.copy(engineState = state) }
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreAntiExt, flow)
        assertEquals(3, flow.exercise.sets, "the premise: three sets")
        assertEquals(30, flow.exercise.load, "the premise: 30 s each")
        assertNull(flow.exercise.loads)
        assertNull(flow.exercise.probe)
        return flow to store
    }

    /** "Set the time" 45, set 1 on its clock, the rest after it run out with
     *  nobody there — the run drops, and set 2 waits on its own screen, where
     *  it is skipped — and set 3 on its clock to the summary. */
    private fun declareAndSkipTheMiddleSet(flow: WorkoutSession) {
        flow.startDeclaringHoldTime()
        flow.adjustValue = 45
        flow.commitSetEdit()
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 45)
        advance(600)
        flow.tick()
        assertEquals(1, flow.setIndex)
        assertFalse(flow.holdUnderWay, "set 2 waits on its own button")
        flow.skipSet()
        flow.startHoldExercise()
        run(flow) { flow.phase == Phase.ExerciseSummary }
        assertEquals(listOf(45, 30, 45), flow.actuals[Pattern.coreAntiExt], "the premise: the gap reads the plan")
    }

    /** A 3×8 squat in the store's own state: session 1 opens on it. */
    private fun squatFlow(): Pair<WorkoutSession, AppStore> {
        val state = EngineState.initial
        state.doses[Pattern.squat] = 8
        val store = makeStore()
        store.update { it.copy(engineState = state) }
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = index(Pattern.squat, flow)
        assertEquals(LoadUnit.reps, flow.exercise.unit, "the premise: reps")
        assertEquals(3, flow.exercise.sets, "the premise: three sets")
        assertEquals(8, flow.exercise.load, "the premise: 8 each")
        assertNull(flow.exercise.loads)
        return flow to store
    }

    // MARK: - The fold

    /** Set 2 skipped under "Set the time" 45: what the engine takes is the
     *  45 the two sets held, not the mean of 45, a skipped 30 and 45 — the
     *  summary's preview is the engine's own answer to the honest number. */
    @Test
    fun aSkippedHoldSetIsNotFoldedIntoWhatTheEngineTakes() {
        val (flow, store) = plankFlow()
        declareAndSkipTheMiddleSet(flow)
        val honest = assertNotNull(store.previewPlan(
            after = flow.session, pattern = Pattern.coreAntiExt, overrides = mapOf(Pattern.coreAntiExt to 45.0),
            skipped = emptySet(), setsSkipped = mapOf(Pattern.coreAntiExt to 1), probes = emptyMap(),
            raised = emptyMap()))
        assertEquals(honest, flow.nextPlan(withAdditions = 0),
                     "the plan from the 45 the two sets held, not from 40")
    }

    /** The same in reps, where the fold is the same code: 3×8 done as "10,
     *  skipped, 8" folds to 9, not 8.67. */
    @Test
    fun aSkippedRepsSetIsNotFoldedEither() {
        val (flow, store) = squatFlow()
        flow.startAdjusting()
        flow.adjustValue = 10
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        assertEquals(Phase.Rest(flow.exercise.restExerciseSec), flow.phase)
        val honest = assertNotNull(store.previewPlan(
            after = flow.session, pattern = Pattern.squat, overrides = mapOf(Pattern.squat to 9.0),
            skipped = emptySet(), setsSkipped = mapOf(Pattern.squat to 1), probes = emptyMap(),
            raised = emptyMap()))
        assertEquals(honest, flow.nextPlan(withAdditions = 0), "10, skipped, 8 is a 9")
    }

    // MARK: - The journal

    /** The history line is the sets that were done: 45 and 45, with no 30
     *  for the set nobody held — and it still is once the journal has been
     *  written to disk and read back. (The history line itself is a screen's;
     *  what the record keeps for it is checked here.) */
    @Test
    fun theHistoryLineIsTheSetsThatWereDone() {
        val (flow, store) = plankFlow()
        declareAndSkipTheMiddleSet(flow)
        flow.leaveExerciseSummary()
        flow.rate(FeedbackResult.plan)
        assertNotNull(store.records.lastOrNull())
        val reread = assertNotNull(makeStore().records.lastOrNull())
        assertEquals(mapOf(Pattern.coreAntiExt to listOf(1)), reread.skippedSetIndices)
    }

    /** A changed rating folds the record again — from the sets that were
     *  done, which the record has to say. */
    @Test
    fun aChangedRatingFoldsOnlyTheSetsThatWereDone() {
        val (flow, store) = plankFlow()
        declareAndSkipTheMiddleSet(flow)
        flow.leaveExerciseSummary()
        flow.rate(FeedbackResult.plan)
        store.changeLastRating(to = FeedbackResult.less)
        assertEquals(45, store.records.lastOrNull()?.actuals?.get(Pattern.coreAntiExt))
    }

    /** The rating hands the engine the session's own fold, the skipped set
     *  left out, and the screen prints the same sets: no view argument
     *  carries the skipped sets to either. */
    @Test
    fun theRatingHandsTheEngineTheFoldWithoutTheSkippedSet() {
        val (flow, store) = plankFlow()
        declareAndSkipTheMiddleSet(flow)
        flow.leaveExerciseSummary()
        assertEquals(45.0, flow.overrides[Pattern.coreAntiExt])
        assertEquals(listOf(45, 45), flow.actualSets[Pattern.coreAntiExt])
        flow.rate(FeedbackResult.plan)
        assertEquals(45, store.records.lastOrNull()?.actuals?.get(Pattern.coreAntiExt))
    }

    // MARK: - A number entered before a skip

    /** "Went differently" → 6 on the set in front of the person, then "Skip
     *  this set". */
    private fun enterSixAndSkipTheSet(flow: WorkoutSession) {
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.skipSet()
    }

    /** "8, entered 6 then Skip this set, 6" on 3×8: the 6 the person entered
     *  is theirs and counts — 8, 6, 6 is 6.67 — while the set still goes off
     *  the plan as a skipped one. A workout settled from there folds the same. */
    @Test
    fun aSkippedSetKeepsTheNumberEnteredForIt() {
        val (flow, store) = squatFlow()
        flow.completeSet()
        flow.skipRest()
        enterSixAndSkipTheSet(flow)
        flow.completeSet()
        assertEquals(1, flow.setsSkipped[Pattern.squat])
        assertEquals(setOf(1), flow.skippedSetIndices[Pattern.squat], "still a skipped set, for the count and the cut")
        assertEquals(20.0 / 3.0, assertNotNull(flow.overrides[Pattern.squat]), 1e-9)
        assertEquals(listOf(8, 6, 6), flow.actualSets[Pattern.squat])

        val snap = assertNotNull(store.pendingWorkout)
        val back = makeFlow(store, resume = snap)
        assertEquals(20.0 / 3.0, assertNotNull(back.overrides[Pattern.squat]), 1e-9,
                     "a process death keeps the number")
        val settled = WorkoutSessionStore.settlement(snap, flow.session)
        assertEquals(20.0 / 3.0, assertNotNull(settled.overrides[Pattern.squat]), 1e-9)
        assertTrue(store.settleAbandonedWorkout(now = snap.savedAt.plus(WorkoutSessionStore.forgottenAfter)))
    }

    /** "8, 8, entered 6 then Skip this set" on the last set: 8, 8, 6 is 7.33,
     *  the history reads 8-8-6, and a changed rating folds it the same. */
    @Test
    fun theLastSetSkippedKeepsTheNumberEnteredForIt() {
        val (flow, store) = squatFlow()
        repeat(2) {
            flow.completeSet()
            flow.skipRest()
        }
        enterSixAndSkipTheSet(flow)
        assertNotEquals(Pattern.squat, flow.exercise.pattern, "the last set skipped moves on")
        assertEquals(22.0 / 3.0, assertNotNull(flow.overrides[Pattern.squat]), 1e-9)
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        store.changeLastRating(to = FeedbackResult.less)
        assertEquals(7, store.records.lastOrNull()?.actuals?.get(Pattern.squat), "8, 8, 6 again, not 8, 8")
    }

    /** A number entered before a skip counts beside the sets after it: "8,
     *  entered 6 then skipped, entered 8" on 3×8 is 8, 6, 8 — 7.33. */
    @Test
    fun aNumberEnteredBeforeASkipCountsBesideTheSetsAfterIt() {
        val (flow, _) = squatFlow()
        flow.completeSet()
        flow.skipRest()
        enterSixAndSkipTheSet(flow)
        flow.startAdjusting()
        flow.adjustValue = 8
        flow.commitSetEdit()
        assertEquals(listOf(8, 6, 8), flow.actuals[Pattern.squat])
        assertEquals(22.0 / 3.0, assertNotNull(flow.overrides[Pattern.squat]), 1e-9)
    }

    /** "Skip the remaining sets" called on the last set of 3×8 after 6 was
     *  entered for it — the screen offers "Skip this set" there, which names
     *  the same set — keeps the 6: 8, 8, 6, 7.33. */
    @Test
    fun skippingTheRemainingSetsKeepsTheNumberEnteredForTheSetInFront() {
        val (flow, _) = squatFlow()
        doTwoSetsAtPlanAndEnterSixOnTheThird(flow)
        flow.skipRestOfExercise()
        assertEquals(setOf(2), flow.skippedSetIndices[Pattern.squat])
        assertEquals(22.0 / 3.0, assertNotNull(flow.overrides[Pattern.squat]), 1e-9)
    }

    /** No number for the skipped set: what a later set's record fills its gap
     *  with is what was in force, not the person's, and stays out — "10,
     *  skipped, entered 8" is 9, though the facts read 10, 8, 8. */
    @Test
    fun aGapFilledAfterASkipIsNotANumberEnteredForIt() {
        val (flow, _) = squatFlow()
        flow.startAdjusting()
        flow.adjustValue = 10
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.startAdjusting()
        flow.adjustValue = 8
        flow.commitSetEdit()
        assertEquals(listOf(10, 8, 8), flow.actuals[Pattern.squat], "the premise: the gap reads what was in force")
        assertEquals(9.0, flow.overrides[Pattern.squat])
    }

    // MARK: - The summary's cards

    /** No card for the skipped set, and the others keep their own numbers:
     *  "set 1", "set 3". The last working set is still the one that opens. */
    @Test
    fun theSummaryHasNoCardForTheSkippedSet() {
        val (flow, _) = plankFlow()
        declareAndSkipTheMiddleSet(flow)
        assertEquals(listOf(
            HeldSet(index = 0, seconds = 45, planned = 30, approximate = false, correctable = false),
            HeldSet(index = 2, seconds = 45, planned = 30, approximate = false, correctable = true),
        ), flow.heldSets)
    }

    /** 30 on the clock, set 2 skipped, set 3 stopped by hand at 20 s (≈17):
     *  the hand-stopped card carries its mark and opens, and the fold is the
     *  23.5 the two sets ran rather than 25.67 with a 30 nobody held. */
    @Test
    fun aHandStoppedCardAfterASkippedSetIsMarkedAndOpens() {
        val (flow, _) = plankFlow()
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 30)
        advance(600)
        flow.tick()
        flow.skipSet()
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 20)
        flow.stopHoldEarly()
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertEquals(listOf(
            HeldSet(index = 0, seconds = 30, planned = 30, approximate = false, correctable = false),
            HeldSet(index = 2, seconds = 17, planned = 30, approximate = true, correctable = true),
        ), flow.heldSets)
        assertEquals(23.5, SetFacts.override(flow.actuals, flow.exercise, skipping = flow.leftOutHere))
    }

    /** A process death on that summary keeps the set off it: the indices
     *  travel in the snapshot. */
    @Test
    fun theSkippedSetStaysOffTheSummaryAcrossAProcessDeath() {
        val (flow, store) = plankFlow()
        declareAndSkipTheMiddleSet(flow)
        val snap = assertNotNull(store.pendingWorkout)
        assertEquals(mapOf(Pattern.coreAntiExt to listOf(1)), snap.skippedSetIndices)
        val back = makeFlow(store, resume = snap)
        assertEquals(Phase.ExerciseSummary, back.phase)
        assertEquals(mapOf(Pattern.coreAntiExt to setOf(1)), back.skippedSetIndices)
        assertEquals(listOf(0, 2), back.heldSets.map { it.index })
    }

    // MARK: - Every way a set is skipped

    /** 10 entered on the first two sets of the 3×8 squat; set 3 is next. */
    private fun doTwoSetsOfTen(flow: WorkoutSession) {
        repeat(2) {
            flow.startAdjusting()
            flow.adjustValue = 10
            flow.commitSetEdit()
            flow.completeSet()
            flow.skipRest()
        }
        assertEquals(2, flow.setIndex)
        assertEquals(listOf(10, 10), flow.actuals[Pattern.squat])
    }

    /** "Skip the remaining sets": the set taken off is named, and the fold
     *  is the 10 the two sets ran — not 9.33, with the plan's 8 for the third. */
    @Test
    fun theSetsSkipTheRemainingSetsTakesOffAreNotFolded() {
        val (flow, _) = squatFlow()
        doTwoSetsOfTen(flow)
        flow.skipRestOfExercise()
        assertEquals(setOf(2), flow.skippedSetIndices[Pattern.squat])
        assertEquals(10.0, SetFacts.overrides(flow.actuals, skipping = flow.skippedSetIndices,
                                              exercises = flow.exercises)[Pattern.squat])
    }

    /** Sets 1 and 2 of the 3×8 squat on plan, and 6 entered for set 3, the
     *  set in progress ("Went differently" → OK). */
    private fun doTwoSetsAtPlanAndEnterSixOnTheThird(flow: WorkoutSession) {
        repeat(2) {
            flow.completeSet()
            flow.skipRest()
        }
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        assertEquals(2, flow.setIndex)
        assertEquals(listOf(8, 8, 6), flow.actuals[Pattern.squat])
    }

    /** The fold the rating would hand the engine for the squat. */
    private fun squatFold(flow: WorkoutSession): Double =
        assertNotNull(SetFacts.overrides(flow.actuals, skipping = flow.skippedSetIndices,
                                         exercises = flow.exercises)[Pattern.squat])

    /** "Finish now" on set 3: the set it never reached travels as a skipped
     *  set — the count — but nobody skipped it, and it folds at what was in
     *  force for it: "10, 10, Finish now" on 3×8 is 9.33, with the plan's 8
     *  for the third. */
    @Test
    fun finishNowFoldsTheSetItNeverReachedAtWhatWasInForce() {
        val (flow, store) = squatFlow()
        doTwoSetsOfTen(flow)
        flow.finishNow()
        assertEquals(Phase.Feedback, flow.phase)
        assertEquals(1, flow.setsSkipped[Pattern.squat])
        assertNull(flow.skippedSetIndices[Pattern.squat], "a set never reached is not a set skipped")
        assertEquals(28.0 / 3.0, squatFold(flow), 1e-9)
        assertNull(store.pendingWorkout?.skippedSetIndices)
    }

    /** The number entered for the set in progress is a fact about that set,
     *  and "Finish now" folds it: 8, 8, 6 is 7.33, not the 8 of the two sets
     *  before it. */
    @Test
    fun finishNowFoldsTheNumberEnteredForTheSetInProgress() {
        val (flow, _) = squatFlow()
        doTwoSetsAtPlanAndEnterSixOnTheThird(flow)
        flow.finishNow()
        assertEquals(1, flow.setsSkipped[Pattern.squat])
        assertNull(flow.skippedSetIndices[Pattern.squat])
        assertEquals(22.0 / 3.0, squatFold(flow), 1e-9)
    }

    /** A workout left on set 3 and never come back to settles by the same
     *  rule, and the journal names no skipped set for it. */
    @Test
    fun aForgottenWorkoutFoldsTheSetItNeverReachedAtWhatWasInForce() {
        val (flow, store) = squatFlow()
        doTwoSetsOfTen(flow)
        val snap = assertNotNull(store.pendingWorkout)
        val settled = WorkoutSessionStore.settlement(snap, flow.session)
        assertEquals(1, settled.setsSkipped[Pattern.squat])
        assertNull(settled.skippedSets[Pattern.squat])
        assertEquals(28.0 / 3.0, assertNotNull(settled.overrides[Pattern.squat]), 1e-9)

        assertTrue(store.settleAbandonedWorkout(now = snap.savedAt.plus(WorkoutSessionStore.forgottenAfter)))
        val record = assertNotNull(store.records.lastOrNull())
        assertNull(record.skippedSetIndices)
        assertEquals(9, record.actuals?.get(Pattern.squat))
    }

    /** …and folds the number entered for the set in progress: 7.33. */
    @Test
    fun aForgottenWorkoutFoldsTheNumberEnteredForTheSetInProgress() {
        val (flow, store) = squatFlow()
        doTwoSetsAtPlanAndEnterSixOnTheThird(flow)
        val snap = assertNotNull(store.pendingWorkout)
        val settled = WorkoutSessionStore.settlement(snap, flow.session)
        assertNull(settled.skippedSets[Pattern.squat])
        assertEquals(22.0 / 3.0, assertNotNull(settled.overrides[Pattern.squat]), 1e-9)
    }

    /** A forgotten workout still leaves out the set the person skipped:
     *  "10, skipped, 8" on 3×8, left on the rest after set 3, settles at 9
     *  and the journal names the skipped set. */
    @Test
    fun aForgottenWorkoutLeavesOutTheSetThePersonSkipped() {
        val (flow, store) = squatFlow()
        flow.startAdjusting()
        flow.adjustValue = 10
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        assertEquals(Phase.Rest(flow.exercise.restExerciseSec), flow.phase)
        val snap = assertNotNull(store.pendingWorkout)
        val settled = WorkoutSessionStore.settlement(snap, flow.session)
        assertEquals(setOf(1), settled.skippedSets[Pattern.squat])
        assertEquals(9.0, settled.overrides[Pattern.squat])

        assertTrue(store.settleAbandonedWorkout(now = snap.savedAt.plus(WorkoutSessionStore.forgottenAfter)))
        val record = assertNotNull(store.records.lastOrNull())
        assertEquals(mapOf(Pattern.squat to listOf(1)), record.skippedSetIndices)
        assertEquals(9, record.actuals?.get(Pattern.squat))
    }

    /** A movement "Finish now" calls not finished keeps none of the sets
     *  skipped in it, like the count: there is no trained movement to name
     *  them for. The same for a forgotten workout. */
    @Test
    fun aMovementLeftUntrainedKeepsNoSkippedSets() {
        val (flow, store) = squatFlow()
        enterSixAndSkipTheSet(flow)
        assertEquals(setOf(0), flow.skippedSetIndices[Pattern.squat])
        assertEquals(setOf(0), flow.skippedWithNumber[Pattern.squat])
        val snap = assertNotNull(store.pendingWorkout)
        val settled = WorkoutSessionStore.settlement(snap, flow.session)
        assertTrue(Pattern.squat in settled.skipped)
        assertNull(settled.skippedSets[Pattern.squat])
        assertNull(settled.skippedWithNumber[Pattern.squat])

        flow.finishNow()
        assertEquals(Pattern.squat, flow.interruptedPattern)
        assertNull(flow.skippedSetIndices[Pattern.squat])
        assertNull(flow.skippedWithNumber[Pattern.squat])
    }

    /** Leaving the movement takes its skipped sets with it, like the count:
     *  a movement not trained has no sets to name, numbered or not. */
    @Test
    fun leavingAMovementDropsItsSkippedSets() {
        val (flow, _) = squatFlow()
        enterSixAndSkipTheSet(flow)
        assertEquals(setOf(0), flow.skippedSetIndices[Pattern.squat])
        assertEquals(setOf(0), flow.skippedWithNumber[Pattern.squat])
        flow.leaveExercise()
        assertNull(flow.skippedSetIndices[Pattern.squat])
        assertNull(flow.skippedWithNumber[Pattern.squat])
        assertTrue(Pattern.squat in flow.skippedPatterns)
    }
}

/** The fold without the sets the person skipped, without a flow around it.
 *  Port of `PerformedSetsFoldTests` in the same Swift file. */
class PerformedSetsFoldTest : AppStoreTestCase() {

    /** 3×8 squats, as the engine hands them out. */
    private fun squat(): SessionExercise {
        val state = EngineState.initial
        state.doses[Pattern.squat] = 8
        val ex = assertNotNull(Engine.generateSession(state).exercises.firstOrNull { it.pattern == Pattern.squat })
        assertEquals(listOf(3, 8), listOf(ex.sets, ex.load), "the premise: 3×8")
        return ex
    }

    /** "Plank" 3×30 s, as the engine hands it out. */
    private fun plank(): SessionExercise {
        val state = EngineState.initial
        state.counter = 1
        state.vars[Pattern.coreAntiExt] = 3
        state.doses[Pattern.coreAntiExt] = 30
        val ex = assertNotNull(Engine.generateSession(state).exercises.firstOrNull { it.pattern == Pattern.coreAntiExt })
        assertEquals(listOf(3, 30), listOf(ex.sets, ex.load), "the premise: 3×30 s")
        return ex
    }

    /** "10, skipped, 8" on 3×8 is a 9 — not 8.67, which reads the skipped
     *  set as the 8 the plan asked. */
    @Test
    fun theFoldIsTheMeanOfTheSetsThatWereDone() {
        val ex = squat()
        val facts = SetFacts.recording(10, emptyMap(), ex, set = 0)
        val done = SetFacts.performed(facts, ex, skipping = setOf(1))
        assertEquals(listOf(0, 2), done.map { it.first })
        assertEquals(listOf(10, 8), done.map { it.second })
        assertEquals(9.0, SetFacts.override(facts, ex, skipping = setOf(1)))
        assertEquals(mapOf(Pattern.squat to 9.0),
                     SetFacts.overrides(facts, skipping = mapOf(Pattern.squat to setOf(1)), exercises = listOf(ex)))
        val unnamed = assertNotNull(SetFacts.override(facts, ex, skipping = emptySet()))
        assertEquals(26.0 / 3.0, unnamed, 1e-9, "without the index the gap reads the plan")
    }

    /** With every set skipped there is nothing to set apart: the sets read as
     *  they always did. */
    @Test
    fun everySetSkippedReadsAsBefore() {
        val ex = squat()
        val facts = SetFacts.recording(10, emptyMap(), ex, set = 0)
        assertEquals(SetFacts.allSets(facts, ex),
                     SetFacts.performed(facts, ex, skipping = setOf(0, 1, 2)).map { it.second })
        assertEquals(SetFacts.override(facts, ex, skipping = emptySet()),
                     SetFacts.override(facts, ex, skipping = setOf(0, 1, 2)))
    }

    /** The probe caption's half of the fold: 5, a skipped set and 12 on 3×8
     *  is 8.5 — the plan met, though the skipped set read as a 5 would take
     *  the mean under it. */
    @Test
    fun aSkippedSetDoesNotMakeTheFoldFallShort() {
        val ex = squat()
        val facts = SetFacts.recording(12, SetFacts.recording(5, emptyMap(), ex, set = 0), ex, set = 2)
        assertEquals(listOf(5, 5, 12), SetFacts.allSets(facts, ex), "the premise: the gap carries the 5")
        assertTrue(SetFacts.foldFallsShort(facts, of = ex, skipping = emptySet()))
        assertFalse(SetFacts.foldFallsShort(facts, of = ex, skipping = setOf(1)))
    }

    /** Off disk, an index is kept or dropped — never moved onto another set. */
    @Test
    fun skippedSetsOffDiskAreKeptOrDropped() {
        var snap = WorkoutSnapshot(sessionNumber = 3, exIndex = 0, setIndex = 0,
                                   restEndDate = null, restTotalSec = null,
                                   workoutStart = Instant.now(), savedAt = Instant.now())
        assertEquals(emptyMap(), snap.skippedSets)
        snap = snap.copy(skippedSetIndices = mapOf(Pattern.squat to listOf(1, 9, -1), Pattern.pushH to emptyList()))
        assertEquals(mapOf(Pattern.squat to setOf(1)), snap.skippedSets)
        val json = """
        {"sessionNumber": 3, "date": 1000, "result": "plan",
         "skippedSetIndices": ["core_anti_ext", [1, 7, -2]],
         "skippedWithNumberIndices": ["core_anti_ext", [1, 6]]}
        """
        val record = WorkoutRecord.fromJson(Json.parseToJsonElement(json))
        assertEquals(mapOf(Pattern.coreAntiExt to listOf(1)), record.skippedSetIndices)
        assertEquals(mapOf(Pattern.coreAntiExt to setOf(1)), record.skippedSets)
        assertEquals(mapOf(Pattern.coreAntiExt to listOf(1)), record.skippedWithNumberIndices)
    }

    /** A record written without the indices reads as it always did: the
     *  history keeps the set the old reading kept, and a changed rating
     *  folds every set. (The history's read of the plank is a screen's; the
     *  plank premise still runs.) */
    @Test
    fun aRecordWithoutTheIndicesReadsAsItAlwaysDid() {
        plank()
        val json = """
        {"sessionNumber": 3, "date": 1000, "result": "plan",
         "setActuals": ["core_anti_ext", [45, 30, 45]], "setsSkipped": ["core_anti_ext", 1]}
        """
        val record = WorkoutRecord.fromJson(Json.parseToJsonElement(json))
        assertNull(record.skippedSetIndices)
        assertEquals(emptyMap(), record.skippedSets)

        val state = EngineState.initial
        state.counter = 1
        state.vars[Pattern.coreAntiExt] = 3
        state.doses[Pattern.coreAntiExt] = 30
        val store = makeStore()
        store.update { it.copy(engineState = state) }
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              setActuals = mapOf(Pattern.coreAntiExt to listOf(45, 30, 45)),
                              setsSkipped = mapOf(Pattern.coreAntiExt to 1))
        assertNull(store.records.lastOrNull()?.skippedSetIndices)
        store.changeLastRating(to = FeedbackResult.less)
        assertEquals(40, store.records.lastOrNull()?.actuals?.get(Pattern.coreAntiExt), "every set, as before")
    }
}
