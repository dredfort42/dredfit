//
//  Port of ios/DredfitTests/BlockPauseTests.swift: the pause of the guided
//  blocks and of a hands-free rest — the way back in, which stages need one,
//  and the state that owns the freeze.
//

package com.dredfit

import com.dredfit.core.Pattern
import com.dredfit.workout.BlockPause
import com.dredfit.workout.Cooldown
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.Warmup
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BlockPauseTest {

    // MARK: - The way back in

    @Test
    fun theWayBackInIsTheCountIn() {
        // A third length would be a third thing to learn: four seconds is the
        // count-in after every start tap, and the pause between the sides of
        // a position (#35). The way back in is the same
        // beat — Resume is tapped by someone already standing in place, so
        // there is no travel to pay for.
        //
        // Pinned twice: once against the constant it is wired to, and once
        // against the NUMBER — a pin that only says "equals that other
        // symbol" moves silently when the symbol does.
        assertEquals(GetReady.countInSeconds, BlockPause.reentrySeconds)
        assertEquals(4, BlockPause.reentrySeconds)
        // The switch pause is the same beat, so the two are one number. It is
        // on trial and may move, and the value pin above keeps the count-in
        // from following it silently.
        assertEquals(Cooldown.sideSwitchPauseSec, BlockPause.reentrySeconds,
                     "the way back in and the switch are the same beat")
        assertTrue(BlockPause.reentrySeconds < GetReady.seconds,
                   "travel to a position is longer than being counted back into one")
    }

    @Test
    fun theWayBackInLeavesRoomForTheCountdownItPlays() {
        // The 3-2-1 has to fit inside it with a beat to spare for finding the
        // position again — that is the whole reason it exists rather than
        // dropping the user back mid-count.
        assertTrue(BlockPause.reentrySeconds > 3)
    }

    /** A REST resumes into itself — no lead-in, because a rest is time
     *  being given rather than a position to be counted back into, and its own
     *  3-2-1 is still ahead of it. What it takes instead is a floor: on a
     *  hands-free hold run the rest STARTS the next set, and resuming with two
     *  seconds left would drop someone who has just walked back in into a
     *  plank. */
    @Test
    fun aResumedRestKeepsItsSecondsAndNeverEndsUnderTheCountIn() {
        assertEquals(40, BlockPause.restAfterPause(remaining = 40, total = 60),
                     "a pause must not lengthen a rest that has time left")
        assertEquals(60, BlockPause.restAfterPause(remaining = 60, total = 60))
        assertEquals(BlockPause.reentrySeconds, BlockPause.restAfterPause(remaining = 1, total = 60))
        assertEquals(BlockPause.reentrySeconds, BlockPause.restAfterPause(remaining = 0, total = 60))
        // …and the floor is capped by the rest itself, so a one-second rest
        // (--uitest-fast collapses them) is not stretched to four.
        assertEquals(1, BlockPause.restAfterPause(remaining = 0, total = 1))
        assertEquals(1, BlockPause.restAfterPause(remaining = 1, total = 1))
    }

    // MARK: - Which stages need one

    @Test
    fun aFrozenTransitionIsItsOwnWayBackIn() {
        // Each still has its own signal ahead of it — the 3-2-1 into the go
        // that starts a position, the go into the second side. A lead-in
        // ending on a go of its own would sound the same thing twice.
        assertFalse(BlockPause.needsReentry(GuidedStage.getReady))
        assertFalse(BlockPause.needsReentry(GuidedStage.switchPause),
                    "the side-switch beat is a transition like any other")
    }

    @Test
    fun everyStageThatIsAPositionGetsTheWayBackIn() {
        for (stage in listOf(GuidedStage.whole, GuidedStage.firstHalf, GuidedStage.secondHalf)) {
            assertTrue(BlockPause.needsReentry(stage),
                       "$stage drops the user into a position, so it has to count them in")
        }
    }

    @Test
    fun onlyATransitionHasAFloorAfterAPause() {
        // A transition is the way back in, so its count and its go must still
        // be ahead of it; a position keeps its seconds, after a re-entry of its own.
        for (stage in listOf(GuidedStage.getReady, GuidedStage.switchPause)) {
            assertEquals(GetReady.countInSeconds, BlockPause.stageAfterPause(remaining = 1, stage = stage))
            assertEquals(GetReady.countInSeconds, BlockPause.stageAfterPause(remaining = 0, stage = stage))
            assertEquals(7, BlockPause.stageAfterPause(remaining = 7, stage = stage),
                         "a pause must not lengthen a transition that has time left")
        }
        for (stage in listOf(GuidedStage.whole, GuidedStage.firstHalf, GuidedStage.secondHalf)) {
            assertEquals(1, BlockPause.stageAfterPause(remaining = 1, stage = stage),
                         "$stage picks up what it froze with")
        }
    }

    @Test
    fun aZeroLengthWayBackInJustHolds() {
        // It would otherwise end on the next tick, with a go and no count.
        val state = BlockPause.State()
        state.beginReentry(seconds = 0, now = Instant.now())
        assertTrue(state.isHeld)
        assertNull(state.reentryEndDate)
    }

    // MARK: - The state itself

    @Test
    fun aHeldBlockHasNoDeadlineToRunOut() {
        // Which is why a locked or backgrounded phone costs a paused block
        // nothing: there is no end date left anywhere to expire.
        val state = BlockPause.State()
        state.hold()
        assertTrue(state.isPaused)
        assertTrue(state.isHeld)
        assertFalse(state.isReentering)
        assertNull(state.reentryEndDate)
        assertEquals(BlockPause.Tick.nothing, state.tick(Instant.now().plusSeconds(3_600), signalSeconds = 3),
                     "an hour away must not move a held block")
    }

    @Test
    fun theWayBackInTicksDownAndThenHandsOver() {
        val start = Instant.ofEpochSecond(1_000)
        val state = BlockPause.State()
        state.beginReentry(seconds = 5, now = start)
        assertTrue(state.isReentering)
        assertFalse(state.isHeld, "counting back in is not standing still")

        assertEquals(BlockPause.Tick.redraw, state.tick(start.plusSeconds(1), signalSeconds = 3))
        assertEquals(4, state.reentryRemaining)
        assertEquals(BlockPause.Tick.signal, state.tick(start.plusSeconds(2), signalSeconds = 3),
                     "the last three seconds are the 3-2-1")
        assertEquals(BlockPause.Tick.nothing, state.tick(start.plusSeconds(2), signalSeconds = 3),
                     "the same second twice is not a second")
        assertEquals(BlockPause.Tick.over, state.tick(start.plusSeconds(5), signalSeconds = 3))
    }

    @Test
    fun pausingAgainMidWayBackInHoldsTheBlock() {
        val state = BlockPause.State()
        state.beginReentry(seconds = 5, now = Instant.now())
        state.hold()
        assertTrue(state.isHeld)
        assertEquals(0, state.reentryRemaining, "the lead-in starts over on the next resume")
    }

    @Test
    fun thePauseOutranksTheTechniqueSheetsOwnFreeze() {
        // #34 freezes the countdown while the mini-sheet is open and hands it
        // back on dismissal. Over a held block it must hand back nothing.
        val state = BlockPause.State()
        state.hold()
        state.freezeForSheet()
        state.thawAfterSheet(now = Instant.now())
        assertTrue(state.isHeld, "closing the sheet must not restart a stopped block")
        assertNull(state.reentryEndDate)
    }

    @Test
    fun theSheetFreezesTheWayBackInAndHandsBackWhatItFroze() {
        val start = Instant.ofEpochSecond(1_000)
        val state = BlockPause.State()
        state.beginReentry(seconds = 5, now = start)
        state.tick(start.plusSeconds(2), signalSeconds = 3)     // 3 left

        state.freezeForSheet()
        assertEquals(BlockPause.Tick.nothing, state.tick(start.plusSeconds(600), signalSeconds = 3),
                     "reading is not getting back into position either")

        state.thawAfterSheet(now = start.plusSeconds(600))
        assertEquals(3, state.reentryRemaining)
        assertEquals(BlockPause.Tick.over, state.tick(start.plusSeconds(603), signalSeconds = 3),
                     "it picks up the three seconds it was frozen with")
    }

    // MARK: - Honest numbers

    @Test
    fun thePauseAddsNothingToWhatTheBlocksPromise() {
        // The pause is user-initiated, so no estimate moves (#61 follows the
        // precedent of #52). What the blocks cost uninterrupted is unchanged
        // by this feature — the stage lengths are the same ones GetReadyTest
        // measures against the reserved minutes.
        val positions = Cooldown.positions(performed = listOf(Pattern.pull))
        val warmup = Warmup.moves(sessionNumber = 1)
        assertEquals(Warmup.moveSeconds, GuidedBlock.warmup.stageSeconds(GuidedStage.whole, warmup[0]))
        assertEquals(GetReady.seconds, GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, warmup[0]))
        assertEquals(Warmup.halfSeconds, GuidedBlock.warmup.stageSeconds(GuidedStage.firstHalf, warmup[0]))
        assertEquals(Cooldown.sideSwitchPauseSec, GuidedBlock.warmup.stageSeconds(GuidedStage.switchPause, warmup[0]),
                     "one gesture, one length — the cool-down's constant")
        assertEquals(Cooldown.positionSeconds, GuidedBlock.cooldown.stageSeconds(GuidedStage.whole, positions[0]))
        assertEquals(Cooldown.sideSeconds, GuidedBlock.cooldown.stageSeconds(GuidedStage.firstHalf, positions[0]))
        assertEquals(Cooldown.sideSwitchPauseSec, GuidedBlock.cooldown.stageSeconds(GuidedStage.switchPause, positions[0]))
    }
}
