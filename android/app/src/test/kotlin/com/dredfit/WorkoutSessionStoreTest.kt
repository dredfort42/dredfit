//
//  Port of ios/DredfitTests/WorkoutSessionStoreTests.swift: the snapshot's
//  policy on its own — which snapshot still describes the plan ahead, and
//  what a forgotten workout is recorded as.
//
//  Every Swift test is ported.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.core.generateSession
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.workout.WorkoutSessionStore
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSessionStoreTest {

    private val plan = Engine.generateSession(EngineState.initial)
    private val start = Instant.ofEpochSecond(1_900_000_000)

    private fun snapshot(exIndex: Int = 0, setIndex: Int = 1,
                         setActuals: Map<Pattern, List<Int>>? = null, skipped: Set<Pattern> = emptySet(),
                         fingerprint: String? = null, awaySec: Int? = null,
                         raisedSteps: Map<Pattern, Int>? = null): WorkoutSnapshot =
        WorkoutSnapshot(sessionNumber = 1, exIndex = exIndex, setIndex = setIndex,
                        setActuals = setActuals, skipped = skipped,
                        workoutStart = start, savedAt = start.plusSeconds(3_600),
                        fingerprint = fingerprint ?: WorkoutSnapshot.fingerprint(plan),
                        awaySec = awaySec, raisedSteps = raisedSteps)

    @Test
    fun onlyASnapshotOfThePlanAheadWithSomethingDoneIsValid() {
        assertNotNull(WorkoutSessionStore.valid(snapshot(), plan, counter = 0))
        assertNull(WorkoutSessionStore.valid(snapshot(), plan, counter = 1), "another session number")
        assertNull(WorkoutSessionStore.valid(snapshot(fingerprint = "another plan"), plan, counter = 0),
                   "a plan regenerated under the same number")
        assertNull(WorkoutSessionStore.valid(snapshot(setIndex = 0), plan, counter = 0), "nothing done yet")
        assertNull(WorkoutSessionStore.valid(null, plan, counter = 0))
    }

    @Test
    fun aSettlementIsDatedWhereTheWorkoutEndedLessTheTimeAway() {
        val settled = WorkoutSessionStore.settlement(snapshot(awaySec = 600), plan)
        assertEquals(start.plusSeconds(3_600), settled.date)
        assertEquals(3_000, settled.durationSec)
    }

    @Test
    fun aSkipWinsOverAnActualAndTakesItsRaiseWithIt() {
        val first = plan.exercises[0].pattern
        val second = plan.exercises[1].pattern
        val settled = WorkoutSessionStore.settlement(
            snapshot(exIndex = 2, setIndex = 0,
                     setActuals = mapOf(first to listOf(6, 6, 6), second to listOf(5)),
                     skipped = setOf(second),
                     raisedSteps = mapOf(first to 1, second to 2)),
            plan)
        assertEquals(listOf(6, 6, 6), settled.setActuals[first])
        assertNull(settled.setActuals[second])
        assertEquals(mapOf(first to 1), settled.raised)
        assertTrue(second in settled.skipped)
        assertEquals(plan.exercises.drop(1).map { it.pattern }.toSet(), settled.skipped,
                     "the movement skipped by hand, and everything from where it stopped on")
    }

    @Test
    fun aSetIndexOffDiskCannotTrapTheSettlement() {
        val snap = snapshot(setIndex = Int.MAX_VALUE, setActuals = mapOf(plan.exercises[0].pattern to listOf(6, 6, 6)))
            .copy(restEndDate = start.plusSeconds(3_600))
        val settled = WorkoutSessionStore.settlement(snap, plan)
        assertFalse(plan.exercises[0].pattern in settled.skipped,
                    "in its rest, every set of the movement is behind")
    }
}
