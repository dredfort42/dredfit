//
//  Port of ios/DredfitTests/PositionTechniqueTests.swift — the halves about
//  the pools themselves: the warm-up block's six moves and every position's
//  two to three steps.
//  — and the sheet's model, `PositionTechnique`
//  (ui/workout/PositionTechniqueSheet.kt). The capsules are compared on their
//  English (`Words.english`), which is what the iOS test reads on an English
//  simulator.
//

package com.dredfit

import com.dredfit.core.Pattern
import com.dredfit.ui.workout.PositionTechnique
import com.dredfit.workout.Cooldown
import com.dredfit.workout.CooldownPosition
import com.dredfit.workout.Warmup
import com.dredfit.workout.WarmupHalves
import com.dredfit.workout.WarmupMove
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PositionTechniqueTest {

    /** Two compositions that together surface all nine pool positions. */
    private val allCooldownPositions: List<CooldownPosition>
        get() = (Cooldown.positions(listOf(Pattern.squat, Pattern.pull, Pattern.pushH, Pattern.coreRot,
                                           Pattern.calf, Pattern.lunge)) +
            Cooldown.positions(listOf(Pattern.calf, Pattern.lunge, Pattern.coreAntiExt))).distinct()

    @Test
    fun theWarmupBlockIsSixDistinctMoves() {
        val moves = Warmup.moves(sessionNumber = 1)
        assertEquals(6, moves.size)
        assertEquals(6, moves.map { it.id }.toSet().size, "ids must be unique")
        for (move in moves) assertFalse(move.name.english.isEmpty(), "${move.id}: empty name")
    }

    @Test
    fun everyPositionCarriesTwoToThreeSteps() {
        val cooldown = allCooldownPositions
        assertEquals(9, cooldown.size, "the two compositions must surface the whole pool")
        for (position in cooldown) {
            assertTrue(position.steps.size in 2..3, "${position.id}: ${position.steps.size} steps")
            assertFalse(position.steps.any { it.english.isEmpty() }, "${position.id}: an empty step")
        }
        for (move in Warmup.moves(sessionNumber = 1)) {
            assertTrue(move.steps.size in 2..3, "${move.id}: ${move.steps.size} steps")
            assertFalse(move.steps.any { it.english.isEmpty() }, "${move.id}: an empty step")
        }
    }

    @Test
    fun sheetModelMirrorsItsSource() {
        val move = Warmup.moves(sessionNumber = 1)[0]
        val fromWarmup = PositionTechnique.of(move)
        assertEquals(move.id, fromWarmup.id)
        assertEquals(move.name, fromWarmup.name)
        assertEquals(move.steps, fromWarmup.steps)

        val position = allCooldownPositions[0]
        val fromCooldown = PositionTechnique.of(position)
        assertEquals(position.id, fromCooldown.id)
        assertEquals(position.name, fromCooldown.name)
        assertEquals(position.steps, fromCooldown.steps)
    }

    /** A warm-up move that splits the way `halves` says, found rather than
     *  named by session number: the rotation decides who appears. */
    private fun warmupMove(halves: WarmupHalves?): WarmupMove? =
        (1..Warmup.compositionCount).flatMap { Warmup.moves(sessionNumber = it) }.firstOrNull { it.halves == halves }

    @Test
    fun capsulesTellTheBlocksAndTheSidesApart() {
        val warmup = PositionTechnique.of(Warmup.moves(sessionNumber = 1)[0]).capsule.english
        val positions = allCooldownPositions
        val perSide = PositionTechnique.of(assertNotNull(positions.firstOrNull { it.perSide })).capsule.english
        val bilateral = PositionTechnique.of(assertNotNull(positions.firstOrNull { !it.perSide })).capsule.english
        assertFalse(warmup.isEmpty())
        assertNotEquals(warmup, bilateral, "warm-up and cool-down must be told apart")
        assertNotEquals(perSide, bilateral, "a per-side slot reads differently")
        // The capsules carry the real block constants, not copies of them.
        assertTrue(warmup.contains("${Warmup.moveSeconds}"))
        assertTrue(perSide.contains("${Cooldown.sideSeconds}"))
        assertTrue(bilateral.contains("${Cooldown.positionSeconds}"))
    }

    /** A split warm-up move says the length of ONE half, and sides and
     *  directions must not read alike. */
    @Test
    fun aSplitWarmupMoveNamesTheLengthOfOneHalf() {
        val bySide = assertNotNull(warmupMove(WarmupHalves.sides), "the pool must draw one")
        val byDirection = assertNotNull(warmupMove(WarmupHalves.directions), "...and one of these")
        val whole = assertNotNull(warmupMove(null))
        val capsules = listOf(bySide, byDirection).map { PositionTechnique.of(it).capsule.english }
        for (capsule in capsules) {
            assertTrue(capsule.contains("${Warmup.halfSeconds}"), "the capsule must name one half: $capsule")
            assertFalse(capsule.contains("${Warmup.moveSeconds}"), "the whole slot is not what is asked for: $capsule")
        }
        assertEquals(2, capsules.toSet().size, "sides and directions must not read alike")
        assertFalse(PositionTechnique.of(whole).capsule.english in capsules,
                    "a split move must not read like a move that runs straight through")
    }
}
