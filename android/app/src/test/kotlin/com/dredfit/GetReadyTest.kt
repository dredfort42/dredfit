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
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GetReadyTest {

    /** The block composes six moves out of fourteen, so a stage machine cannot
     *  be asked about "the moves" — it has to be asked about a COMPOSITION.
     *  Session one's, which opens on a squat, throughout; the reserve tests in
     *  BlockReserveTest walk all of them. */
    private val warmupMoves: List<WarmupMove> = Warmup.moves(sessionNumber = 1, opening = Pattern.squat)

    /** Every composition with nothing set aside: each session of the rotation
     *  against every opening the lead-in reads, and none. */
    private val everyComposition: List<List<WarmupMove>>
        get() = (1..Warmup.rotationPeriod).flatMap { session ->
            (listOf<Pattern?>(null) + Pattern.allCases).map { Warmup.moves(sessionNumber = session, opening = it) }
        }

    /** What one warm-up move costs uninterrupted: the transition, then the
     *  thirty seconds — a reversed circle's two halves ARE the slot.
     *  Hand-rolled on purpose, unlike the cool-down twin below: an
     *  independent statement of the warm-up arithmetic. */
    @Suppress("UNUSED_PARAMETER")
    private fun cost(move: WarmupMove): Int = GetReady.seconds + Warmup.moveSeconds

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
                     GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, warmupMoves[0]),
                     "marching starts where the user already stands")
    }

    @Test
    fun aPositionThatHasToBeGotIntoGetsTheSupplement() {
        // The differentiated pause of issue #83: base plus supplement for the
        // transition that changes the starting position.
        assertEquals(4, GetReady.setupSupplementSec)
        assertEquals(GetReady.seconds + GetReady.setupSupplementSec, GetReady.stageSeconds(needsSetup = true))
        val positions = Cooldown.positions(sessionNumber = 1)
        val descent = assertNotNull(positions.indexOfFirst { it.level > CooldownPosition.Level.standing }
                                        .takeIf { it >= 0 })
        assertEquals("hip-flexors", positions[descent].id)
        assertEquals(GetReady.seconds + GetReady.setupSupplementSec,
                     GuidedBlock.cooldown.stageSeconds(GuidedStage.getReady, positions[descent]),
                     "the trip down onto one knee pays the supplement")
    }

    @Test
    fun onlyTheTripDownPaysTheSupplement() {
        // The flag travels with the data, so this is the list issue #83
        // pinned: the warm-up never leaves standing, and the cool-down goes
        // down once — what follows the kneeling lunge is already on the floor.
        for (moves in everyComposition) {
            assertEquals(emptyList(), moves.filter { it.needsSetup }.map { it.id },
                         "${moves.map { it.id }}: a warm-up transition paid the supplement")
        }
        for (session in 1..Cooldown.rotationPeriod) {
            assertEquals(listOf("hip-flexors"),
                         Cooldown.positions(sessionNumber = session).filter { it.needsSetup }.map { it.id },
                         "session $session")
        }
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
        val hold = if (position.halves?.pausesAtTheSwitch == true) Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec
                   else Cooldown.positionSeconds
        return GetReady.stageSeconds(needsSetup = position.needsSetup) + hold
    }

    /**
     * The decision this feature rests on: the transitions — the one
     * supplement included (#83) — ride on top of the minutes the engine
     * reserves for the two blocks. The worst case with nothing set aside is
     * exact: the dearest warm-up plus the dearest session of the cool-down's
     * rotation. BlockReserveTest adds the set-aside axis, where neither
     * block grows.
     *
     * The FIT is not exact: a reserve is whole minutes, so it carries slack.
     * What is guarded is that the slack stays under two minutes — more, and
     * the engine would be holding minutes the blocks do not use.
     */
    @Test
    fun bothBlocksFitInsideTheReservedWarmupAndCooldownMinutes() {
        val warmup = everyComposition.maxOf { moves -> moves.sumOf { cost(it) } }
        val cooldown = (1..Cooldown.rotationPeriod).maxOf { session ->
            Cooldown.positions(sessionNumber = session).sumOf { cost(it) }
        }
        val reserved = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60

        // Lengthening the transition is what makes the reserve an engine
        // constraint; shortening it only ever leaves slack.
        assertEquals(228, warmup)
        assertEquals(236, cooldown)
        assertTrue(warmup + cooldown <= reserved, "the worst case overruns the reserved minutes")
        // Nine is the smallest whole minute that fits: ten held more than two
        // spare once the cool-down stopped pausing on the spot, and the minute
        // went back through the reference chain. `BlockReserveTest` holds the
        // same floor and ceiling over the axis the app actually composes on.
        assertTrue(reserved - (warmup + cooldown) < 120,
                   "two whole minutes of slack: the reserve is no longer " +
                       "sized against the blocks it exists for")
    }

    @Test
    fun aRealCompositionLeavesRoom() {
        val session = Engine.generateSession(EngineState.initial)
        val cooldown = Cooldown.positions(sessionNumber = session.sessionNumber).sumOf { cost(it) }
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
        // and lands at the top of the next transition, not mid-anything. A
        // reversed circle runs the same thirty seconds as a whole move: its
        // halves have nothing between them.
        val cycle = GuidedBlock.warmup.stageSeconds(GuidedStage.getReady, warmupMoves[1]) +
            Warmup.moveSeconds
        val landing = GuidedBlock.warmup.advance(from = Step(0, GuidedStage.whole), overshoot = cycle, positions = warmupMoves)
        assertEquals(2, landing?.index)
        assertEquals(GuidedStage.getReady, landing?.stage)
        assertEquals(GetReady.seconds, landing?.remaining)
    }

    // MARK: - The warm-up's two halves

    /** A circle walks its two halves with NOTHING between them: the switch
     *  pause is for a side switch, which re-sets the body, and a circle
     *  reverses on the move. Both halves stay on the same move — an index
     *  that walked would show the next move's name over the wrong countdown. */
    @Test
    fun aReversedMoveWalksItsTwoHalvesWithNoPause() {
        val moves = warmupMoves
        val index = moves.indexOfFirst { it.reverses }
        assertTrue(index >= 0, "session one must draw a circle")
        assertEquals(GuidedStage.firstHalf, GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = moves)?.stage)
        val second = GuidedBlock.step(after = Step(index, GuidedStage.firstHalf), positions = moves)
        assertEquals(GuidedStage.secondHalf, second?.stage, "a circle reverses on the move: no switch pause")
        assertEquals(index, second?.index, "the second half belongs to the same move")
        val next = GuidedBlock.step(after = Step(index, GuidedStage.secondHalf), positions = moves)
        assertEquals(index + 1, next?.index, "the far half hands over to the next move")
        assertEquals(GuidedStage.getReady, next?.stage)
    }

    @Test
    fun aMoveWithNoBoundaryNeverSeesAHalf() {
        val moves = warmupMoves
        val index = moves.indexOfFirst { !it.reverses }
        assertTrue(index >= 0)
        assertEquals(GuidedStage.whole, GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = moves)?.stage,
                     "a move with no halfway boundary runs the whole slot in one stage")
    }

    /** The distinction the block turns on: a move splits because its own steps
     *  name a moment, not because the movement looks two-sided. Side steps,
     *  torso rotations, side bends and overhead reaches change side every rep,
     *  so there is no single moment to announce. Named by id, because "how
     *  many split" says nothing about which — and no move splits by SIDE: the
     *  warm-up asks nothing of one leg or one arm at a time. */
    @Test
    fun onlyTheCirclesAreSplitAndNoneBySide() {
        val reversing = mutableSetOf<String>()
        val whole = mutableSetOf<String>()
        for (move in everyComposition.flatten()) {
            assertNotEquals(WarmupHalves.sides, move.halves, "${move.id} splits by side")
            if (move.reverses) reversing += move.id else whole += move.id
        }
        assertEquals(setOf("arm-circles", "wrist-circles", "hip-circles"), reversing)
        assertEquals(setOf("marching", "side-steps", "heels-to-glutes", "arm-swings",
                           "reach-and-pull", "overhead-reaches", "torso-rotations",
                           "side-bends", "standing-cat-cow", "hip-hinges", "half-squats"), whole)
    }

    /** Sides and directions differ in the WORDS and in whether the clock stops.
     *  A test can ask about the words because they are a type rather than a
     *  `Text` (SwiftUI `Text` is not reliably equatable — the flake that rule
     *  came from). */
    @Test
    fun theWordsFollowWhatIsSwitchedAndOnlyASideSwitchPauses() {
        val sides = SplitStageWords(halves = WarmupHalves.sides)
        val directions = SplitStageWords(halves = WarmupHalves.directions)
        assertNotEquals(sides.switching.english, directions.switching.english,
                        "a circle about to be reversed must not be told to switch sides")
        assertNotEquals(sides.secondHalf.english, directions.secondHalf.english)
        assertNotEquals(sides.everyHalf.english, directions.everyHalf.english)
        assertEquals("Switch sides", sides.switching.english)
        assertEquals("Switch direction", directions.switching.english)
        assertTrue(WarmupHalves.sides.pausesAtTheSwitch, "turning over re-sets the body")
        assertFalse(WarmupHalves.directions.pausesAtTheSwitch, "a circle reverses on the move")
        // A side switched on the spot keeps the words of a side and loses only
        // the pause: the twist's knees go the other way, not "the other way".
        val onTheSpot = SplitStageWords(halves = WarmupHalves.sidesOnTheSpot)
        assertEquals(listOf(sides.switching.english, sides.secondHalf.english, sides.everyHalf.english),
                     listOf(onTheSpot.switching.english, onTheSpot.secondHalf.english, onTheSpot.everyHalf.english))
        assertFalse(WarmupHalves.sidesOnTheSpot.pausesAtTheSwitch, "the body stays where it is")
    }

    @Test
    fun theTwoHalvesOfACircleAreTheSlot() {
        val move = assertNotNull(warmupMoves.firstOrNull { it.reverses })
        assertEquals(Warmup.halfSeconds, GuidedBlock.warmup.stageSeconds(GuidedStage.firstHalf, move))
        assertEquals(Warmup.halfSeconds, GuidedBlock.warmup.stageSeconds(GuidedStage.secondHalf, move))
        assertEquals(Warmup.moveSeconds, Warmup.halfSeconds * 2,
                     "the two halves ARE the slot, and nothing rides on top of it")
    }

    @Test
    fun theWarmupEndsAfterTheFarHalfOfASplitLastMove() {
        // A composition can end on a circle — a session with no exercise to
        // lead into, whose trunk slot drew hip circles — and then `whole` is a
        // stage that never runs: the block has to end on `secondHalf` instead.
        val moves = assertNotNull(everyComposition.firstOrNull { it.lastOrNull()?.reverses == true },
                                  "some composition must end on a circle")
        assertNull(GuidedBlock.step(after = Step(moves.size - 1, GuidedStage.secondHalf), positions = moves),
                   "the far half of the last move hands the flow to the work")
    }

    @Test
    fun theWarmupSwitchIsABoundaryTheFlowCanSound() {
        // The tone is chosen from `entered` (see `WorkoutSession.tick(block)`), so
        // the second half has to be NAMED when the first runs out — with its
        // whole fifteen seconds, no pause taken out of them. And a long absence
        // across the whole move must not report a switch nobody is standing
        // at: `entered` and `stage` disagree, and the flow stays silent.
        val moves = warmupMoves
        val index = moves.indexOfFirst { it.reverses }
        assertTrue(index >= 0)
        val intoSecond = GuidedBlock.warmup.advance(from = Step(index, GuidedStage.firstHalf), overshoot = 0, positions = moves)
        assertEquals(GuidedStage.secondHalf, intoSecond?.entered)
        assertEquals(Warmup.halfSeconds, intoSecond?.remaining)
        val landing = GuidedBlock.warmup.advance(from = Step(index, GuidedStage.getReady),
                                                 overshoot = Warmup.moveSeconds + 1,
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

        // Cool-down: the same shape across a whole per-side position — the
        // kneeling lunge, whose sides are a re-set with a pause between them.
        val positions = Cooldown.positions(sessionNumber = 1)
        val lunge = assertNotNull(positions.indexOfFirst { it.halves == WarmupHalves.sides }.takeIf { it >= 0 })
        val cooldown = GuidedBlock.cooldown.advance(
            from = Step(lunge, GuidedStage.getReady),
            overshoot = Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec + 2,
            positions = positions)
        assertEquals(GuidedStage.firstHalf, cooldown?.entered, "the run opened on the first side")
        assertEquals(GuidedStage.getReady, cooldown?.stage, "...but came to rest on a transition")
        assertEquals(lunge + 1, cooldown?.index)
        assertEquals(GetReady.seconds - 2, cooldown?.remaining,
                     "the next position is already on the floor — the trip down is paid once")
    }

    // MARK: - The cool-down stage machine

    @Test
    fun everyCooldownPositionOpensWithTheTransition() {
        for (session in 1..Cooldown.rotationPeriod) {
            val positions = Cooldown.positions(sessionNumber = session)
            for ((index, position) in positions.withIndex()) {
                val after = GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = positions)
                assertEquals(index, after?.index, "${position.id}: the transition stays put")
                assertEquals(if (position.perSide) GuidedStage.firstHalf else GuidedStage.whole, after?.stage,
                             "${position.id}: the transition hands over to the position itself")
            }
        }
    }

    @Test
    fun aBilateralPositionWalksTransitionThenTheWholeSlot() {
        // The chest opener, the first bilateral position of session one.
        val positions = Cooldown.positions(sessionNumber = 1)
        val index = positions.indexOfFirst { !it.perSide }
        assertTrue(index >= 0, "the composition must contain a bilateral position")
        assertEquals(GuidedStage.whole, GuidedBlock.step(after = Step(index, GuidedStage.getReady), positions = positions)?.stage)
        assertEquals(Cooldown.positionSeconds, GuidedBlock.cooldown.stageSeconds(GuidedStage.whole, positions[index]))
    }

    /** The other half of the rule the warm-up's circles changed: a side switch
     *  that re-sets the body — the lunge changing its front leg — still stops
     *  the clock for its pause. Both blocks walk one stage machine, so the
     *  shortcut of a switch on the spot must not leak into a re-set. */
    @Test
    fun aSideReSetStillPauses() {
        val positions = Cooldown.positions(sessionNumber = 1)
        val index = assertNotNull(positions.indexOfFirst { it.halves == WarmupHalves.sides }.takeIf { it >= 0 })
        assertEquals(GuidedStage.switchPause,
                     GuidedBlock.step(after = Step(index, GuidedStage.firstHalf), positions = positions)?.stage)
        assertEquals(GuidedStage.secondHalf,
                     GuidedBlock.step(after = Step(index, GuidedStage.switchPause), positions = positions)?.stage)
    }

    @Test
    fun noStageIsEmpty() {
        // advance() walks stages while the overshoot covers them; a zero-length
        // stage would spin forever.
        for (position in (1..Cooldown.rotationPeriod).flatMap { Cooldown.positions(sessionNumber = it) }) {
            for (stage in GuidedStage.entries) {
                assertTrue(GuidedBlock.cooldown.stageSeconds(stage, position) > 0,
                           "${position.id}.$stage has no length")
            }
        }
        assertTrue(Cooldown.switchPauseSeconds > 0)
        for (move in everyComposition.flatten()) {
            for (stage in GuidedStage.entries) {
                assertTrue(GuidedBlock.warmup.stageSeconds(stage, move) > 0, "$stage at ${move.id} has no length")
            }
        }
    }
}
