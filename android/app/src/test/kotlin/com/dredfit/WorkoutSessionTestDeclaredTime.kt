//
//  Port of ios/DredfitTests/WorkoutSessionTests+DeclaredTime.swift: the time
//  a hold is declared to run, and the number the work screen names —
//  whatever it shows is what the clock then counts.
//
//  Every test is ported.
//

package com.dredfit

import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.workout.Cooldown
import com.dredfit.workout.GetReady
import com.dredfit.workout.SetFacts
import com.dredfit.workout.WorkoutSession.EditTarget
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.holdEndedByTap
import com.dredfit.workout.skipSet
import com.dredfit.workout.startAdjusting
import com.dredfit.workout.startDeclaringHoldTime
import com.dredfit.workout.startHold
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.stopHoldEarly
import com.dredfit.workout.workNumber
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSessionTestDeclaredTime : WorkoutSessionTestCase() {

    // MARK: - The declared time

    @Test
    fun theDeclaredTimeSetsTheClockAndRecordsNothing() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startDeclaringHoldTime()
        assertEquals(EditTarget.HoldTime, flow.editing)
        flow.adjustValue = 45
        flow.commitSetEdit()
        assertEquals(45, flow.holdDeclared)
        assertNull(flow.actuals[Pattern.coreAntiExt], "a target, not a record")
        flow.startHold()
        assertEquals(45, flow.holdTotal)
    }

    @Test
    fun startingTheExerciseClosesTheDeclarationUnsaid() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startDeclaringHoldTime()
        flow.adjustValue = 45
        flow.startHoldExercise()
        assertNull(flow.editing)
        assertNull(flow.holdDeclared)
        assertEquals(15, flow.holdTotal)
    }

    // MARK: - The number the screen names, and the clock then counts

    /** The rest ran out with nobody there, so the run stopped and set 2 waits
     *  on its own button — showing the number its clock will count. */
    @Test
    fun aSetTheRunNoLongerOpensShowsTheDeclaredTimeItWillRun() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        declare(45, flow)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 45)
        advance(600)
        flow.tick()
        assertFalse(flow.holdAutoRun)
        assertEquals(1, flow.setIndex)

        assertEquals(45, flow.workNumber, "the screen names the declared time, not the plan of 15")
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds)
        assertEquals(45, flow.holdClock.remaining, "and the clock counts what the screen named")
    }

    @Test
    fun aStopInsideTheGraceHandsBackTheDeclaredTimeTheClockWillRun() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        declare(45, flow)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 45 + 60)
        assertEquals(1, flow.setIndex)
        assertTrue(flow.holding, "the run opened set 2 on its rest's go")
        run(flow, 2)
        flow.stopHoldEarly()
        assertFalse(flow.holding)

        assertEquals(45, flow.workNumber, "the set handed back names the declared time, not the plan of 15")
        flow.startHold()
        run(flow, GetReady.countInSeconds)
        assertEquals(45, flow.holdClock.remaining, "and the clock counts what the screen named")
    }

    /** Below the plan, and with nothing recorded yet: the declaration alone
     *  is what the set after a skipped one runs at. */
    @Test
    fun aSetAfterASkipShowsTheDeclaredTimeItWillRun() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        declare(10, flow)
        flow.skipSet()
        assertEquals(1, flow.setIndex)

        assertEquals(10, flow.workNumber, "the screen names the declared time, not the plan of 15")
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds)
        assertEquals(10, flow.holdClock.remaining, "and the clock counts what the screen named")
    }

    /** Nothing on a reps movement can declare a time, so one found there came
     *  off a snapshot, and the set goes on naming the reps it asks for. */
    @Test
    fun aRepsMovementNamesItsOwnNumberWhateverIsDeclared() {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        assertEquals(LoadUnit.reps, flow.exercise.unit)
        flow.holdDeclared = 45
        assertEquals(flow.exercise.plannedLoad(set = 0), flow.workNumber)
    }

    /** The probe is one set of another movement: it names the probe's own
     *  target, then the number entered for it — never the working sets'. */
    @Test
    fun theProbeSetNamesTheProbesOwnNumber() {
        val flow = makeFlow(makeStore(), probeSession())
        flow.declineWarmup()
        flow.setIndex = flow.exercise.sets
        val probe = assertNotNull(flow.exercise.probe)
        assertNotEquals(flow.exercise.plannedLoad(set = flow.setIndex), probe.load,
                        "the probe and the working sets must ask for different numbers to be told apart")
        assertEquals(probe.load, flow.workNumber)

        flow.startAdjusting()
        flow.adjustValue = probe.load + 1
        flow.commitSetEdit()
        assertEquals(probe.load + 1, flow.workNumber, "the number entered for the probe is the one it names")
    }

    /** While a clock is on the person the big number is that clock: the
     *  count-in, the hold itself and the pause between the sides each show
     *  the seconds they have left, never the set's 15. */
    @Test
    fun whileAClockRunsTheScreenNamesItsSecondsLeft() {
        val (flow, _) = holdFlow(Pattern.coreRot)
        flow.startHoldExercise()
        run(flow, 1)
        assertTrue(flow.holdCountingIn)
        assertEquals(GetReady.countInSeconds - 1, flow.workNumber)

        run(flow, GetReady.countInSeconds - 1 + 3)
        assertTrue(flow.holding)
        assertEquals(15 - 3, flow.workNumber)

        run(flow) { flow.holdSwitchPausing }
        assertEquals(Cooldown.switchPauseSeconds, flow.workNumber)
    }

    /** The panel reopens on the time already declared — what the clock would
     *  run now — not on the plan. */
    @Test
    fun theDeclarationReopensOnTheTimeTheClockWouldRun() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        declare(45, flow)
        flow.startDeclaringHoldTime()
        assertEquals(45, flow.adjustValue)
    }

    /**
     * A Stop inside the grace on the SECOND side hands that side back, and it
     * still runs for what the first side ran — so that is the number it
     * names, not the set's own: the plan's 15, or a declared 45. Under a
     * declaration a first side past the plan counts in full.
     */
    @Test
    fun aSecondSideHandedBackNamesWhatTheFirstSideRan() {
        // The time declared before the run, and the seconds the first side
        // ran before the Stop that cut it short.
        val cases: List<Pair<Int?, Int>> = listOf(null to 10, 45 to 13, 45 to 33)
        for ((declared, held) in cases) {
            val (flow, _) = holdFlow(Pattern.coreRot)
            if (declared != null) declare(declared, flow)
            flow.startHoldExercise()
            run(flow, GetReady.countInSeconds + held)
            flow.stopHoldEarly()
            val firstSide = SetFacts.holdEndedByTap(heldSeconds = held)
            assertEquals(firstSide, flow.firstSideHeld)
            run(flow, Cooldown.switchPauseSeconds + 2)
            flow.stopHoldEarly()
            assertTrue(flow.holdSecondSide, "the side is handed back, not the set")
            assertFalse(flow.holding)

            assertEquals(firstSide, flow.workNumber,
                         "declared $declared: the side names what the first side ran")
            flow.startHold()
            run(flow, GetReady.countInSeconds)
            assertEquals(firstSide, flow.holdClock.remaining, "and the clock counts what the screen named")
        }
    }
}
