//
//  Port of ios/DredfitTests/SessionAheadTests.swift: the number on the work
//  screen.
//
//  The plan announces how long the workout takes; the decision about its
//  length is taken inside the workout now, so the number has to follow the
//  decision rather than the plan. What is asserted here is that it is the SAME
//  number: the engine's own arithmetic over a shorter list, never an app-side
//  estimate that would drift from the line on Today by an amount nobody could
//  account for.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.generateSession
import com.dredfit.core.roundedAwayFromZero
import com.dredfit.workout.SessionAhead
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SessionAheadTest {

    /** A plan with every movement `variation` rungs up its ladder, at the dose
     *  ceiling — the long end of the scale, where "how much is left" matters. */
    private fun session(variation: Int): Session {
        val state = EngineState.initial
        for (pattern in Pattern.allCases) {
            val v = minOf(variation, Library.count(pattern))
            state.vars[pattern] = v
            state.doses[pattern] = Dose.grid(Library.unit(pattern, v)).max
            // A journal, so the ceiling does not turn into a probe on every
            // movement and change what "the sets left" even means here.
            state.lastHard.add(pattern)
        }
        return Engine.generateSession(state)
    }

    /** Standing at the first set of the first exercise, everything is ahead —
     *  so the number is the announced duration itself, minus the warm-up
     *  already behind. */
    @Test
    fun atTheStartWhatIsLeftIsTheWholeWorkout() {
        for (variation in listOf(1, 2, 3, 4)) {
            val plan = session(variation = variation)
            val ahead = SessionAhead.minutes(plan.exercises, exIndex = 0, setsBehind = 0,
                                             ends = plan.warmupMin + plan.cooldownMin)
            assertEquals(roundedAwayFromZero(plan.estimatedTotalMin).toInt(), ahead,
                         "variation $variation: the live number disagrees with the announced one")
        }
    }

    /** And it only ever goes down as the session is walked — set by set,
     *  exercise by exercise. */
    @Test
    fun itFallsWithEverySetBehind() {
        val plan = session(variation = 4)
        var previous = Int.MAX_VALUE
        for (exIndex in plan.exercises.indices) {
            for (behind in 0..plan.exercises[exIndex].sets) {
                val now = SessionAhead.minutes(plan.exercises, exIndex = exIndex, setsBehind = behind,
                                               ends = plan.cooldownMin)
                assertTrue(now <= previous, "exercise $exIndex, $behind behind: time went UP")
                previous = now
            }
        }
    }

    /** The sets left are the LAST ones of the plan. On an uneven plan — 9-8-8
     *  — the person who has done the 9 has two 8s ahead of them, and a list
     *  built from the first sets instead would over-count the work left. */
    @Test
    fun theSetsLeftAreTheOnesStillToCome() {
        val uneven = SessionExercise(pattern = Pattern.squat, name = "Squat", variation = 1, unit = LoadUnit.reps,
                                     load = 8, perSide = false, sets = 3,
                                     restSetSec = 60, restExerciseSec = 90, loads = listOf(9, 8, 8),
                                     probe = null)
        val ahead = assertNotNull(SessionAhead.remaining(listOf(uneven), exIndex = 0, setsBehind = 1).firstOrNull())
        assertEquals(2, ahead.sets)
        assertEquals(listOf(8, 8), listOf(ahead.plannedLoad(set = 0), ahead.plannedLoad(set = 1)),
                     "the sub-step was counted again after it was performed")
    }

    /** The sets left of the exercise under way are priced at what their clock
     *  will run: a declared time on a hold, and the plan on reps whatever is
     *  declared beside them — a declaration governs a hold only. */
    @Test
    fun theSetsLeftArePricedAtWhatTheirClockWillRun() {
        val hold = SessionExercise(pattern = Pattern.coreAntiExt, name = "Plank", variation = 1, unit = LoadUnit.hold,
                                   load = 30, perSide = false, sets = 3,
                                   restSetSec = 60, restExerciseSec = 90, loads = null, probe = null)
        val reps = SessionExercise(pattern = Pattern.squat, name = "Squat", variation = 1, unit = LoadUnit.reps,
                                   load = 8, perSide = false, sets = 3,
                                   restSetSec = 60, restExerciseSec = 90, loads = null, probe = null)
        val held = assertNotNull(SessionAhead.remaining(listOf(hold), exIndex = 0, setsBehind = 1,
                                                        facts = emptyMap(), declared = 45).firstOrNull())
        assertEquals(listOf(45, 45), listOf(held.plannedLoad(set = 0), held.plannedLoad(set = 1)),
                     "the clock runs the declared time, so the header prices it")
        val counted = assertNotNull(SessionAhead.remaining(listOf(reps), exIndex = 0, setsBehind = 1,
                                                           facts = emptyMap(), declared = 45).firstOrNull())
        assertEquals(listOf(8, 8), listOf(counted.plannedLoad(set = 0), counted.plannedLoad(set = 1)),
                     "a declaration governs a hold only")
    }

    /** A skipped set is a set behind: the minutes come off at the moment of
     *  the tap, which is the whole promise of a number that recalculates. */
    @Test
    fun aSkippedSetTakesItsMinutesOffImmediately() {
        val plan = session(variation = 4)
        val full = SessionAhead.minutes(plan.exercises, exIndex = 0, setsBehind = 0, ends = plan.cooldownMin)
        val afterSkip = SessionAhead.minutes(plan.exercises, exIndex = 0, setsBehind = 1, ends = plan.cooldownMin)
        assertTrue(afterSkip < full, "a skipped set bought no time at all")
    }

    /** Past the last exercise there is nothing left but the blocks that are
     *  still to come — and past those, nothing. */
    @Test
    fun pastTheEndOnlyTheBlocksAreLeft() {
        val plan = session(variation = 3)
        val past = plan.exercises.size
        assertTrue(SessionAhead.remaining(plan.exercises, exIndex = past, setsBehind = 0).isEmpty())
        assertEquals(plan.cooldownMin,
                     SessionAhead.minutes(plan.exercises, exIndex = past, setsBehind = 0, ends = plan.cooldownMin))
        assertEquals(0, SessionAhead.minutes(plan.exercises, exIndex = past, setsBehind = 0, ends = 0))
    }

    /** Indices off the end of the list, a negative count of sets behind, a
     *  negative block: this is read on every body pass of a live screen, so it
     *  answers rather than traps. */
    @Test
    fun itSurvivesNonsense() {
        val plan = session(variation = 3)
        assertTrue(SessionAhead.remaining(plan.exercises, exIndex = -1, setsBehind = 0).isEmpty())
        assertTrue(SessionAhead.remaining(emptyList(), exIndex = 0, setsBehind = 0).isEmpty())
        assertEquals(plan.exercises[0].sets,
                     SessionAhead.remaining(plan.exercises, exIndex = 0, setsBehind = -5).firstOrNull()?.sets,
                     "a negative count of sets behind added work")
        assertTrue(SessionAhead.minutes(plan.exercises, exIndex = 0, setsBehind = 99, ends = -10) >= 0)
    }
}
