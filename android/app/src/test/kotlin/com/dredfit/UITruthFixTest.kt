//
//  Port of ios/DredfitTests/UITruthFixTests.swift: pins that keep what the UI
//  says true — comparisons against each set's own plan (a flat-load
//  comparison shows a plan as a fact and hides a recorded shortfall), the
//  milestone label that lands on its own tick, and the snapshot that carries
//  the sparse coordinates the row's number includes.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Position
import com.dredfit.core.SessionExercise
import com.dredfit.core.applyComeback
import com.dredfit.core.applyFeedback
import com.dredfit.core.applySilentDecay
import com.dredfit.core.generateSession
import com.dredfit.core.setCut
import com.dredfit.journal.RecordedPosition
import com.dredfit.store.positions
import com.dredfit.workout.SetFacts
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UITruthFixTest {

    /** The uneven plan every flat-load defect hid behind: 9-8-8. */
    private fun unevenExercise() = SessionExercise(
        pattern = Pattern.squat, name = "Squat", variation = 1, unit = LoadUnit.reps, load = 8, perSide = false,
        sets = 3, restSetSec = 60, restExerciseSec = 60, loads = listOf(9, 8, 8), probe = null)

    // MARK: - The work screen's "actual N"

    @Test
    fun offPlanIsSilentOnTheUntouchedTopSetOfAnUnevenPlan() {
        val ex = unevenExercise()
        assertNull(SetFacts.offPlan(emptyMap(), ex, set = 0), "nothing was entered — the planned 9 is not an actual")
        assertNull(SetFacts.offPlan(emptyMap(), ex, set = 1))
    }

    @Test
    fun offPlanShowsABelowPlanEntryEqualToTheBase() {
        val ex = unevenExercise()
        val facts = SetFacts.recording(8, emptyMap(), ex, set = 0)
        assertEquals(8, SetFacts.offPlan(facts, ex, set = 0), "8 on a set planned at 9 is a real shortfall to accent")
    }

    // MARK: - History's guard

    @Test
    fun differsSeesAShortfallThatMatchesTheBaseDose() {
        val ex = unevenExercise()
        assertTrue(SetFacts.differs(listOf(8, 8, 8), from = ex), "8-8-8 against a plan of 9-8-8 is not \"ran to plan\"")
        assertFalse(SetFacts.differs(listOf(9, 8, 8), from = ex))
    }

    // MARK: - The probe caption's knowable gate

    @Test
    fun foldBelowThePlanMeansTheProbeWillNotCount() {
        val ex = unevenExercise()
        var short: Map<Pattern, List<Int>> = emptyMap()
        for (set in 0 until 3) short = SetFacts.recording(8, short, ex, set)
        assertTrue(SetFacts.foldFallsShort(short, of = ex, skipping = emptySet()))
        // 9-8-8 done as written collapses to nothing said at all.
        val onPlan = SetFacts.recording(9, emptyMap(), ex, set = 0)
        assertFalse(SetFacts.foldFallsShort(onPlan, of = ex, skipping = emptySet()))
    }

    // MARK: - The next-milestone label counts the crossing, not the ceiling

    @Test
    fun milestoneDistanceEqualsTheOrdinalGapToTheNextVariation() {
        for ((pattern, cut) in listOf(Pattern.squat to 0, Pattern.squat to 1, Pattern.coreAntiExt to 0)) {
            var state = EngineState.initial
            val unit = Library.unit(pattern, 1)
            state.doses[pattern] = Dose.grid(unit).max - Dose.grid(unit).step
            if (cut > 0) state = Engine.setCut(state = state, pattern = pattern, cut = cut)
            val position = state.position(pattern)
            val labelled = Engine.stepsToVariationCeiling(state, pattern) + position.cut + 1
            val entry = Engine.progress(pattern, variation = 2, sets = EngineConfig.setsBase,
                                        dose = Dose.grid(Library.unit(pattern, 2)).min)
            assertEquals(labelled, entry - Engine.progress(state, pattern),
                         "$pattern cut $cut: the label must land on the next variation's own tick")
        }
    }

    // MARK: - Both sides of a per-side hold carry the same load

    @Test
    fun theFirstSideAloneDecidesHowLongTheSecondRuns() {
        assertEquals(30, SetFacts.holdSideSeconds(planned = 30, firstSideHeld = null))
        assertEquals(20, SetFacts.holdSideSeconds(planned = 30, firstSideHeld = 20))
        assertEquals(30, SetFacts.holdSideSeconds(planned = 30, firstSideHeld = 30))
    }

    @Test
    fun theSecondSideIsNeverLongerThanThePlan() {
        assertEquals(20, SetFacts.holdSideSeconds(planned = 20, firstSideHeld = 45))
    }

    /** A second side of three could not be stored (the corridor floor is
     *  five) nor stopped (every tap inside three seconds is a mis-tap). */
    @Test
    fun aVeryShortFirstSideStillLeavesAStoppableSecond() {
        val floor = SetFacts.corridor(LoadUnit.hold).first
        assertEquals(floor, SetFacts.holdSideSeconds(planned = 30, firstSideHeld = 3))
        assertEquals(floor, SetFacts.holdSideSeconds(planned = 30, firstSideHeld = 4))
        assertEquals(floor, SetFacts.holdSideSeconds(planned = 30, firstSideHeld = floor))
        // …and the floor never overrides a plan shorter than itself.
        assertEquals(3, SetFacts.holdSideSeconds(planned = 3, firstSideHeld = 3))
    }

    // MARK: - The maximum-out-of-order note

    @Test
    fun theMaximumNoteFiresOnlyAboveThisSetsOwnPlan() {
        val ex = unevenExercise()
        assertTrue(SetFacts.maximumOutOfOrder(12, ex, set = 0))
        assertTrue(SetFacts.maximumOutOfOrder(9, ex, set = 1))
        assertFalse(SetFacts.maximumOutOfOrder(9, ex, set = 0))
        assertFalse(SetFacts.maximumOutOfOrder(8, ex, set = 1))
        // The last set is what the note is FOR — never flagged.
        assertFalse(SetFacts.maximumOutOfOrder(99, ex, set = 2))
    }

    /** The fold is the mean, so the order of the sets does not reach the
     *  engine — measured, because a note advising an order would advise
     *  something the model does not do. */
    @Test
    fun theOrderOfAMaximumDoesNotReachTheEngine() {
        val state = EngineState.initial
        state.doses[Pattern.pull] = 8
        state.shown[Pattern.pull] = mutableMapOf(1 to 8)
        val session = Engine.generateSession(state)
        val ex = assertNotNull(session.exercises.firstOrNull { it.pattern == Pattern.pull })

        fun nextPlan(sets: List<Int>): String {
            var facts: Map<Pattern, List<Int>> = emptyMap()
            sets.forEachIndexed { i, v -> facts = SetFacts.recording(v, facts, ex, i) }
            val fold = SetFacts.override(facts, ex, skipping = emptySet())
            val next = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.plan,
                                            overrides = fold?.let { mapOf(Pattern.pull to it) } ?: emptyMap())
            return assertNotNull(Engine.generateSession(next).exercises.firstOrNull { it.pattern == Pattern.pull }).display
        }
        assertEquals(nextPlan(listOf(6, 6, 12)), nextPlan(listOf(12, 6, 6)),
                     "same total, different order — the engine cannot tell them apart")
        assertEquals(nextPlan(listOf(8, 8, 12)), nextPlan(listOf(12, 8, 8)),
                     "and the same holds when the plan is held on the other sets")
        assertNotEquals(nextPlan(listOf(8, 8, 12)), nextPlan(listOf(12, 6, 6)),
                        "what DOES move the plan is the total, which is what the note now says")
    }

    // MARK: - What a descent off a probing appearance may do

    /** Every pattern at the ceiling of its variation, the journal proving it. */
    private fun toppedOutOnEveryVariation(): EngineState {
        val state = EngineState.initial
        state.counter = 11
        for (p in Pattern.allCases) {
            val target = minOf(3, Library.count(p))
            state.vars[p] = target
            state.doses[p] = Dose.grid(Library.unit(p, target)).max
            state.shown[p] = (1..target).associateWith { v -> Dose.grid(Library.unit(p, v)).max }.toMutableMap()
        }
        return state
    }

    private fun work(ex: SessionExercise): Int = ex.plannedVolume * (if (ex.perSide) 2 else 1)

    /** The bound is the plan the POSITION holds, not the working sets on
     *  screen while the probe borrowed one of them. */
    @Test
    fun aDescentNeverAsksMoreThanThePlanThePositionHolds() {
        val state = toppedOutOnEveryVariation()
        val shown = Engine.recordShown(state = state, session = Engine.generateSession(state))
        val held = Engine.generateSession(shown).exercises.filter { it.probe != null }
            .associate { it.pattern to (it.plannedVolume + it.load) * (if (it.perSide) 2 else 1) }
        assertFalse(held.isEmpty(), "the seed must actually be probing")

        val descents = mutableListOf("silent decay" to Engine.applySilentDecay(state = shown, gapDays = 10))
        for (gap in listOf(14, 35, 56, 77, 119)) {
            descents += "comeback gap $gap" to Engine.applyComeback(state = shown, gapDays = gap)
        }
        for ((label, after) in descents) {
            for (ex in Engine.generateSession(after).exercises) {
                val before = held[ex.pattern] ?: continue
                assertTrue(work(ex) <= before,
                           "$label: ${ex.pattern} asks ${work(ex)} against the $before the position holds")
            }
        }
    }

    /** The comeback card's promise: the longer the break, the lower the plan
     *  meets you (84 days once met a person higher than 56). */
    @Test
    fun aComebackNeverRisesWithTheLengthOfTheBreak() {
        val shown = Engine.recordShown(state = toppedOutOnEveryVariation(),
                                       session = Engine.generateSession(toppedOutOnEveryVariation()))
        assertTrue(Engine.generateSession(shown).exercises.any { it.probe != null }, "the seed must actually be probing")
        for (p in Pattern.allCases) {
            var previous = Int.MAX_VALUE
            for (gap in listOf(14, 20, 28, 35, 42, 56, 70, 77, 84, 95, 110, 119)) {
                val after = Engine.applyComeback(state = shown, gapDays = gap)
                val ex = Engine.generateSession(after).exercises.firstOrNull { it.pattern == p } ?: continue
                assertTrue(work(ex) <= previous,
                           "${p.rawValue}: $gap days lands on ${work(ex)}, a shorter break on $previous")
                previous = work(ex)
            }
        }
    }

    /** The memory itself — the root the sweeps above stand on. */
    @Test
    fun aProbingAppearanceRecordsThePlanWithoutItsProbe() {
        val state = toppedOutOnEveryVariation()
        val session = Engine.generateSession(state)
        val probing = assertNotNull(session.exercises.firstOrNull { it.probe != null })
        val shown = Engine.recordShown(state = state, session = session)
        assertEquals((probing.plannedVolume + probing.load) * (if (probing.perSide) 2 else 1),
                     shown.shownWork[probing.pattern], "the borrowed set is counted back in, not written off")
        assertTrue(assertNotNull(shown.shownWork[probing.pattern]) > work(probing),
                   "which is strictly more than the working sets alone")
    }

    // MARK: - The snapshot carries the sparse coordinates into the chart

    @Test
    fun progressOverloadReadsSubAndCut() {
        assertEquals(Engine.progress(Pattern.squat, variation = 1, sets = 3, dose = 8) + 2,
                     Engine.progress(Pattern.squat, Position(variation = 1, sets = 3, dose = 8, sub = 2, cut = 0)))
        assertEquals(Engine.progress(Pattern.squat, variation = 1, sets = 3, dose = 8) - 1,
                     Engine.progress(Pattern.squat, Position(variation = 1, sets = 3, dose = 8, sub = 0, cut = 1)))
    }

    @Test
    fun recordedPositionKeepsTheSparseCoordinatesSparse() {
        val state = EngineState.initial
        state.doses[Pattern.squat] = 8
        state.sub[Pattern.squat] = 1
        val recorded = assertNotNull(positions(state)[Pattern.squat])
        assertEquals(1, recorded.sub)
        assertNull(recorded.cut, "a zero coordinate stays sparse, like the state")

        // A record written before the fields existed decodes without them —
        // and one written with nulls re-encodes to the same shape.
        val decoded = RecordedPosition.fromJson(Json.parseToJsonElement("""{"variation":3,"sets":3,"dose":11}"""))
        assertNull(decoded.sub)
        assertNull(decoded.cut)
        assertEquals(decoded, RecordedPosition.fromJson(Json.parseToJsonElement(decoded.toJson().toString())))
    }
}
