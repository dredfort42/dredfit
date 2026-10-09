//
//  Port of ios/DredfitTests/NextTimeTests.swift: the addition "for next
//  time" — where it is kept, where it lands, and what the store says about
//  it afterwards.
//
//  Not ported yet, each with the code it needs: the correction range
//  (`SetFacts.correctionRange`, the workout flow's writing half), the preview
//  (`previewPlan` / PlannedPosition), the summary's and the history's words
//  (`NextTimeBlock`, `RaiseLabel`, `ExerciseRow`, `HistorySheet`) and the
//  snapshot's `measuredHold` (the hold screens). The `HistorySheet.afterLine`
//  check inside `theJournalNamesTheShareThatLandedAndKeepsTheDecision` waits
//  for the same screen.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Position
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.raiseDose
import com.dredfit.journal.RecordedPosition
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppStore
import com.dredfit.store.currentPositions
import com.dredfit.store.landed
import com.dredfit.store.nextSession
import com.dredfit.store.raisedForNextPlan
import kotlinx.serialization.json.Json
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class NextTimeTest : AppStoreTestCase() {

    // MARK: - The addition through the store

    private data class HoldFixture(val store: AppStore, val session: Session, val hold: SessionExercise)

    private fun storeWithHold(): HoldFixture {
        val store = makeStore()
        // The second session is the first with a hold in it (the rotation).
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        val session = store.nextSession
        val hold = assertNotNull(session.exercises.firstOrNull { it.unit == LoadUnit.hold })
        return HoldFixture(store, session, hold)
    }

    private fun measure(p: Pattern, r: RecordedPosition): Int =
        Engine.progress(p, Position(variation = r.variation, sets = r.sets, dose = r.dose,
                                    sub = r.sub ?: 0, cut = r.cut ?: 0))

    /** A plan with `pattern` in it, reached by training on plan. */
    private fun storeReaching(pattern: Pattern): AppStore {
        val store = makeStore()
        var tries = 0
        while (store.nextSession.exercises.none { it.pattern == pattern } && tries < 12) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
            tries += 1
        }
        return store
    }

    /** The raise lands over the rating and is written down: the record
     *  carries it, and the position after is one step above the rating's. */
    @Test
    fun theAdditionLandsOverTheRatingAndIsRecorded() {
        val (store, session, hold) = storeWithHold()
        val alone = makeStore()
        alone.completeWorkout(session = session, result = FeedbackResult.plan)
        store.completeWorkout(session = session, result = FeedbackResult.plan, raised = mapOf(hold.pattern to 1))

        val without = assertNotNull(alone.currentPositions[hold.pattern])
        val withRaise = assertNotNull(store.currentPositions[hold.pattern])
        assertEquals(measure(hold.pattern, without) + 1, measure(hold.pattern, withRaise),
                     "one step for next time is one growth event over the rating's")
        val record = makeStore().records.last()
        assertEquals(mapOf(hold.pattern to 1), record.raisedSteps, "the journal keeps the decision")
        // …and the store the record came from says so on tomorrow's plan.
        assertEquals(1, store.raisedForNextPlan(hold.pattern))
        assertEquals(0, store.raisedForNextPlan(session.exercises[0].pattern))
    }

    /** Changing the rating afterwards keeps the addition: it was a decision
     *  about the movement, not about the rating. */
    @Test
    fun changingTheRatingKeepsTheAddition() {
        val (store, session, hold) = storeWithHold()
        store.completeWorkout(session = session, result = FeedbackResult.plan, raised = mapOf(hold.pattern to 1))
        val before = store.currentPositions[hold.pattern]
        store.changeLastRating(to = FeedbackResult.less)
        val record = store.records.last()
        assertEquals(FeedbackResult.less, record.result)
        assertEquals(mapOf(hold.pattern to 1), record.raisedSteps)
        assertNotEquals(before, store.currentPositions[hold.pattern],
                        "the rating moved the position; the addition stayed on top of it")
        assertEquals(1, store.raisedForNextPlan(hold.pattern))
    }

    /** The journal names the share that LANDED and keeps the decision apart.
     *  "+10 s" on 3×40 s rated "easy": the rating takes the base to 45-45-40,
     *  one step makes it 3×45 and the other burns. A changed rating replays
     *  the two the person asked for and, under "on plan", lands both. */
    @Test
    fun theJournalNamesTheShareThatLandedAndKeepsTheDecision() {
        val pattern = Pattern.coreAntiExt
        val store = storeReaching(pattern)
        // One rung under the top of the hold grid, never shown there: the
        // plan reads 3×40 s with no gate in the way.
        store.update { s ->
            s.copy(engineState = s.engineState.copy().also { it.doses[pattern] = Dose.hold.max - Dose.hold.step })
        }
        val session = store.nextSession
        val hold = assertNotNull(session.exercises.firstOrNull { it.pattern == pattern })
        assertEquals(Dose.hold.max - Dose.hold.step, hold.load, "the premise: 3×40 s")
        assertNull(hold.loads, "the premise: a uniform plan")
        assertEquals(EngineConfig.setsBase, hold.sets)

        store.completeWorkout(session = session, result = FeedbackResult.more, raised = mapOf(pattern to 2))
        val record = store.records.last()
        assertEquals(mapOf(pattern to 2), record.raisedSteps, "the decision is kept as tapped")
        assertEquals(mapOf(pattern to 1), record.raisedLanded, "one step landed, the other burned")
        val after = assertNotNull(store.currentPositions[pattern])
        assertEquals(Dose.hold.max, after.dose)
        assertNull(after.sub)
        assertEquals(1, store.raisedForNextPlan(pattern), "tomorrow's note names the landed share")

        // Under "on plan" the base is 45-40-40 and both steps land.
        store.changeLastRating(to = FeedbackResult.plan)
        val redone = store.records.last()
        assertEquals(mapOf(pattern to 2), redone.raisedSteps, "the decision survived the change")
        assertEquals(mapOf(pattern to 2), redone.raisedLanded)
        assertEquals(2, store.raisedForNextPlan(pattern))
        assertEquals(Dose.hold.max, store.currentPositions[pattern]?.dose)
    }

    /** Under a cut, the step that completes a rung moves the measure by more
     *  than one event, so a second step burned on the ceiling would hide
     *  inside the first one's jump (#277). Knee plank on 45-40 s, one set
     *  cut: the first tap makes it 2×45, the second has nowhere to go. */
    @Test
    fun aStepBurnedOnTheCeilingUnderACutIsNotCountedAsLanded() {
        val p = Pattern.coreAntiExt
        val unraised = EngineState.initial.also {
            it.vars[p] = 1
            it.doses[p] = Dose.hold.max - Dose.hold.step
            it.sets[p] = EngineConfig.setsBase
            it.sub[p] = 1
            it.cut[p] = 1
        }
        val raised = Engine.raiseDose(state = unraised, pattern = p, steps = 2)
        assertEquals(Dose.hold.max, raised.doses[p], "the premise: the first step reaches the top")
        assertEquals(mapOf(p to 1), landed(mapOf(p to 2), unraised))
    }

    /** The same through the store: 40-40-35 s, one set skipped, "easy", two
     *  taps on "+". The rating and the cut leave 45-40; the first tap lands,
     *  the second burns. */
    @Test
    fun theStoreRecordsOnlyTheStepThatLandedUnderACut() {
        val pattern = Pattern.coreAntiExt
        val store = storeReaching(pattern)
        store.update { s ->
            s.copy(engineState = s.engineState.copy().also {
                it.vars[pattern] = 2
                it.doses[pattern] = 35
                it.sets[pattern] = EngineConfig.setsBase
                it.sub[pattern] = 2
                it.cut[pattern] = 0
            })
        }
        val session = store.nextSession
        val hold = assertNotNull(session.exercises.firstOrNull { it.pattern == pattern })
        assertEquals(listOf(40, 40, 35), hold.loads, "the premise: 40-40-35 s")

        store.completeWorkout(session = session, result = FeedbackResult.more, setsSkipped = mapOf(pattern to 1),
                              raised = mapOf(pattern to 2))
        val record = store.records.last()
        assertEquals(Dose.hold.max, store.currentPositions[pattern]?.dose, "the premise: the raise reached the top")
        assertEquals(mapOf(pattern to 1), record.raisedLanded)
        assertEquals(1, store.raisedForNextPlan(pattern))
    }

    /** A record written before the share existed falls back to the decision;
     *  a record that says nothing landed says so even with the decision on it. */
    @Test
    fun theShareFallsBackToTheDecisionOnlyWhereThereIsNone() {
        var record = WorkoutRecord(sessionNumber = 1, date = Instant.now(), result = FeedbackResult.plan,
                                   raisedSteps = mapOf(Pattern.squat to 2))
        assertEquals(2, record.raisedShare(Pattern.squat))
        record = record.copy(raisedLanded = emptyMap())
        assertEquals(0, record.raisedShare(Pattern.squat))
        record = record.copy(raisedLanded = mapOf(Pattern.squat to 1))
        assertEquals(1, record.raisedShare(Pattern.squat))
        assertEquals(0, record.raisedShare(Pattern.pushH))
    }

    /** The note on tomorrow's plan belongs to a rise still standing: once
     *  something else moves the movement — a decay or a comeback would — the
     *  note stands down. */
    @Test
    fun theAdditionNoteStandsDownWhenTheMovementMovedSince() {
        val (store, session, hold) = storeWithHold()
        store.completeWorkout(session = session, result = FeedbackResult.plan, raised = mapOf(hold.pattern to 1))
        assertEquals(1, store.raisedForNextPlan(hold.pattern))
        store.update { s -> s.copy(engineState = Engine.raiseDose(state = s.engineState, pattern = hold.pattern, steps = 1)) }
        assertEquals(0, store.raisedForNextPlan(hold.pattern))
    }

    /** Off disk the count is clamped to what the engine accepts. */
    @Test
    fun aRaiseOffDiskIsClampedToWhatTheEngineTakes() {
        val record = WorkoutRecord.fromJson(Json.parseToJsonElement("""
            {"sessionNumber": 3, "date": 1000, "result": "plan",
             "raisedSteps": ["core_anti_ext", 40, "squat", -2],
             "raisedLanded": ["core_anti_ext", 9]}
        """))
        assertEquals(EngineConfig.raiseStepsMax, record.raisedSteps?.get(Pattern.coreAntiExt))
        assertEquals(0, record.raisedSteps?.get(Pattern.squat))
        assertEquals(EngineConfig.raiseStepsMax, record.raisedLanded?.get(Pattern.coreAntiExt))
    }
}
