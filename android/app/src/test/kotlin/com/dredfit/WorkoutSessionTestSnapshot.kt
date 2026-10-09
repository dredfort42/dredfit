//
//  Port of ios/DredfitTests/WorkoutSessionTests+Snapshot.swift: what survives
//  a backgrounded phone and a process death, and the two guided blocks with
//  their pause.
//
//  Every Swift test is ported. Dropped inside one helper: the second half of
//  `assertNoCoolDownBilled` prices the record through
//  `EnergyEstimate.segments` (the Health export), which arrives with health/
//  in phase 3; the record's own `cooldownSec == 0` is asserted as on iOS.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.settleAbandonedWorkout
import com.dredfit.workout.BlockPause
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.WorkoutSessionStore
import com.dredfit.workout.beginCooldown
import com.dredfit.workout.beginWarmup
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineCooldown
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.finishNow
import com.dredfit.workout.freezeForPositionTechnique
import com.dredfit.workout.leaveExercise
import com.dredfit.workout.leaveExerciseSummary
import com.dredfit.workout.resumePositionCountdown
import com.dredfit.workout.sceneCameBack
import com.dredfit.workout.sceneLeft
import com.dredfit.workout.skipRest
import com.dredfit.workout.startHold
import com.dredfit.workout.toggleBlockPause
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSessionTestSnapshot : WorkoutSessionTestCase() {

    // MARK: - Restoring after a process death

    @Test
    fun aRestorePicksUpInsideARestStillRunning() {
        val store = makeStore()
        val first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        val snapshot = assertNotNull(store.pendingWorkout)

        advance(10)
        val flow = makeFlow(store, resume = snapshot)
        assertEquals(Phase.Rest(60), flow.phase)
        assertEquals(50, flow.restClock.remaining)
        assertEquals(0, flow.awaySec, "a rest running on schedule is training, not absence")
    }

    @Test
    fun aRestRestoredInItsLastHalfSecondStillEnds() {
        val store = makeStore()
        val first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        val snapshot = assertNotNull(store.pendingWorkout)

        advance(59.7)
        val flow = makeFlow(store, resume = snapshot)
        assertEquals(Phase.Rest(60), flow.phase)
        assertEquals(0, flow.restClock.remaining)
        run(flow, 1)
        assertEquals(Phase.Work, flow.phase, "the rest ends instead of hanging on 0")
        assertEquals(1, flow.setIndex)
    }

    @Test
    fun aRestoreAfterTheRestRanOutLandsOnTheNextSetAndCountsTheAbsence() {
        val store = makeStore()
        val first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        val snapshot = assertNotNull(store.pendingWorkout)

        advance(60 + 300)
        val flow = makeFlow(store, resume = snapshot)
        assertEquals(Phase.Work, flow.phase)
        assertEquals(1, flow.setIndex, "the advance the timer would have made")
        assertEquals(300, flow.awaySec, "measured from the end of the rest, not from the last write")
    }

    @Test
    fun aRestorePastTheLastSetsRestOpensTheNextMovementWithoutItsDeclaration() {
        val store = makeStore()
        val first = makeFlow(store, holdSession())
        first.declineWarmup()
        val index = index(Pattern.coreAntiExt, first)
        assertTrue(index < first.exercises.size - 1, "a movement must follow it")
        first.exIndex = index
        first.holdDeclared = 45
        first.setIndex = 2
        first.completeSet()
        assertEquals(Phase.ExerciseSummary, first.phase)
        first.leaveExerciseSummary()
        val snapshot = assertNotNull(store.pendingWorkout)
        assertEquals(45, snapshot.holdDeclaredSec)

        advance(600)
        val flow = makeFlow(store, holdSession(), resume = snapshot)
        assertEquals(index + 1, flow.exIndex)
        assertEquals(0, flow.setIndex)
        assertNull(flow.holdDeclared, "the declaration belongs to the movement behind")
    }

    @Test
    fun aRestoreFromTheCoolDownLandsOnTheRating() {
        val store = makeStore()
        val first = makeFlow(store)
        first.declineWarmup()
        first.exIndex = first.exercises.size - 1
        first.setIndex = 2
        first.completeSet()
        assertEquals(Phase.CooldownIntro, first.phase)
        val snapshot = assertNotNull(store.pendingWorkout)

        val flow = makeFlow(store, resume = snapshot)
        assertEquals(Phase.Feedback, flow.phase)
    }

    @Test
    fun theSummaryOfAFinishedHoldSurvivesAProcessDeath() {
        val store = makeStore()
        val first = makeFlow(store, holdSession())
        first.declineWarmup()
        first.exIndex = index(Pattern.coreAntiExt, first)
        first.setIndex = 2
        first.startHold()
        run(first, GetReady.countInSeconds + 15)
        assertEquals(Phase.ExerciseSummary, first.phase)

        val flow = makeFlow(store, holdSession(), resume = assertNotNull(store.pendingWorkout))
        assertEquals(Phase.ExerciseSummary, flow.phase)
        assertEquals(15, flow.holdMeasured[2])
    }

    @Test
    fun keepingTheWorkoutFromTodayCataloguesItWithoutRunningIt() {
        val store = makeStore()
        val first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        val snapshot = assertNotNull(store.pendingWorkout)
        tile.started = null

        val flow = makeFlow(store, resume = snapshot, settle = true)
        assertEquals(Phase.Feedback, flow.phase)
        assertNull(tile.started, "nothing for the lock screen to describe on the rating")
    }

    // MARK: - An absence the process lived through

    @Test
    fun anAbsenceIsSubtractedAndARunningRestIsNot() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.sceneLeft()
        advance(1_800)
        flow.sceneCameBack()
        assertEquals(1_800, flow.awaySec)

        flow.completeSet()
        flow.sceneLeft()
        advance(600)
        flow.sceneCameBack()
        assertEquals(1_800 + 540, flow.awaySec, "the 60 s rest that was running is training")
    }

    @Test
    fun onlyTheFirstLeavingCounts() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.sceneLeft()
        advance(100)
        flow.sceneLeft()
        advance(100)
        flow.sceneCameBack()
        assertEquals(200, flow.awaySec)
    }

    // MARK: - The guided blocks

    @Test
    fun theWarmUpWaitsToBeAskedAndNoMeansStraightToTheWork() {
        val store = makeStore()
        val flow = makeFlow(store)
        assertEquals(Phase.WarmupIntro, flow.phase)
        assertEquals("WARM-UP", tile.started?.title?.english)
        flow.declineWarmup()
        assertEquals(Phase.Work, flow.phase)
        assertEquals(0, flow.warmupSec, "a declined block bills nothing")
        assertEquals(0, store.pendingWorkout?.warmupSec)
    }

    @Test
    fun theWarmUpRunsToTheWorkAndBillsTheTimeItRan() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        assertEquals(Phase.Warmup, flow.phase)
        assertEquals(GetReady.countInSeconds, flow.warmup.clock.remaining, "a start tap opens on the count-in")
        val ran = run(flow, limit = 1_000) { flow.phase == Phase.Work }
        assertEquals(ran, flow.warmupSec)
        assertEquals(Event.Done, signals.tones.lastOrNull())
    }

    /** The threshold is measured to the fraction, as the rest measures it
     *  (`aRestMissedByAFractionPastTheThresholdDropsTheRun`): 4.6 s late is
     *  an absence, 4.0 s is not. */
    @Test
    fun aWarmUpBoundaryMissedByAFractionPastTheThresholdFreezes() {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        advance((GetReady.countInSeconds + BlockPause.absenceSeconds).toDouble() + 0.6)
        flow.tick()
        assertTrue(flow.blockPause.isHeld)
    }

    @Test
    fun aWarmUpBoundaryMissedByExactlyTheThresholdRunsOn() {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        advance((GetReady.countInSeconds + BlockPause.absenceSeconds).toDouble())
        flow.tick()
        assertFalse(flow.blockPause.isPaused)
        assertNotEquals(GuidedStage.getReady, flow.warmup.stage, "the boundary was crossed under the person's eyes")
    }

    @Test
    fun aWarmUpBoundaryCrossedWhileAwayFreezesTheBlockAndBillsNothingOfIt() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        advance(600)
        flow.tick()
        assertTrue(flow.blockPause.isHeld)
        assertEquals(Phase.Warmup, flow.phase)
        assertFalse(flow.warmup.clock.isRunning)
        assertEquals(GetReady.countInSeconds, flow.warmup.clock.remaining, "frozen on the second it showed")
        assertEquals(600 - GetReady.countInSeconds, flow.blockPausedSec)
        assertTrue(signals.events.contains(Event.Announce("Paused")))

        advance(100)
        flow.tick()
        assertTrue(flow.blockPause.isHeld, "a held block has nothing left to run out")
        flow.toggleBlockPause()
        assertFalse(flow.blockPause.isPaused, "a frozen transition is its own way back in")
        assertTrue(flow.warmup.clock.isRunning)
        assertEquals(700 - GetReady.countInSeconds, flow.blockPausedSec)
    }

    @Test
    fun aPausedMoveCountsTheAthleteBackInBeforeItRunsOn() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        run(flow) { flow.warmup.stage != GuidedStage.getReady }
        run(flow, 3)
        val frozen = flow.warmup.clock.remaining
        flow.toggleBlockPause()
        assertTrue(flow.blockPause.isHeld)
        advance(50)
        flow.toggleBlockPause()
        assertTrue(flow.blockPause.isReentering)
        assertEquals(BlockPause.reentrySeconds, flow.blockPause.reentryRemaining)

        signals.events.clear()
        run(flow, BlockPause.reentrySeconds)
        assertFalse(flow.blockPause.isPaused)
        assertEquals(frozen, flow.warmup.clock.remaining, "the move picks up the seconds it froze with")
        assertEquals(clock.plusSeconds(frozen.toLong()), flow.warmup.clock.endDate)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
        assertEquals(50, flow.blockPausedSec, "the way back in is the block again")
    }

    @Test
    fun aTransitionFrozenByAnAbsenceNearItsEndGetsItsWholeCountBack() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, GetReady.countInSeconds - 2)
        assertEquals(2, flow.warmup.clock.remaining)
        advance(60)
        flow.tick()
        assertTrue(flow.blockPause.isHeld)
        assertEquals(GuidedStage.getReady, flow.warmup.stage)
        assertEquals(2, flow.warmup.clock.remaining, "frozen on the second it showed; the floor comes at Resume")

        flow.toggleBlockPause()
        assertFalse(flow.blockPause.isPaused, "a frozen transition is its own way back in")
        assertEquals(clock.plusSeconds(GetReady.countInSeconds.toLong()), flow.warmup.clock.endDate,
                     "two seconds would put someone who has just come back into the move with no count")
        signals.events.clear()
        run(flow, GetReady.countInSeconds)
        assertNotEquals(GuidedStage.getReady, flow.warmup.stage)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
    }

    @Test
    fun aSwitchPausedNearItsEndGetsTheCountInBack() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, limit = 1_000) { flow.warmup.stage == GuidedStage.switchPause }
        run(flow) { flow.warmup.clock.remaining == 1 }
        flow.toggleBlockPause()
        advance(30)
        flow.toggleBlockPause()
        assertFalse(flow.blockPause.isPaused, "the switch is a transition too")
        assertEquals(clock.plusSeconds(GetReady.countInSeconds.toLong()), flow.warmup.clock.endDate)
        signals.events.clear()
        run(flow, GetReady.countInSeconds)
        assertEquals(GuidedStage.secondHalf, flow.warmup.stage)
        assertEquals(listOf<Event>(Event.Go), signals.tones, "no 3-2-1 inside the switch: its go is its signal")
    }

    @Test
    fun aCoolDownTransitionPausedNearItsEndGetsTheCountInBack() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow) { flow.cooldown.clock.remaining == 1 }
        assertEquals(GuidedStage.getReady, flow.cooldown.stage)
        flow.toggleBlockPause()
        advance(30)
        flow.toggleBlockPause()
        assertFalse(flow.blockPause.isPaused)
        assertEquals(clock.plusSeconds(GetReady.countInSeconds.toLong()), flow.cooldown.clock.endDate)
        signals.events.clear()
        run(flow, GetReady.countInSeconds)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.Go), signals.tones)
    }

    @Test
    fun aMovePausedNearItsEndKeepsItsSecondsAfterTheWayBackIn() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, limit = 1_000) { BlockPause.needsReentry(flow.warmup.stage) && flow.warmup.clock.remaining == 2 }
        flow.toggleBlockPause()
        advance(30)
        flow.toggleBlockPause()
        assertTrue(flow.blockPause.isReentering)
        run(flow, BlockPause.reentrySeconds)
        assertFalse(flow.blockPause.isPaused)
        assertEquals(clock.plusSeconds(2), flow.warmup.clock.endDate, "the floor is a transition's, never a position's")
    }

    @Test
    fun aCoolDownStretchPausedNearItsEndKeepsItsSecondsAfterTheWayBackIn() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow) { BlockPause.needsReentry(flow.cooldown.stage) && flow.cooldown.clock.remaining == 2 }
        flow.toggleBlockPause()
        advance(30)
        flow.toggleBlockPause()
        assertTrue(flow.blockPause.isReentering)
        run(flow, BlockPause.reentrySeconds)
        assertFalse(flow.blockPause.isPaused)
        assertEquals(clock.plusSeconds(2), flow.cooldown.clock.endDate,
                     "the cool-down's own stage decides, whatever the warm-up was left on")
    }

    @Test
    fun aTransitionPausedWithTimeLeftKeepsIt() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, limit = 1_000) {
            flow.warmup.index == 1 && flow.warmup.stage == GuidedStage.getReady && flow.warmup.clock.remaining == 6
        }
        flow.toggleBlockPause()
        advance(30)
        flow.toggleBlockPause()
        assertFalse(flow.blockPause.isPaused)
        assertEquals(clock.plusSeconds(6), flow.warmup.clock.endDate, "the floor never lengthens a transition")
    }

    @Test
    fun theTechniqueSheetHandsATransitionBackExactlyWhatItFroze() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, GetReady.countInSeconds - 1)
        assertEquals(1, flow.warmup.clock.remaining)
        flow.freezeForPositionTechnique()
        advance(30)
        flow.resumePositionCountdown()
        assertEquals(clock.plusSeconds(1), flow.warmup.clock.endDate,
                     "reading is not a pause: the floor belongs to the way back from one")
    }

    @Test
    fun theCoolDownIsOfferedAfterTheLastSetAndEndsOnTheRating() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        assertEquals(Phase.CooldownIntro, flow.phase)
        flow.beginCooldown()
        assertEquals(Phase.Cooldown, flow.phase)
        val ran = run(flow, limit = 1_000) { flow.phase == Phase.Feedback }
        assertEquals(ran, flow.cooldownSec)
        assertEquals(ran, store.pendingWorkout?.cooldownSec, "a process death on the rating keeps it")
        assertEquals(Event.WorkoutDone, signals.tones.lastOrNull())
        assertEquals(1, tile.ended)
        flow.rate(FeedbackResult.plan)
        assertEquals(ran, store.records.lastOrNull()?.cooldownSec, "the record keeps what the block ran")
    }

    @Test
    fun decliningTheCoolDownGoesStraightToTheRating() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.declineCooldown()
        assertEquals(Phase.Feedback, flow.phase)
        assertEquals(0, flow.cooldownSec)
        flow.rate(FeedbackResult.plan)
        assertEquals(0, store.records.lastOrNull()?.cooldownSec)
    }

    // MARK: - A cool-down the workout never reached

    /** A block never begun is zero, the same as a declined one. Left null, the
     *  record reads as one from before the blocks were measured, and both the
     *  Health energy and the history's plan clock charge it the planned
     *  minutes. */
    @Test
    fun finishNowFromTheWorkRecordsNoCoolDown() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipRest()
        flow.finishNow()
        assertEquals(0, store.pendingWorkout?.cooldownSec,
                     "a process death on the rating must not bring the planned minutes back")
        flow.rate(FeedbackResult.plan)
        assertNoCoolDownBilled(assertNotNull(store.records.lastOrNull()))
    }

    /** The zero is written only over null: whatever ends the workout once the
     *  block has ended by itself must not turn what it ran into nothing. */
    @Test
    fun finishNowAfterTheCoolDownEndedKeepsWhatItRan() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        val ran = run(flow, limit = 1_000) { flow.phase == Phase.Feedback }
        flow.finishNow()
        flow.rate(FeedbackResult.plan)
        assertEquals(ran, assertNotNull(store.records.lastOrNull()).cooldownSec)
    }

    /** The same interruption recorded twelve hours later from the snapshot the
     *  work wrote: whether the process survived must not decide the cool-down. */
    @Test
    fun aWorkoutAbandonedInTheWorkSettlesWithNoCoolDown() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipRest()
        val snapshot = assertNotNull(store.pendingWorkout)
        assertNull(snapshot.restEndDate, "on the work screen, not in a rest")
        assertNull(snapshot.cooldownSec, "the block is still ahead")

        val relaunched = makeStore()
        assertTrue(relaunched.settleAbandonedWorkout(now = clock.plus(WorkoutSessionStore.forgottenAfter)))
        assertNoCoolDownBilled(assertNotNull(relaunched.records.lastOrNull()))
    }

    /** Nothing performed, nothing to stretch: the flow goes to the rating
     *  without offering the block. */
    @Test
    fun aWorkoutOfPureSkipsRecordsNoCoolDown() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        repeat(flow.exercises.size) { flow.leaveExercise() }
        assertEquals(Phase.Feedback, flow.phase)
        flow.rate(FeedbackResult.plan)
        assertNoCoolDownBilled(assertNotNull(store.records.lastOrNull()))
    }

    /** A restore from the offer lands on the rating, where the block can no
     *  longer begin. Left there, by "Finish later" or a process death, and
     *  rated from Today's "Rate the workout", it was never begun. */
    @Test
    fun aWorkoutLeftOnTheCoolDownsOfferIsRatedWithNoCoolDown() {
        val store = makeStore()
        val first = makeFlow(store)
        first.declineWarmup()
        first.exIndex = first.exercises.size - 1
        first.setIndex = 2
        first.completeSet()
        assertEquals(Phase.CooldownIntro, first.phase)
        val snapshot = assertNotNull(store.pendingWorkout)
        assertEquals(0, snapshot.cooldownSec, "what a restore from the offer will record")

        val flow = makeFlow(store, resume = snapshot)
        assertEquals(Phase.Feedback, flow.phase)
        flow.rate(FeedbackResult.plan)
        assertNoCoolDownBilled(assertNotNull(store.records.lastOrNull()))
    }

    /** The same offer, recorded by the store twelve hours later. */
    @Test
    fun aWorkoutAbandonedOnTheCoolDownsOfferSettlesWithNoCoolDown() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        assertEquals(Phase.CooldownIntro, flow.phase)

        val relaunched = makeStore()
        assertTrue(relaunched.settleAbandonedWorkout(now = clock.plus(WorkoutSessionStore.forgottenAfter)))
        assertNoCoolDownBilled(assertNotNull(relaunched.records.lastOrNull()))
    }

    /** Where the zero stops: a snapshot taken inside the cool-down carries no
     *  measurement either, and a block that may be half done stays unknown,
     *  which falls back to its plan, rather than reading as declined. */
    @Test
    fun aWorkoutAbandonedInsideTheCoolDownLeavesItUnmeasured() {
        val store = makeStore()
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow, 30)

        val relaunched = makeStore()
        assertTrue(relaunched.settleAbandonedWorkout(now = clock.plus(WorkoutSessionStore.forgottenAfter)))
        assertNull(assertNotNull(relaunched.records.lastOrNull()).cooldownSec)
    }

    /** The record. iOS also prices it through `EnergyEstimate.segments` — the
     *  Health export's energy and the history's plan clock — which is not
     *  ported yet (health/, phase 3). */
    private fun assertNoCoolDownBilled(record: WorkoutRecord) {
        assertEquals(0, record.cooldownSec)
    }
}
