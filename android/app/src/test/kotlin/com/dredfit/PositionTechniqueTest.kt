//
//  Port of ios/DredfitTests/PositionTechniqueTests.swift — the halves about
//  the pools themselves: the warm-up block's six moves and every position's
//  two to three steps.
//
//  Not ported: `testSheetModelMirrorsItsSource`,
//  `testCapsulesTellTheBlocksAndTheSidesApart` and
//  `testASplitWarmupMoveNamesTheLengthOfOneHalf` — their subject,
//  `PositionTechnique` (ios/Dredfit/Views/Workout/PositionTechniqueSheet.swift),
//  is the technique sheet's model, whose Compose twin is not written yet.
//

package com.dredfit

import com.dredfit.core.Pattern
import com.dredfit.workout.Cooldown
import com.dredfit.workout.CooldownPosition
import com.dredfit.workout.Warmup
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
}
