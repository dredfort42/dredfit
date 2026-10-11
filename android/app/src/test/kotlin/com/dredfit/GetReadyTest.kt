//
//  Port of ios/DredfitTests/GetReadyTests.swift: the transition before every
//  guided position, what it costs against the engine's reserve, and the stage
//  machine both blocks run on.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.core.generateSession
import com.dredfit.workout.Cooldown
import com.dredfit.workout.CooldownPosition
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedBlock.Step
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.SplitStageWords
import com.dredfit.workout.Warmup
import com.dredfit.workout.WarmupHalves
import com.dredfit.workout.WarmupMove
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GetReadyTest {

    /** The block composes six moves out of nine, so a stage machine cannot be
     *  asked about "the moves" — it has to be asked about a COMPOSITION.
     *  Session one's, throughout; the reserve tests in BlockReserveTest walk
     *  all of them. */
    private val warmupMoves: List<WarmupMove> = Warmup.moves(sessionNumber = 1)

    /** The index of the one move that pays the transition supplement — the
     *  trip down to the floor. */
    private val floorIndex: Int get() = warmupMoves.indexOfFirst { it.needsSetup }.takeIf { it >= 0 } ?: 0

    /** The dearest composition: the one the rotation fills with the most split
     *  moves — three of the four the pool has. Found, not named by session
     *  number: the rotation decides who appears, and a hard-coded 2 goes stale
     *  the first time the pool changes. */
    private val dearestComposition: List<WarmupMove>
        get() = (1..Warmup.compositionCount)
            .map { Warmup.moves(sessionNumber = it) }
            .maxByOrNull { moves -> moves.count { it.isSplit } } ?: emptyList()

    /** What one warm-up move costs uninterrupted: the transition, then the
     *  slot — two halves and the switch pause when the move has a boundary.
     *  Hand-rolled on purpose, unlike the cool-down twin below: an
     *  independent statement of the warm-up arithmetic. */
    private fun cost(move: WarmupMove): Int {
        val slot = if (move.isSplit) Warmup.halfSeconds * 2 + Cooldown.sideSwitchPauseSec else Warmup.moveSeconds
        return GetReady.seconds + (if (move.needsSetup) GetReady.setupSupplementSec else 0) + slot
    }

    // MARK: - The transition itself

    /** The transition and the side-switch pause are two different things: #35
     *  counts the switch inside a position, #52 the switch between positions.
     *  Travelling to another position takes time, turning over inside one does
     *  not — so they part on WHAT they are, not on how long they happen to be,
     *  and the split is pinned in both directions. */
    @Test
    fun theTransitionAndTheSideSwitchPauseKeepTheirOwnLengths() {
        assertEquals(8, GetReady.seconds)
        assertEquals(4, Cooldown.sideSwitchPauseSec)   // on trial
        assertNotEquals(GetReady.seconds, Cooldown.sideSwitchPauseSec,
                        "the transition and the switch pause must stay two lengths")
        assertEquals(GetReady.seconds, GetReady.stageSeconds(needsSetup = false))
        assertEquals(GetReady.seconds,
                     GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, Warmup.moves(sessionNumber = 1)[0]),
                     "marching starts where the user already stands")
    }

    @Test
    fun aPositionThatHasToBeGotIntoGetsTheSupplement() {
        // The differentiated pause of issue #83: base plus supplement for a
        // position that changes the starting position or needs a prop.
        assertEquals(4, GetReady.setupSupplementSec)
        assertEquals(GetReady.seconds + GetReady.setupSupplementSec, GetReady.stageSeconds(needsSetup = true))
        val positions = Cooldown.positions(performed = listOf(Pattern.pull))
        assertEquals("hip-flexors", positions[0].id)
        assertEquals(GetReady.seconds + GetReady.setupSupplementSec,
                     GuidedBlock.cooldown.stageSeconds(GuidedStage.getReady, positions[0]),
                     "the block opens by getting down onto one knee")
    }

    @Test
    fun onlyTheStandingPositionsKeepTheBaseTransition() {
        // The flag travels with the data, so this is the list issue #83
        // pinned: in the warm-up only cat-cow leaves standing; in the
        // cool-down only forward fold, the lat stretch and the wrists stay
        // upright with no wall to walk to.
        // The warm-up composes six of nine, and three of the nine are on the
        // floor — so "who pays the supplement" is a property of the
        // COMPOSITION, not of a move. Exactly one per session, always the trip
        // down to the floor, in every composition there is.
        for (session in 1..Warmup.compositionCount) {
            val moves = Warmup.moves(sessionNumber = session)
            assertEquals(listOf("cat-cow"), moves.filter { it.needsSetup }.map { it.id }, "session $session")
        }
        val allNine = Cooldown.positions(performed = listOf(Pattern.squat, Pattern.pull, Pattern.pushH)) +
            Cooldown.positions(performed = listOf(Pattern.coreAntiExt, Pattern.calf, Pattern.lunge))
        val standing = allNine.filter { !it.needsSetup }.map { it.id }.toSet()
        assertEquals(setOf("forward-fold", "lat-stretch", "wrists"), standing)
    }

    @Test
    fun theTransitionLeavesRoomForTheCountdownItPlays() {
        // The 3-2-1 has to fit inside it with a beat to spare for reading the
        // name of what is coming — a transition shorter than the ticks would
        // start mid-signal.
        assertTrue(GetReady.seconds > 3)
    }

    // MARK: - Honest numbers

    /**
     * What one position costs uninterrupted, supplement and sides included.
     *
     * Routes through `GetReady.stageSeconds(needsSetup)` rather than
     * re-deriving `seconds + setupSupplementSec` by hand, as
     * `BlockReserveTest.cost(CooldownPosition)` does too: two spellings of
     * one formula stay correct only as long as nobody changes the production
     * one without noticing the copy. Calling the real function makes that
     * impossible instead of merely unlikely.
     */
    private fun cost(position: CooldownPosition): Int {
        val hold = if (position.perSide) Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec else Cooldown.positionSeconds
        return GetReady.stageSeconds(needsSetup = position.needsSetup) + hold
    }

    /**
     * The decision this feature rests on: the transitions — supplements
     * included (#83) — ride on top of the minutes the engine reserves for
     * the two blocks. The worst case with nothing set aside is exact: the
     * dearest warm-up plus the fixed three positions plus the costliest three
     * the mapping can draw. BlockReserveTest adds the set-aside axis, where
     * the warm-up reaches 248 s.
     *
     * The FIT is not exact: a reserve is whole minutes, so it carries slack.
     * What is guarded is that the slack stays under two minutes — more, and
     * the engine would be holding minutes the blocks do not use.
     */
    @Test
    fun bothBlocksFitInsideTheReservedWarmupAndCooldownMinutes() {
        val warmup = dearestComposition.sumOf { cost(it) }

        // One pattern per pool position; index 2 of a one-pattern composition
        // is the position that pattern maps to.
        val pool = listOf(Pattern.squat, Pattern.pull, Pattern.pushH, Pattern.coreAntiExt, Pattern.calf, Pattern.lunge)
            .map { Cooldown.positions(performed = listOf(it))[2] }
        val worstMapped = pool.map { cost(it) }.sortedDescending().take(3).sum()
        val anyComposition = Cooldown.positions(performed = listOf(Pattern.squat))
        val fixed = cost(anyComposition[0]) + cost(anyComposition[1]) + cost(anyComposition[5])
        val reserved = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60

        // Lengthening the transition is what makes the reserve an engine
        // constraint; shortening it only ever leaves slack.
        assertEquals(244, warmup)
        assertEquals(272, fixed + worstMapped)
        assertTrue(warmup + fixed + worstMapped <= reserved, "the worst case overruns the reserved minutes")
        // Ten minutes is not the smallest whole minute that fits, and the
        // owner keeps it: giving the minute back is `cooldownMin` 4 → 3
        // through the reference chain, and it would take a minute off every
        // announced duration to reclaim slack nobody is short of. What is
        // guarded is drift, not tightness — `BlockReserveTest` holds the same
        // floor and ceiling over the axis the app actually composes on.
        assertTrue(reserved - (warmup + fixed + worstMapped) < 120,
                   "two whole minutes of slack: the reserve is no longer " +
                       "sized against the blocks it exists for")
    }

    @Test
    fun aRealCompositionLeavesRoom() {
        val performed = Engine.generateSession(EngineState.initial).exercises.map { it.pattern }
        val cooldown = Cooldown.positions(performed = performed).sumOf { cost(it) }
        val warmup = warmupMoves.sumOf { cost(it) }
        assertTrue(warmup + cooldown < (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60)
    }

    // MARK: - The warm-up stage machine

    @Test
    fun everyWarmupMoveOpensWithTheTransition() {
        // The first one included: the user has just pressed Start and is
        // still standing by the phone.
        assertEquals(GuidedStage.whole, GuidedBlock.step(after = Step(0, GuidedStage.getReady), positions = warmupMoves)?.stage)
        val next = GuidedBlock.step(after = Step(0, GuidedStage.whole), positions = warmupMoves)
        assertEquals(1, next?.index)
        assertEquals(GuidedStage.getReady, next?.stage)
    }

    @Test
    fun theWarmupEndsAfterTheLastMove() {
        assertNull(GuidedBlock.step(after = Step(warmupMoves.size - 1, GuidedStage.whole), positions = warmupMoves),
                   "the last move hands the flow to the first exercise")
        assertNotNull(GuidedBlock.step(after = Step(warmupMoves.size - 1, GuidedStage.getReady), positions = warmupMoves),
                      "...but its own transition still has a move to announce")
    }

    @Test
    fun warmupAdvanceNamesTheStageItEnters() {
        val intoMove = GuidedBlock.warmup.advance(from = Step(0, GuidedStage.getReady), overshoot = 0, positions = warmupMoves)
        assertEquals(GuidedStage.whole, intoMove?.entered)
        assertEquals(Warmup.moveSeconds, intoMove?.remaining)
        val intoTransition = GuidedBlock.warmup.advance(from = Step(0, GuidedStage.whole), overshoot = 0,
                                                        positions = warmupMoves)
        assertEquals(GuidedStage.getReady, intoTransition?.entered)
        assertEquals(1, intoTransition?.index)
        assertEquals(GetReady.seconds, intoTransition?.remaining)
    }

    @Test
    fun warmupAdvanceAbsorbsBackgroundedTime() {
        // Past a move's end by the whole next transition plus two seconds: the
        // transition is consumed whole and the landing is 2 s into the move it
        // announced. Written from the constant rather than from a literal,
        // which would silently go wrong the next time the transition moves.
        //
        // WHICH stage that move opens on is asked of the machine, not assumed:
        // a split move opens on its first half, not on the whole slot.
        val opening = assertNotNull(GuidedBlock.step(after = Step(1, GuidedStage.getReady), positions = warmupMoves)?.stage)
        val landing = GuidedBlock.warmup.advance(from = Step(0, GuidedStage.whole), overshoot = GetReady.seconds + 2,
                                                 positions = warmupMoves)
        assertEquals(1, landing?.index)
        assertEquals(opening, landing?.stage)
        assertEquals(GuidedBlock.warmup.stageSeconds(opening, warmupMoves[1]) - 2, landing?.remaining)
        // An absence past the whole block simply ends it.
        assertNull(GuidedBlock.warmup.advance(from = Step(0, GuidedStage.whole), overshoot = 10_000, positions = warmupMoves))
    }

    @Test
    fun warmupOvershootLandsOnAWholeMoveBoundary() {
        // A full move-plus-transition of absence advances by exactly one move
        // and lands at the top of the next transition, not mid-anything. The
        // cycle is the move's OWN: a split move's slot carries the switch
        // pause, a whole one runs straight through.
        val cycle = GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, warmupMoves[1]) +
            Warmup.slotSeconds(warmupMoves[1])
        val landing = GuidedBlock.warmup.advance(from = Step(0, GuidedStage.whole), overshoot = cycle, positions = warmupMoves)
        assertEquals(2, landing?.index)
        assertEquals(GuidedStage.getReady, landing?.stage)
        assertEquals(GetReady.seconds, landing?.remaining)
    }

    @Test
    fun theSupplementedTransitionStretchesTheWayOntoTheFloor() {
        // The one warm-up supplement (issue #83): the transition that takes
        // the person down to the floor, and advance() absorbs it at its LONGER
        // length — the overshoot below is that whole transition plus 2 s of
        // the move itself, written from the constants so the supplement is
        // what the test is actually about.
        //
        // The block has three floor moves in its pool and still exactly ONE
        // supplement: it is the trip DOWN that is paid for, not each position
        // on the floor.
        val onto = floorIndex
        assertTrue(onto > 0, "the floor is never the first move")
        val supplemented = GetReady.seconds + GetReady.setupSupplementSec
        assertEquals(supplemented, GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, warmupMoves[onto]))
        val landing = GuidedBlock.warmup.advance(from = Step(onto - 1, GuidedStage.whole), overshoot = supplemented + 2,
                                                 positions = warmupMoves)
        assertEquals(onto, landing?.index)
        assertEquals(GuidedStage.whole, landing?.stage)
        assertEquals(Warmup.moveSeconds - 2, landing?.remaining)
    }

    // MARK: - The warm-up's two halves

    @Test
    fun aSplitWarmupMoveWalksTheTwoHalvesAroundThePause() {
        val moves = dearestComposition
        val index = moves.indexOfFirst { it.isSplit }
        assertTrue(index >= 0, "the dearest composition must draw a split move")
        assertEquals(GuidedStage.firstHalf, GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = moves)?.stage)
        assertEquals(GuidedStage.switchPause, GuidedBlock.step(after = Step(index, GuidedStage.firstHalf), positions = moves)?.stage)
        assertEquals(GuidedStage.secondHalf, GuidedBlock.step(after = Step(index, GuidedStage.switchPause), positions = moves)?.stage)
        // All three stay on the same move: the switch is inside one position,
        // not travel to another, and an index that walked would show the next
        // move's name over the wrong countdown.
        for (stage in listOf(GuidedStage.getReady, GuidedStage.firstHalf, GuidedStage.switchPause)) {
            assertEquals(index, GuidedBlock.step(after = Step(index, stage), positions = moves)?.index,
                         "$stage must not walk off the move it belongs to")
        }
        val next = GuidedBlock.step(after = Step(index, GuidedStage.secondHalf), positions = moves)
        assertEquals(index + 1, next?.index, "the far side hands over to the next move")
        assertEquals(GuidedStage.getReady, next?.stage)
    }

    @Test
    fun aMoveWithNoBoundaryNeverSeesAHalf() {
        val moves = dearestComposition
        val index = moves.indexOfFirst { !it.isSplit }
        assertTrue(index >= 0)
        assertEquals(GuidedStage.whole, GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = moves)?.stage,
                     "a move with no halfway boundary runs the whole slot in one stage")
    }

    /** The distinction the block turns on: a move splits because its own steps
     *  name a moment, not because the movement looks two-sided. Torso rotations
     *  and cat-cow alternate CONTINUOUSLY — every rep, every breath — so there
     *  is no single moment to announce, and marching swings both legs by
     *  definition. Named by id, because "how many split" says nothing about
     *  which. */
    @Test
    fun onlyTheMovesWhoseStepsNameAMomentAreSplit() {
        val sides = mutableSetOf<String>()
        val directions = mutableSetOf<String>()
        val whole = mutableSetOf<String>()
        for (session in 1..Warmup.compositionCount) {
            for (move in Warmup.moves(sessionNumber = session)) {
                when (move.halves) {
                    WarmupHalves.sides -> sides += move.id
                    WarmupHalves.directions -> directions += move.id
                    null -> whole += move.id
                }
            }
        }
        assertEquals(setOf("single-leg-rdl", "bird-dog"), sides)
        assertEquals(setOf("arm-circles", "hip-circles"), directions)
        assertEquals(setOf("marching", "torso-rotations", "half-squats", "cat-cow", "y-t-w"), whole)
    }

    /** Sides and directions differ in the WORDS and in nothing else. A test
     *  can ask, because the words are a type rather than a `Text` (SwiftUI
     *  `Text` is not reliably equatable — the flake that rule came from). */
    @Test
    fun theWordsFollowWhatIsSwitchedAndTheSecondsDoNot() {
        val sides = SplitStageWords(halves = WarmupHalves.sides)
        val directions = SplitStageWords(halves = WarmupHalves.directions)
        assertNotEquals(sides.switching.english, directions.switching.english,
                        "a circle about to be reversed must not be told to switch sides")
        assertNotEquals(sides.secondHalf.english, directions.secondHalf.english)
        assertNotEquals(sides.everyHalf.english, directions.everyHalf.english)
        assertEquals("Switch sides", sides.switching.english)
        assertEquals("Switch direction", directions.switching.english)
        val moves = dearestComposition
        val bySide = assertNotNull(moves.firstOrNull { it.halves == WarmupHalves.sides })
        val byDirection = assertNotNull(moves.firstOrNull { it.halves == WarmupHalves.directions })
        assertEquals(Warmup.slotSeconds(bySide), Warmup.slotSeconds(byDirection),
                     "the two kinds cost the same: two halves and one switch pause")
    }

    @Test
    fun theTwoHalvesSplitTheSlotAndThePauseRidesOnTop() {
        val move = assertNotNull(dearestComposition.firstOrNull { it.isSplit })
        assertEquals(Warmup.halfSeconds, GuidedBlock.warmup.stageSeconds(GuidedStage.firstHalf, move))
        assertEquals(Warmup.halfSeconds, GuidedBlock.warmup.stageSeconds(GuidedStage.secondHalf, move))
        assertEquals(Cooldown.sideSwitchPauseSec, GuidedBlock.warmup.stageSeconds(GuidedStage.switchPause, move))
        assertEquals(Warmup.moveSeconds + Cooldown.sideSwitchPauseSec, Warmup.slotSeconds(move),
                     "the two halves ARE the slot; only the pause is added to it")
        val whole = assertNotNull(dearestComposition.firstOrNull { !it.isSplit })
        assertEquals(Warmup.moveSeconds, Warmup.slotSeconds(whole))
    }

    @Test
    fun theWarmupEndsAfterTheFarHalfOfASplitLastMove() {
        // A composition can end on a split move, and then `whole` is a stage
        // that never runs: the block has to end on `secondHalf` instead.
        val moves = assertNotNull((1..Warmup.compositionCount)
                                      .map { Warmup.moves(sessionNumber = it) }
                                      .firstOrNull { it.lastOrNull()?.isSplit == true },
                                  "some composition must end on a split move")
        assertNull(GuidedBlock.step(after = Step(moves.size - 1, GuidedStage.secondHalf), positions = moves),
                   "the far half of the last move hands the flow to the work")
    }

    @Test
    fun theWarmupSwitchIsABoundaryTheFlowCanSound() {
        // The tone is chosen from `entered` (see `WorkoutSession.tick(block)`), so the pause
        // has to be NAMED when the first side runs out. And a long absence
        // across the whole move must not report a switch nobody is standing
        // at: `entered` and `stage` disagree, and the flow stays silent.
        val moves = dearestComposition
        val index = moves.indexOfFirst { it.isSplit }
        assertTrue(index >= 0)
        val intoPause = GuidedBlock.warmup.advance(from = Step(index, GuidedStage.firstHalf), overshoot = 0, positions = moves)
        assertEquals(GuidedStage.switchPause, intoPause?.entered)
        assertEquals(Cooldown.sideSwitchPauseSec, intoPause?.remaining)
        val intoSecond = GuidedBlock.warmup.advance(from = Step(index, GuidedStage.switchPause), overshoot = 0, positions = moves)
        assertEquals(GuidedStage.secondHalf, intoSecond?.entered)
        assertEquals(Warmup.halfSeconds, intoSecond?.remaining)
        val landing = GuidedBlock.warmup.advance(from = Step(index, GuidedStage.getReady),
                                                 overshoot = Warmup.slotSeconds(moves[index]) + 1,
                                                 positions = moves)
        assertEquals(GuidedStage.firstHalf, landing?.entered, "the run opened on the first half")
        assertEquals(index + 1, landing?.index, "...and came to rest past the whole move")
        assertEquals(GuidedStage.getReady, landing?.stage)
    }

    // MARK: - What the signal has to be chosen from

    @Test
    fun advanceCanLandOnATransitionItDidNotEnter() {
        // Warm-up: one second past a move's own end, so the run opens on the
        // move and rests inside the next position's transition.
        val warmup = GuidedBlock.warmup.advance(from = Step(0, GuidedStage.getReady),
                                                overshoot = Warmup.moveSeconds + 1,
                                                positions = warmupMoves)
        assertEquals(GuidedStage.whole, warmup?.entered, "the run opened on the move")
        assertEquals(GuidedStage.getReady, warmup?.stage, "...but came to rest on a transition")
        assertEquals(1, warmup?.index)

        // Cool-down: the same shape across a whole per-side position.
        val positions = Cooldown.positions(performed = listOf(Pattern.pull))
        assertTrue(positions[0].perSide, "hip flexors open the block per side")
        val cooldown = GuidedBlock.cooldown.advance(
            from = Step(0, GuidedStage.getReady),
            overshoot = Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec + 2,
            positions = positions)
        assertEquals(GuidedStage.firstHalf, cooldown?.entered, "the run opened on the first side")
        assertEquals(GuidedStage.getReady, cooldown?.stage, "...but came to rest on a transition")
        assertEquals(1, cooldown?.index)
        assertEquals(GetReady.seconds + GetReady.setupSupplementSec - 2, cooldown?.remaining,
                     "chest wall carries the supplement — the wall has to be walked to")
    }

    // MARK: - The cool-down stage machine

    @Test
    fun everyCooldownPositionOpensWithTheTransition() {
        val positions = Cooldown.positions(performed = listOf(Pattern.pull))
        for ((index, position) in positions.withIndex()) {
            val after = GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = positions)
            assertEquals(index, after?.index, "${position.id}: the transition stays put")
            assertEquals(if (position.perSide) GuidedStage.firstHalf else GuidedStage.whole, after?.stage,
                         "${position.id}: the transition hands over to the position itself")
        }
    }

    @Test
    fun aBilateralPositionWalksTransitionThenTheWholeSlot() {
        // squat → forward fold, the first bilateral position of the block.
        val positions = Cooldown.positions(performed = listOf(Pattern.squat))
        val index = positions.indexOfFirst { !it.perSide }
        assertTrue(index >= 0, "the composition must contain a bilateral position")
        assertEquals(GuidedStage.whole, GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = positions)?.stage)
        assertEquals(Cooldown.positionSeconds, GuidedBlock.cooldown.stageSeconds(GuidedStage.whole, positions[index]))
    }

    @Test
    fun noStageIsEmpty() {
        // advance() walks stages while the overshoot covers them; a zero-length
        // stage would spin forever.
        for (position in Cooldown.positions(performed = listOf(Pattern.pull))) {
            for (stage in GuidedStage.entries) {
                assertTrue(GuidedBlock.cooldown.stageSeconds(stage, position) > 0,
                           "${position.id}.$stage has no length")
            }
        }
        assertTrue(Cooldown.switchPauseSeconds > 0)
        for (move in warmupMoves + dearestComposition) {
            for (stage in GuidedStage.entries) {
                assertTrue(GuidedBlock.warmup.stageSeconds(stage, move) > 0, "$stage at ${move.id} has no length")
            }
        }
    }
}
