//
//  Port of ios/DredfitTests/HoldSummaryTests.swift: the summary a hold
//  movement ends on, walked on the engine's own plans — how far its
//  correctable card can go, and what it promises about next time. On iOS an
//  extension of WorkoutSessionTests; here a class on its harness.
//
//  Every test is ported.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.generateSession
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.workout.GetReady
import com.dredfit.workout.ProbeOutcome
import com.dredfit.workout.SetFacts
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.finishNow
import com.dredfit.workout.holdUnderWay
import com.dredfit.workout.isLastSummarySet
import com.dredfit.workout.leaveExerciseSummary
import com.dredfit.workout.nextPlan
import com.dredfit.workout.probeOutcome
import com.dredfit.workout.skipSet
import com.dredfit.workout.startDeclaringHoldTime
import com.dredfit.workout.startHold
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.stopHoldEarly
import com.dredfit.workout.summaryCardIsApproximate
import com.dredfit.workout.summaryMeasured
import com.dredfit.workout.summaryRange
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HoldSummaryTest : WorkoutSessionTestCase() {

    /** Knee plank on its ceiling and journalled there, in the store's own
     *  state: session 2 hands it out as 2×45 s and a probe of High plank,
     *  15 s. The store generated the session, so the summary's preview has
     *  an answer. */
    private fun probingPlankFlow(): Pair<WorkoutSession, AppStore> {
        val state = EngineState.initial
        state.counter = 1
        state.doses[Pattern.coreAntiExt] = Dose.hold.max
        state.shown[Pattern.coreAntiExt] = mutableMapOf(1 to Dose.hold.max)
        val store = makeStore()
        store.update { it.copy(engineState = state) }
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreAntiExt, flow)
        assertEquals(2, flow.exercise.sets, "the premise: two working sets")
        assertEquals(Library.name(Pattern.coreAntiExt, 2), flow.exercise.probe?.name, "the premise: a probe")
        signals.events.clear()
        return flow to store
    }

    /** "Start exercise", the first working set on its clock, the second one
     *  opened by its rest's go — run out, or stopped by hand at
     *  `secondStoppedAt` seconds on its clock — and the rest before the
     *  probe, up to the probe's own screen. */
    private fun walkToTheProbe(flow: WorkoutSession, secondStoppedAt: Int? = null) {
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + Dose.hold.max)
        run(flow) { flow.phase == Phase.Work }
        if (secondStoppedAt != null) {
            run(flow, secondStoppedAt)
            flow.stopHoldEarly()
        } else {
            run(flow, Dose.hold.max)
        }
        assertEquals(Phase.Rest(flow.exercise.restSetSec), flow.phase,
                     "a rest starts on the second working set's signal")
        run(flow) { flow.phase == Phase.Work }
        assertTrue(flow.onProbeSet)
    }

    /** The probe held on its own clock for `seconds`, and its Done. */
    private fun holdTheProbe(flow: WorkoutSession, seconds: Int) {
        flow.startHold()
        run(flow, GetReady.countInSeconds + seconds)
        assertTrue(flow.holdSettled)
        flow.completeSet()
    }

    // MARK: - How far the correctable card goes

    /** The last working set of the probing plank ran its 45 s and the rest
     *  before the probe started on its signal: it can be put down, and not
     *  above the 45 the clock ran. */
    @Test
    fun aSetARestFollowedCannotBeRaisedAboveItsClock() {
        val (flow, _) = probingPlankFlow()
        walkToTheProbe(flow)
        holdTheProbe(flow, 15)
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertTrue(flow.isLastSummarySet(1), "the last working set is still the card that opens")
        assertFalse(flow.isLastSummarySet(0))
        assertEquals(SetFacts.corridor(LoadUnit.hold).first..45, flow.summaryRange(set = 1),
                     "set 2's clock ran 45 s and a rest followed it")
        assertEquals(45..45, flow.summaryRange(set = 0), "an earlier set stands as it ran")
    }

    /** Stopped by hand at 44 s on its clock, the set recorded ≈41; the
     *  clock's own reading at the tap is the ceiling. */
    @Test
    fun aHandStoppedSetARestFollowedGoesUpToTheClocksReading() {
        val (flow, _) = probingPlankFlow()
        walkToTheProbe(flow, secondStoppedAt = 44)
        holdTheProbe(flow, 15)
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertEquals(listOf(45, 41), flow.actuals[Pattern.coreAntiExt])
        assertEquals(SetFacts.corridor(LoadUnit.hold).first..44, flow.summaryRange(set = 1),
                     "≈41 plus the reach allowance it paid")
    }

    /** Nothing followed the last set of a plain hold: both directions stay
     *  open. */
    @Test
    fun aPlainHoldsLastSetKeepsBothDirections() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        assertNull(flow.exercise.probe, "the premise: nothing after the last set")
        flow.startHoldExercise()
        run(flow) { flow.phase == Phase.ExerciseSummary }
        assertTrue(flow.isLastSummarySet(2))
        assertEquals(SetFacts.corridor(LoadUnit.hold), flow.summaryRange(set = 2))
    }

    /** …whoever ended it: a thumb on the last set closes nothing either. */
    @Test
    fun aPlainHoldsHandStoppedLastSetKeepsBothDirections() {
        val (flow, _) = holdFlow(Pattern.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertEquals(SetFacts.corridor(LoadUnit.hold), flow.summaryRange(set = 2))
    }

    // MARK: - A per-side set's ceiling

    /** The kneeling side plank on its ceiling and journalled there: session 2
     *  hands it out as 2×45 s per side and a probe of the next variation. */
    private fun probingSidePlankFlow(): Pair<WorkoutSession, AppStore> {
        val state = EngineState.initial
        state.counter = 1
        state.doses[Pattern.coreRot] = Dose.hold.max
        state.shown[Pattern.coreRot] = mutableMapOf(1 to Dose.hold.max)
        val store = makeStore()
        store.update { it.copy(engineState = state) }
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreRot, flow)
        assertTrue(flow.exercise.perSide, "the premise: per side")
        assertEquals(2, flow.exercise.sets, "the premise: two working sets")
        assertNotNull(flow.exercise.probe, "the premise: a probe")
        return flow to store
    }

    /** Set 1 on its clock, both sides, and the rest after it, up to set 2's
     *  first side, which the rest's go opens. */
    private fun walkToTheSecondSetsFirstSide(flow: WorkoutSession) {
        flow.startHoldExercise()
        run(flow) { flow.phase == Phase.Rest(flow.exercise.restSetSec) }
        run(flow) { flow.phase == Phase.Work }
        assertEquals(1, flow.setIndex)
        assertTrue(flow.holding && !flow.holdSecondSide, "set 2's first side runs")
    }

    /** From set 2's end — the rest before the probe — to the probe's screen,
     *  and the probe skipped onto the summary. */
    private fun skipTheProbeToTheSummary(flow: WorkoutSession) {
        assertEquals(Phase.Rest(flow.exercise.restSetSec), flow.phase)
        run(flow) { flow.phase == Phase.Work }
        assertTrue(flow.onProbeSet)
        flow.skipSet()
        assertEquals(Phase.ExerciseSummary, flow.phase)
    }

    /** Side 1 stopped by hand at 44 s (≈41), side 2 run out on its clock at
     *  the 41 it was handed: the set ended on a clock that ran 41, and the
     *  rest began on its signal. The ceiling is 41, whatever the mark says. */
    @Test
    fun aPerSideSetWhoseSecondSideRanOutGoesNoHigherThanThatClock() {
        val (flow, _) = probingSidePlankFlow()
        walkToTheSecondSetsFirstSide(flow)
        run(flow, 44)
        flow.stopHoldEarly()
        assertTrue(flow.holdSecondSide, "the first side handed over to the second")
        run(flow) { flow.phase != Phase.Work }
        assertEquals(41, flow.actuals[Pattern.coreRot]?.get(1))
        assertTrue(1 in flow.holdApproxSets, "the set carries the thumb's mark")
        skipTheProbeToTheSummary(flow)
        assertEquals(SetFacts.corridor(LoadUnit.hold).first..41, flow.summaryRange(set = 1),
                     "side 2's clock ran 41 and ended the set")
    }

    /** Side 1 on its clock, side 2 stopped by hand at 40 s (≈37): the thumb
     *  ended the set, and the ceiling is the estimate plus the allowance it
     *  paid, 40. A process death on the summary keeps it, and the movement
     *  takes the record of which side ended the set with it. */
    @Test
    fun aPerSideSetWhoseSecondSideAThumbEndedGoesUpToThatReading() {
        val (flow, store) = probingSidePlankFlow()
        walkToTheSecondSetsFirstSide(flow)
        run(flow) { flow.holdSecondSide && flow.holding }
        run(flow, 40)
        flow.stopHoldEarly()
        assertEquals(37, flow.actuals[Pattern.coreRot]?.get(1))
        skipTheProbeToTheSummary(flow)
        val ceiling = SetFacts.corridor(LoadUnit.hold).first..40
        assertEquals(ceiling, flow.summaryRange(set = 1))

        val back = makeFlow(store, resume = assertNotNull(store.pendingWorkout))
        assertEquals(Phase.ExerciseSummary, back.phase)
        assertEquals(ceiling, back.summaryRange(set = 1), "a process death keeps which side ended the set")
        back.leaveExerciseSummary()
        assertTrue(back.holdTapEndedSets.isEmpty(), "it goes with the movement")
        flow.finishNow()
        assertTrue(flow.holdTapEndedSets.isEmpty(), "…however the movement is left")
    }

    /** Off disk, a set a thumb ended is one the scale has, or it is dropped. */
    @Test
    fun theSetsAThumbEndedComeBackOffDiskBounded() {
        var snap = WorkoutSnapshot(sessionNumber = 3, exIndex = 0, setIndex = 0,
                                   restEndDate = null, restTotalSec = null,
                                   workoutStart = Instant.now(), savedAt = Instant.now())
        assertEquals(emptySet(), snap.endedByTapSets)
        snap = snap.copy(tapEndedSets = listOf(1, 9, -1))
        assertEquals(setOf(1), snap.endedByTapSets)
    }

    // MARK: - What is promised about next time

    /** The plan the engine hands `pattern` on its next appearance. */
    private fun nextAppearance(pattern: Pattern, store: AppStore): SessionExercise? {
        val state = store.engineState.copy()
        repeat(Pattern.entries.size) {
            Engine.generateSession(state).exercises.firstOrNull { it.pattern == pattern }?.let { return it }
            state.counter += 1
        }
        return null
    }

    /** The probe stopped by hand at 8 s of its 15: it records 5 and falls
     *  short, with the working sets behind it on plan. */
    private fun failTheProbe(flow: WorkoutSession) {
        flow.startHold()
        run(flow, GetReady.countInSeconds + 8)
        flow.stopHoldEarly()
        assertEquals(5, flow.probeActuals[Pattern.coreAntiExt], "the premise: the probe fell short")
    }

    /** The probe fell short after working sets that met the plan: the plank
     *  stays on its ceiling and its next appearance probes again — two
     *  working sets and the probe, which is what the summary must promise
     *  rather than three working sets. */
    @Test
    fun theNextPlanCarriesTheProbeTheEngineWillHandOut() {
        val (flow, store) = probingPlankFlow()
        walkToTheProbe(flow)
        failTheProbe(flow)
        flow.completeSet()
        assertEquals(Phase.ExerciseSummary, flow.phase)
        val promised = assertNotNull(flow.nextPlan(withAdditions = 0))

        flow.leaveExerciseSummary()
        flow.rate(FeedbackResult.plan)
        val next = assertNotNull(nextAppearance(Pattern.coreAntiExt, store))
        assertNotNull(next.probe, "the premise: the engine probes again")
        assertEquals(next.probe, promised.probe)
        assertEquals(next.display, promised.display)
    }

    /** "Set the time" 30 on the probing plank: both working sets ran 30 of
     *  the 45 asked and the probe met its target — and the plank steps down
     *  whatever the probe showed. The caption names the movement of the plan
     *  it steps down to, instead of saying the plan stays. */
    @Test
    fun aProbeAfterWorkingSetsThatFellShortNamesWhereThePlanGoes() {
        val (flow, _) = probingPlankFlow()
        flow.startDeclaringHoldTime()
        flow.adjustValue = 30
        flow.commitSetEdit()
        flow.startHoldExercise()
        run(flow, GetReady.countInSeconds + 30)
        run(flow) { flow.phase == Phase.Work }
        run(flow, 30)
        run(flow) { flow.phase == Phase.Work }
        assertTrue(flow.onProbeSet)
        flow.startHold()
        run(flow, GetReady.countInSeconds + 15)
        assertEquals(15, flow.probeActuals[Pattern.coreAntiExt], "the premise: the probe met its target")

        val next = assertNotNull(flow.nextPlan(withAdditions = 0))
        assertEquals(30, next.load, "the premise: the plan steps down to what was held")
        assertNull(next.probe)
        assertEquals(ProbeOutcome.PlanMoves(Library.name(Pattern.coreAntiExt, 1)), flow.probeOutcome)
    }

    /** The High plank on its ceiling, probing the plank above it, with "Set
     *  the time" 10 on its working sets — under the grid's floor of 15 s, so
     *  the plan drops back a variation whatever the probe shows. The caption
     *  names that lower movement, not the one just held. */
    @Test
    fun aProbeAfterWorkingSetsThatDropAVariationNamesTheLowerMovement() {
        val state = EngineState.initial
        state.counter = 1
        state.vars[Pattern.coreAntiExt] = 2
        state.doses[Pattern.coreAntiExt] = Dose.hold.max
        state.shown[Pattern.coreAntiExt] = mutableMapOf(2 to Dose.hold.max)
        val store = makeStore()
        store.update { it.copy(engineState = state) }
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = index(Pattern.coreAntiExt, flow)
        assertEquals(2, flow.exercise.variation, "the premise: the second variation")
        assertNotNull(flow.exercise.probe, "the premise: a probe")
        flow.startDeclaringHoldTime()
        flow.adjustValue = 10
        flow.commitSetEdit()
        flow.startHoldExercise()
        run(flow) { flow.onProbeSet && flow.phase == Phase.Work }
        flow.startHold()
        run(flow, GetReady.countInSeconds + Dose.hold.min)
        assertNotNull(flow.probeActuals[Pattern.coreAntiExt])

        val next = assertNotNull(flow.nextPlan(withAdditions = 0))
        assertEquals(1, next.variation, "the premise: the plan drops a variation")
        assertEquals(ProbeOutcome.PlanMoves(Library.name(Pattern.coreAntiExt, 1)), flow.probeOutcome)
    }

    /** Working sets that met the plan leave the outcome to the probe: met,
     *  it names the probe's own movement. */
    @Test
    fun aProbePassedAfterWorkingSetsThatMetThePlanNamesItsMovement() {
        val (flow, _) = probingPlankFlow()
        walkToTheProbe(flow)
        assertNull(flow.probeOutcome, "nothing to say before the probe has a number")
        flow.startHold()
        run(flow, GetReady.countInSeconds + 15)
        assertEquals(ProbeOutcome.Passed(Library.name(Pattern.coreAntiExt, 2)), flow.probeOutcome)
    }

    /** …short of its target, the plan stays as it is — and there it does. */
    @Test
    fun aProbeShortAfterWorkingSetsThatMetThePlanLeavesThePlan() {
        val (flow, _) = probingPlankFlow()
        walkToTheProbe(flow)
        failTheProbe(flow)
        assertEquals(ProbeOutcome.Stays, flow.probeOutcome)
    }

    // MARK: - A skipped probe

    /** Set 2 stopped by hand at 44 s on its clock (≈41), then the probe
     *  skipped. "The working sets lose nothing": their summary still comes,
     *  with the estimate on its card to put right, and its Done leads into
     *  the rest between movements, as after a probe done. */
    @Test
    fun skippingAHoldsProbeOpensTheMovementsSummary() {
        val (flow, _) = probingPlankFlow()
        walkToTheProbe(flow, secondStoppedAt = 44)
        flow.skipSet()
        assertEquals(Phase.ExerciseSummary, flow.phase,
                     "the plank's summary, with its ≈41 card, after the probe is skipped")
        assertEquals(Pattern.coreAntiExt, flow.exercise.pattern)
        assertTrue(flow.summaryCardIsApproximate(set = 1), "the estimate is still there to put right")
        assertEquals(41, flow.summaryMeasured(set = 1))
        assertNull(flow.probeActuals[Pattern.coreAntiExt])

        flow.leaveExerciseSummary()
        assertEquals(Phase.Rest(flow.exercise.restExerciseSec), flow.phase,
                     "the rest between movements, as after a probe done")
        assertNull(flow.probeActuals[Pattern.coreAntiExt], "a skipped probe records nothing on the way out")
    }

    /** The summary's Done is not the probe's: nothing records the skipped
     *  probe at its target, so the engine sees it unresolved — no pass, and
     *  the plank's next appearance probes again. */
    @Test
    fun aSkippedProbeReachesTheEngineUnresolved() {
        val (flow, store) = probingPlankFlow()
        walkToTheProbe(flow)
        flow.skipSet()
        flow.leaveExerciseSummary()
        flow.rate(FeedbackResult.plan)
        val record = assertNotNull(store.records.lastOrNull())
        assertNull(record.probes?.get(Pattern.coreAntiExt), "no number for a probe nobody did")
        assertEquals(1, store.engineState.position(Pattern.coreAntiExt).variation, "not promoted")
        val next = assertNotNull(nextAppearance(Pattern.coreAntiExt, store))
        assertEquals(2, next.probe?.variation, "the probe comes back")
    }

    /** A process death on that summary comes back to it — the estimate mark
     *  and the clock's number with it — and its Done still records no probe. */
    @Test
    fun theSummaryAfterASkippedProbeSurvivesAProcessDeath() {
        val (flow, store) = probingPlankFlow()
        walkToTheProbe(flow, secondStoppedAt = 44)
        flow.skipSet()
        val snap = assertNotNull(store.pendingWorkout)
        assertEquals(true, snap.atExerciseSummary)

        val back = makeFlow(store, resume = snap)
        assertEquals(Phase.ExerciseSummary, back.phase)
        assertEquals(Pattern.coreAntiExt, back.exercise.pattern)
        assertTrue(back.summaryCardIsApproximate(set = 1))
        assertEquals(41, back.summaryMeasured(set = 1))
        assertNull(back.probeActuals[Pattern.coreAntiExt])
        back.leaveExerciseSummary()
        assertNull(back.probeActuals[Pattern.coreAntiExt], "the restored summary's Done records no probe either")
        assertEquals(Phase.Rest(back.exercise.restExerciseSec), back.phase)
    }

    /** A per-side probe whose first side a thumb ended and whose second a
     *  stop inside the grace handed back, then skipped: the summary opens
     *  with no side left over, as after a probe done. */
    @Test
    fun aSkippedPerSideProbeLeavesNoSideBehind() {
        val (flow, _) = probingSidePlankFlow()
        flow.startHoldExercise()
        run(flow) { flow.onProbeSet && flow.phase == Phase.Work }
        assertEquals(true, assertNotNull(flow.exercise.probe).perSide, "the premise: a per-side probe")
        flow.startHold()
        run(flow, GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        run(flow) { flow.holdSecondSide && flow.holding }
        run(flow, 2)
        flow.stopHoldEarly()
        assertTrue(flow.holdSecondSide && !flow.holdUnderWay, "the premise: side 2 handed back")
        flow.skipSet()
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertFalse(flow.holdSecondSide)
        assertNull(flow.firstSideHeld)
    }

    /** A movement in reps has no summary to open: skipping its probe goes
     *  straight on to the next movement, as it always has. */
    @Test
    fun skippingARepsProbeGoesStraightOn() {
        val flow = makeFlow(makeStore(), probeSession())
        flow.declineWarmup()
        assertEquals(LoadUnit.reps, flow.exercise.unit, "the premise: a movement in reps")
        val pattern = flow.exercise.pattern
        flow.setIndex = flow.exercise.sets
        assertTrue(flow.onProbeSet)
        flow.skipSet()
        assertEquals(Phase.Work, flow.phase)
        assertNotEquals(pattern, flow.exercise.pattern)
        assertNull(flow.probeActuals[pattern])
    }
}
