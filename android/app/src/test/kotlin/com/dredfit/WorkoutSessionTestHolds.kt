//
//  Port of ios/DredfitTests/WorkoutSessionTests+Holds.swift: the count-in,
//  the clock, Stop, the side switch and the summary a hold movement ends on.
//  The hands-free run and the declared time have files of their own
//  (WorkoutSessionTestHoldRun, WorkoutSessionTestDeclaredTime). `holdFlow`
//  and `declare` live in WorkoutSessionTestCase, as every hold suite shares
//  them.
//
//  Every test is ported.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.generateSession
import com.dredfit.workout.Cooldown
import com.dredfit.workout.GetReady
import com.dredfit.workout.SetFacts
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.EditTarget
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.commitSummaryEdit
import com.dredfit.workout.finishNow
import com.dredfit.workout.holdEndedByTap
import com.dredfit.workout.holdStopRecords
import com.dredfit.workout.leaveExerciseSummary
import com.dredfit.workout.skipRest
import com.dredfit.workout.skipSet
import com.dredfit.workout.skipsLeaveAMovement
import com.dredfit.workout.startHold
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.startSummaryAdjusting
import com.dredfit.workout.stopHoldEarly
import com.dredfit.workout.summaryCardIsApproximate
import com.dredfit.workout.summaryPanelLine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSessionTestHolds : WorkoutSessionTestCase() {

    @Test
    fun aHoldCountsInThenRunsAndRecordsWhatTheClockRan() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        declare(20, flow)
        flow.startHold()
        assertTrue(flow.holdCountingIn)
        assertEquals(GetReady.countInSeconds, flow.holdCountInClock.remaining)
        assertFalse(flow.holding)

        run(flow, GetReady.countInSeconds)
        assertTrue(flow.holding)
        assertEquals(20, flow.holdClock.remaining)

        run(flow, 20)
        assertEquals(listOf(20), flow.actuals[Pattern.coreAntiExt])
        assertEquals(20, flow.holdMeasured[0])
        assertEquals(Phase.Rest(60), flow.phase)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go, Event.Tick, Event.Tick, Event.Tick, Event.Done),
                     signals.tones)
    }

    @Test
    fun aHoldThatRanOutWhileAwayIsCreditedInFull() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        declare(20, flow)
        flow.startHold()
        run(flow, GetReady.countInSeconds)
        advance(3_600)
        flow.tick()
        assertEquals(listOf(20), flow.actuals[Pattern.coreAntiExt],
                     "a hold that ran to the end of its clock counts as held, whatever came after")
    }

    @Test
    fun aCountInThatEndedOutOfEarshotStartsOver() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        advance(30)
        flow.tick()
        assertTrue(flow.holdCountingIn, "a go nobody could hear must not start a plank")
        assertEquals(GetReady.countInSeconds, flow.holdCountInClock.remaining)
        assertFalse(flow.holding)
    }

    @Test
    fun aCountInThatStartsOverIsPrimedAgain() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        advance(30)
        signals.primes = 0
        flow.tick()
        assertTrue(flow.holdCountingIn, "the premise")
        assertEquals(1, signals.primes, "the absence that ended the first count-in let the engine go cold")
        run(flow, GetReady.countInSeconds)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(1, signals.primes, "one prime per 3-2-1")
    }

    @Test
    fun aStopInsideTheMisTapGraceHandsTheSetBack() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        run(flow, GetReady.countInSeconds + 2)
        flow.stopHoldEarly()
        assertFalse(flow.holding)
        assertEquals(15, flow.holdClock.remaining, "the set stands at its full length again")
        assertNull(flow.actuals[Pattern.coreAntiExt])
        assertEquals(Phase.Work, flow.phase)
        assertEquals(0, flow.setIndex)
    }

    @Test
    fun aStopPastTheGraceIsRecordedAsAnEstimate() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        run(flow, GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        val expected = SetFacts.snap(SetFacts.holdEndedByTap(heldSeconds = 10).toDouble(), LoadUnit.hold)
        assertEquals(listOf(expected), flow.actuals[Pattern.coreAntiExt])
        assertTrue(0 in flow.holdApproxSets, "a number the app guessed at says so")
        assertEquals(Phase.Rest(60), flow.phase)
    }

    @Test
    fun theSecondSideRunsForWhatTheFirstSideRan() {
        val (flow, _) = holdFlow(Pattern.coreRot)
        flow.startHold()
        run(flow, GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        val firstSide = SetFacts.holdEndedByTap(heldSeconds = 10)
        assertTrue(flow.holdSwitchPausing)
        assertEquals(firstSide, flow.firstSideHeld)
        assertEquals(Event.SwitchSides, signals.tones.last())

        run(flow, Cooldown.switchPauseSeconds)
        assertTrue(flow.holding)
        assertEquals(SetFacts.holdSideSeconds(planned = 15, firstSideHeld = firstSide), flow.holdTotal)

        val secondSide = flow.holdTotal
        run(flow) { !flow.holding }
        assertEquals(listOf(SetFacts.snap(minOf(secondSide, firstSide).toDouble(), LoadUnit.hold)),
                     flow.actuals[Pattern.coreRot],
                     "one set of a per-side hold is the smaller of its two sides")
        assertFalse(flow.holdSecondSide)
        assertEquals(Phase.Rest(60), flow.phase)
    }

    @Test
    fun theLastHoldOfAMovementEndsOnItsSummary() {
        val (flow, store) = holdFlow(Pattern.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, GetReady.countInSeconds + 15)
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertEquals(true, store.pendingWorkout?.atExerciseSummary)
        assertEquals(Event.Done, signals.tones.last(), "the end sounds where the effort stopped")

        signals.events.clear()
        flow.leaveExerciseSummary()
        assertEquals(Phase.Rest(flow.exercise.restExerciseSec), flow.phase)
        assertTrue(flow.holdMeasured.isEmpty())
        assertEquals(emptyList(), signals.tones, "the summary's Done confirms numbers; the end already sounded")
    }

    /**
     * On the plank the engine itself hands out with a probe, neither working
     * set can be skipped on its own: the skip would leave fewer sets than
     * the shared floor, so the work screen offers "Skip exercise" instead and
     * the tap takes the whole movement. The probe's Done opens the movement's
     * summary, whose last card is the one a person may correct, under a line
     * saying what the clock saw — a lone skip of the last working set would
     * put a set no clock ran on that card.
     *
     * The engine's own floor for this exercise is one, the probe holding the
     * slot's other set. The skip rule reads the shared floor of two; read
     * from the exercise, it would offer exactly that skip.
     */
    @Test
    fun theEnginesProbingPlankOffersNoSkipOfALastWorkingSet() {
        // Session 2 carries the plank. On its ceiling, journalled there and
        // below the top of its ladder, it is offered a probe.
        val state = EngineState.initial
        state.counter = 1
        state.doses[Pattern.coreAntiExt] = Dose.hold.max
        state.shown[Pattern.coreAntiExt] = mutableMapOf(1 to Dose.hold.max)
        val (flow, _) = holdFlow(Pattern.coreAntiExt, Engine.generateSession(state))
        assertEquals(2, flow.exercise.sets)
        assertEquals(3, flow.totalSets)
        assertEquals(1, flow.exercise.setsFloor, "the engine's floor, which the skip rule must not read")

        assertFalse(flow.skipsLeaveAMovement(1), "set one: \"Skip this set\" is not offered")
        flow.startHold()
        run(flow, GetReady.countInSeconds + Dose.hold.max)
        flow.skipRest()
        assertEquals(1, flow.setIndex)
        assertFalse(flow.skipsLeaveAMovement(1), "set two: \"Skip this set\" is not offered")
        flow.skipSet()
        assertTrue(Pattern.coreAntiExt in flow.skippedPatterns, "the tap takes the whole movement")
        assertNotEquals(Pattern.coreAntiExt, flow.exercise.pattern,
                        "the flow is past the movement: its probe, and the summary the probe opens, never come")
    }

    @Test
    fun finishNowOnTheSummaryCountsEverySetOfTheMovementDone() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, GetReady.countInSeconds + 15)
        assertEquals(Phase.ExerciseSummary, flow.phase)
        flow.finishNow()
        assertNull(flow.setsSkipped[Pattern.coreAntiExt],
                   "every set is behind and on the screen — none of them was skipped")
        assertFalse(Pattern.coreAntiExt in flow.skippedPatterns)
        assertNull(flow.interruptedPattern)
    }

    /**
     * A set a thumb ended at 33 s on the clock records 30, the clock less the
     * reach allowance, and the line above its panel names that number as the
     * estimate it is. A correction does not change who ended the set, so the
     * line says the same after one — "the clock saw 30 s" would pass the
     * estimate off as a measurement. The card's "≈" stands while the card
     * carries the thumb's number: OK on it keeps the mark, a number of the
     * person's own takes it off.
     */
    @Test
    fun aCorrectedSetStoppedByHandIsNotPassedOffAsTheClocksCount() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        declare(45, flow)
        flow.setIndex = 2
        flow.startHold()
        run(flow, GetReady.countInSeconds + 33)
        flow.stopHoldEarly()
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertEquals(listOf(15, 15, 30), flow.actuals[Pattern.coreAntiExt], "33 s on the clock less the 3 s reach")
        val estimate = "set 3 · stopped by hand at about 30 s"

        flow.startSummaryAdjusting(set = 2)
        assertEquals(estimate, flow.summaryPanelLine(set = 2).english)
        assertTrue(flow.summaryCardIsApproximate(set = 2))

        flow.commitSummaryEdit(set = 2)   // OK on the number as it stands
        assertTrue(flow.summaryCardIsApproximate(set = 2), "the card still carries the thumb's number")
        flow.startSummaryAdjusting(set = 2)
        assertEquals(estimate, flow.summaryPanelLine(set = 2).english)

        flow.adjustValue = 35   // one "+" on the panel's five-second grid
        flow.commitSummaryEdit(set = 2)
        assertEquals(listOf(15, 15, 35), flow.actuals[Pattern.coreAntiExt])
        assertFalse(flow.summaryCardIsApproximate(set = 2), "the card carries the person's number now")
        flow.startSummaryAdjusting(set = 2)
        assertEquals(estimate, flow.summaryPanelLine(set = 2).english, "the clock saw neither 30 nor 35")
    }

    /**
     * A per-side set whose first side a thumb ended is marked as an estimate
     * before it has recorded anything. A second side stopped inside the
     * mis-tap grace hands the set back with "Skip this set" live, and a set
     * skipped from there records nothing — its card on the summary shows the
     * number it falls back to, and must not print "≈ · stopped by hand" over
     * it. A set that did record an estimate keeps its mark through the skip.
     */
    @Test
    fun aSkippedSetLeavesNoEstimateOnTheSummary() {
        val (flow, _) = holdFlow(Pattern.coreRot)
        // Set one: a thumb ends the first side, the clock the second.
        flow.startHold()
        run(flow, GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        run(flow) { flow.phase != Phase.Work }
        flow.skipRest()

        // Set two: a thumb ends the first side, the second is handed back.
        flow.startHold()
        run(flow, GetReady.countInSeconds + 5)
        flow.stopHoldEarly()
        run(flow, Cooldown.switchPauseSeconds + 2)
        flow.stopHoldEarly()
        assertTrue(flow.holdSecondSide, "the grace handed the second side back")
        flow.skipSet()

        // Set three runs on the clock to the summary.
        flow.startHold()
        run(flow) { flow.phase == Phase.ExerciseSummary }
        assertTrue(flow.summaryCardIsApproximate(set = 0), "set one recorded an estimate")
        assertFalse(flow.summaryCardIsApproximate(set = 1), "set two recorded nothing")
    }

    @Test
    fun theSummaryCorrectsOnlyTheCardThatWasTapped() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.setIndex = 2
        flow.actuals = flow.actuals + (Pattern.coreAntiExt to listOf(15, 15))
        flow.startHold()
        run(flow, GetReady.countInSeconds + 15)
        flow.startSummaryAdjusting(set = 0)
        assertNull(flow.editing, "only the last card opens the panel")
        flow.startSummaryAdjusting(set = 2)
        assertEquals(EditTarget.SummaryCard(2), flow.editing)
        flow.adjustValue = 20
        flow.commitSummaryEdit(set = 2)
        assertEquals(listOf(15, 15, 20), flow.actuals[Pattern.coreAntiExt])
        assertNull(flow.editing)
    }

    // MARK: - What a Stop records

    /**
     * `ticks` seconds of the running hold pass the way the view's timer runs
     * them, then `plus` more with no tick — where a thumb lands — and Stop is
     * tapped. Returns the figure the last tick put on the button, read before
     * the gap: the button is drawn on the tick, and a figure read at the tap
     * would agree with a record taken off the live clock by moving with it.
     */
    private fun tapStop(flow: WorkoutSession, afterTicks: Int, plus: Double): Int? {
        run(flow, afterTicks)
        val named = flow.holdStopRecords
        advance(plus)
        flow.stopHoldEarly()
        return named
    }

    /**
     * The figure on the button moves only on a tick, and the clock does not
     * wait for one: seven tenths past the tick it is nearer the next second
     * than the one the button names, and a tick that comes late leaves the
     * button more than a second behind it.
     */
    @Test
    fun aStopBetweenTwoTicksStoresTheFigureTheButtonNamed() {
        for (gap in listOf(0.7, 1.2)) {
            val (flow, _) = holdFlow(Pattern.coreAntiExt)
            flow.startHold()
            run(flow, GetReady.countInSeconds)
            val named = assertNotNull(tapStop(flow, afterTicks = 10, plus = gap))
            assertEquals(named, flow.holdMeasured[0], "$gap s past the tick")
        }
    }

    /**
     * On the tick itself: on the whole second, and on a tick the timer
     * delivered late, as it does when the main thread is busy — that one
     * puts the clock's ROUNDED second on the button, a second more than a
     * truncated clock would store.
     */
    @Test
    fun aStopOnATickStoresTheFigureThatTickPutOnTheButton() {
        for (late in listOf(0.0, 0.6)) {
            val (flow, _) = holdFlow(Pattern.coreAntiExt)
            flow.startHold()
            run(flow, GetReady.countInSeconds + 10)
            advance(late)
            flow.tick()
            val named = assertNotNull(tapStop(flow, afterTicks = 0, plus = 0.0))
            assertEquals(named, flow.holdMeasured[0], "a tick $late s late")
        }
    }

    /** A plain "Stop" is the grace, even with the clock already past its
     *  three seconds: the tap does what the button says, and it names nothing. */
    @Test
    fun aStopWhileTheButtonNamesNoFigureStoresNothing() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHold()
        run(flow, GetReady.countInSeconds)
        assertNull(tapStop(flow, afterTicks = 3, plus = 0.5), "the button names no figure")
        assertEquals(15, flow.holdClock.remaining, "the set stands at its full length again")
        assertNull(flow.actuals[Pattern.coreAntiExt])
        assertTrue(flow.holdApproxSets.isEmpty())
        assertEquals(Phase.Work, flow.phase)
    }

    /**
     * The first side's figure is what the second side runs for, and the
     * second side's is what the set stores. Declared at 30 s so both figures
     * stand clear of the five-second floor, where a second more or less
     * would not show.
     */
    @Test
    fun eachSideOfAPerSideHoldStoresTheFigureItsButtonNamed() {
        val (flow, _) = holdFlow(Pattern.coreRot)
        declare(30, flow)
        flow.startHold()
        run(flow, GetReady.countInSeconds)
        val firstSide = assertNotNull(tapStop(flow, afterTicks = 20, plus = 0.7))
        assertEquals(firstSide, flow.firstSideHeld)

        run(flow, Cooldown.switchPauseSeconds)
        assertTrue(flow.holding, "the second side runs")
        val secondSide = assertNotNull(tapStop(flow, afterTicks = 12, plus = 0.7))
        assertEquals(secondSide, flow.holdMeasured[0])
    }

    /** A set the hands-free run opened on the rest's own go stops like any
     *  other. */
    @Test
    fun aStopInASetTheRunOpenedStoresTheFigureTheButtonNamed() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 15 + 60)
        assertEquals(1, flow.setIndex)
        assertTrue(flow.holding, "the rest's go opened the set")
        val named = assertNotNull(tapStop(flow, afterTicks = 10, plus = 0.7))
        assertEquals(named, flow.holdMeasured[1])
    }
}
