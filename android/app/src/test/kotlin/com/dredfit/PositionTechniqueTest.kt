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
import com.dredfit.workout.WarmupMove
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PositionTechniqueTest {

    /** The whole pool of ten: each of session one's positions set aside in
     *  turn, over the rotation — a fallback only appears once its zone's first
     *  choice is gone. */
    private val allCooldownPositions: List<CooldownPosition>
        get() {
            val seen = mutableListOf<CooldownPosition>()
            val first = Cooldown.positions(sessionNumber = 1).map { it.id }
            for (hidden in listOf(emptyList<String>()) + first.map { listOf(it) }) {
                for (session in 1..Cooldown.rotationPeriod) {
                    for (position in Cooldown.positions(sessionNumber = session, hiding = hidden.toSet())) {
                        if (seen.none { it.id == position.id }) seen += position
                    }
                }
            }
            return seen
        }

    @Test
    fun theWarmupBlockIsSixDistinctMoves() {
        val moves = Warmup.moves(sessionNumber = 1, opening = Pattern.squat)
        assertEquals(6, moves.size)
        assertEquals(6, moves.map { it.id }.toSet().size, "ids must be unique")
        for (move in moves) assertFalse(move.name.english.isEmpty(), "${move.id}: empty name")
    }

    @Test
    fun everyPositionCarriesTwoToThreeSteps() {
        val cooldown = allCooldownPositions
        assertEquals(10, cooldown.size, "the compositions must surface the whole pool")
        for (position in cooldown) {
            assertTrue(position.steps.size in 2..3, "${position.id}: ${position.steps.size} steps")
            assertFalse(position.steps.any { it.english.isEmpty() }, "${position.id}: an empty step")
        }
        for (move in Warmup.moves(sessionNumber = 1, opening = Pattern.squat)) {
            assertTrue(move.steps.size in 2..3, "${move.id}: ${move.steps.size} steps")
            assertFalse(move.steps.any { it.english.isEmpty() }, "${move.id}: an empty step")
        }
    }

    @Test
    fun sheetModelMirrorsItsSource() {
        val move = Warmup.moves(sessionNumber = 1, opening = Pattern.squat)[0]
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

    /** A warm-up move that reverses or not, as asked. Found rather than named
     *  by session number: the rotation is what decides who appears, and a
     *  hard-coded 2 would go stale the first time the pool changes. */
    private fun warmupMove(reverses: Boolean): WarmupMove? =
        (1..Warmup.rotationPeriod).flatMap { Warmup.moves(sessionNumber = it, opening = Pattern.squat) }
            .firstOrNull { it.reverses == reverses }

    @Test
    fun capsulesTellTheBlocksAndTheSidesApart() {
        val warmup = PositionTechnique.of(Warmup.moves(sessionNumber = 1, opening = Pattern.squat)[0]).capsule.english
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

    /** A circle has two halves, and the sheet says the length of ONE of them.
     *  "warm-up · 30 s" on a move that turns at fifteen would be the number of
     *  neither half — the sheet is read while the countdown is frozen,
     *  precisely to check what is being asked. And it says a DIRECTION: the
     *  cool-down's per-side capsule over a circle would tell the person to
     *  swap something they are meant to reverse. */
    @Test
    fun aCircleNamesTheLengthOfOneDirection() {
        val circle = assertNotNull(warmupMove(reverses = true), "the pool must draw a circle")
        val whole = assertNotNull(warmupMove(reverses = false))
        val capsule = PositionTechnique.of(circle).capsule.english
        assertTrue(capsule.contains("${Warmup.halfSeconds}"), "the capsule must name one half: $capsule")
        assertFalse(capsule.contains("${Warmup.moveSeconds}"), "the whole slot is not what is asked for: $capsule")
        assertEquals("warm-up · ${Warmup.halfSeconds} s each way", capsule)
        assertNotEquals(capsule, PositionTechnique.of(whole).capsule.english,
                        "a circle must not read like a move that runs straight through")
    }
}
