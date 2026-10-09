//
//  Port of ios/DredfitTests/CooldownTests.swift: the cool-down composed from
//  what was performed, and its per-side stage machine (issue #35).
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
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CooldownTest {

    @Test
    fun sixPositionsForAFullSession() {
        val session = Engine.generateSession(EngineState.initial)
        val positions = Cooldown.positions(performed = session.exercises.map { it.pattern })
        assertEquals(Cooldown.positionCount, positions.size)
        assertEquals(positions.size, positions.map { it.id }.toSet().size, "no duplicates")
        assertEquals("rest-pose", positions.lastOrNull()?.id, "the rest pose closes the block")
        assertEquals("hip-flexors", positions[0].id)
        assertEquals("chest-wall", positions[1].id)
    }

    @Test
    fun compositionIsDeterministic() {
        val performed = Engine.generateSession(EngineState.initial).exercises.map { it.pattern }
        val first = Cooldown.positions(performed = performed)
        repeat(5) {
            assertEquals(first, Cooldown.positions(performed = performed))
        }
    }

    @Test
    fun mappingFollowsThePerformedMovements() {
        // pull → lats, squat → forward fold, calf → calf at the wall; in the
        // order the session ran them.
        val positions = Cooldown.positions(performed = listOf(Pattern.pull, Pattern.squat, Pattern.calf))
        assertEquals(listOf("hip-flexors", "chest-wall",
                            "lat-stretch", "forward-fold", "calf-wall", "rest-pose"),
                     positions.map { it.id })
    }

    @Test
    fun sharedPositionsDeduplicateAndTopUpFromThePool() {
        // squat and hinge share the forward fold; push_h and push_v share
        // wrists — three exercises' worth of movements can map to fewer than
        // three positions, and the pool tops the block back up to six.
        val positions = Cooldown.positions(
            performed = listOf(Pattern.squat, Pattern.hinge, Pattern.pushH, Pattern.pushV, Pattern.pull, Pattern.lunge))
        assertEquals(Cooldown.positionCount, positions.size)
        assertEquals(positions.size, positions.map { it.id }.toSet().size)
        // The mapped three come from the session in order: fold, wrists, lats.
        assertEquals("forward-fold", positions[2].id)
        assertEquals("wrists", positions[3].id)
        assertEquals("lat-stretch", positions[4].id)
    }

    @Test
    fun aWorkoutOfThreePerformedMovementsStillGetsSixPositions() {
        // Three performed movements that all map to distinct positions —
        // whatever left the other three out: skipped exercises, or a session
        // finished early.
        val positions = Cooldown.positions(performed = listOf(Pattern.pull, Pattern.squat, Pattern.coreRot))
        assertEquals(Cooldown.positionCount, positions.size)
        // And three that collapse to two mapped positions — topped up.
        val collapsed = Cooldown.positions(performed = listOf(Pattern.squat, Pattern.hinge, Pattern.pull))
        assertEquals(Cooldown.positionCount, collapsed.size)
        assertEquals(collapsed.size, collapsed.map { it.id }.toSet().size)
    }

    @Test
    fun nothingPerformedMeansNoCooldown() {
        assertTrue(Cooldown.positions(performed = emptyList()).isEmpty(),
                   "a workout of pure skips has nothing to stretch")
    }

    /** The holds alone — 6 × 30 s = 3 min — do not fill the reserved minutes:
     *  the reserve also pays for the transitions and the switch pauses that
     *  carry them. The whole-block counterpart lives in BlockReserveTest,
     *  where both blocks are counted together. */
    @Test
    fun theHoldsAloneDoNotFillTheReserve() {
        val holds = Cooldown.positionCount * Cooldown.positionSeconds
        assertEquals(180, holds, "six positions of thirty seconds")
        assertTrue(holds < EngineConfig.cooldownMin * 60, "the reserve carries the transitions as well")
    }

    @Test
    fun aPerSidePositionSplitsIntoTwoWholeSidesPlusThePause() {
        // 15 + 4 + 15 (issue #35): the slot splits into two equal whole
        // sides, and the pause is the app-layer constant shared with the
        // workout's per-side holds.
        assertEquals(Cooldown.positionSeconds, Cooldown.sideSeconds * 2, "the sides must consume the whole slot")
        assertEquals(15, Cooldown.sideSeconds)
        assertEquals(4, Cooldown.sideSwitchPauseSec)   // on trial
    }

    // MARK: - The stage machine (issue #35)

    /** pull → [hip flexors (per side), chest wall, lats, fold, calf... ] —
     *  enough to walk both a per-side and a bilateral position. */
    private val machinePositions: List<CooldownPosition>
        get() = Cooldown.positions(performed = listOf(Pattern.pull))

    @Test
    fun aPerSidePositionWalksSidesAroundThePause() {
        val positions = machinePositions
        assertTrue(positions[0].perSide, "hip flexors open the block per side")
        // Every position opens with the transition (issue #52); the sides
        // start once it runs out.
        assertEquals(GuidedStage.firstHalf, GuidedBlock.step(after = Step(0, GuidedStage.getReady), positions = positions)?.stage)
        val pause = GuidedBlock.step(after = Step(0, GuidedStage.firstHalf), positions = positions)
        assertEquals(GuidedStage.switchPause, pause?.stage)
        val second = GuidedBlock.step(after = Step(0, GuidedStage.switchPause), positions = positions)
        assertEquals(GuidedStage.secondHalf, second?.stage)
        // ...and the second side leaves the position entirely, into the next
        // position's transition.
        val next = GuidedBlock.step(after = Step(0, GuidedStage.secondHalf), positions = positions)
        assertEquals(1, next?.index)
        assertEquals(GuidedStage.getReady, next?.stage)
        assertEquals(GuidedStage.firstHalf, GuidedBlock.step(after = Step(1, GuidedStage.getReady), positions = positions)?.stage,
                     "chest wall is per side too — the app counts one arm, then the other")
    }

    @Test
    fun theBlockEndsAfterTheLastPosition() {
        val positions = machinePositions
        assertNull(GuidedBlock.step(after = Step(positions.size - 1, GuidedStage.whole), positions = positions))
    }

    @Test
    fun advanceNamesThePauseItEnters() {
        // The boundary crossed right now decides the signal: the first
        // side's end enters the pause (the falling switch tone), the
        // pause's end enters the second side (the usual go).
        val positions = machinePositions
        val intoPause = GuidedBlock.cooldown.advance(from = Step(0, GuidedStage.firstHalf), overshoot = 0,
                                                     positions = positions)
        assertEquals(GuidedStage.switchPause, intoPause?.entered)
        assertEquals(Cooldown.sideSwitchPauseSec, intoPause?.remaining)
        val intoSecond = GuidedBlock.cooldown.advance(from = Step(0, GuidedStage.switchPause), overshoot = 0,
                                                      positions = positions)
        assertEquals(GuidedStage.secondHalf, intoSecond?.entered)
        assertEquals(Cooldown.sideSeconds, intoSecond?.remaining)
    }

    @Test
    fun advanceAbsorbsBackgroundedTimeAcrossStages() {
        // 22 s past the first side's end: the pause (4) and the second side
        // (15) are consumed whole, landing 3 s into the next position — which
        // opens with its transition (#52), so 3 s into that.
        val positions = machinePositions
        val landing = GuidedBlock.cooldown.advance(from = Step(0, GuidedStage.firstHalf), overshoot = 22,
                                                   positions = positions)
        assertEquals(1, landing?.index)
        assertEquals(GuidedStage.getReady, landing?.stage)
        assertEquals(GetReady.seconds + GetReady.setupSupplementSec - 3, landing?.remaining,
                     "chest wall carries the supplement of issue #83")
        // An overshoot past the whole block is simply over.
        assertNull(GuidedBlock.cooldown.advance(from = Step(0, GuidedStage.firstHalf), overshoot = 10_000,
                                                positions = positions))
    }

    /** The flag decides whether the app counts the sides itself or hands the
     *  count to the user, so it has to agree with the position's own
     *  instructions (I-10). */
    @Test
    fun perSideFlagsAgreeWithTheInstructions() {
        val all = Cooldown.positions(
            performed = listOf(Pattern.squat, Pattern.pull, Pattern.pushH, Pattern.coreRot, Pattern.calf, Pattern.lunge)) +
            Cooldown.positions(performed = listOf(Pattern.calf, Pattern.lunge, Pattern.coreAntiExt))
        val unilateral = listOf("hip-flexors", "chest-wall", "wrists",
                                "calf-wall", "seated-glute", "lying-twist")
        for (position in all) {
            assertEquals(unilateral.contains(position.id), position.perSide,
                         "${position.id}: unexpected per-side flag")
        }
    }

    @Test
    fun noPositionTellsTheUserToSwapSidesItself() {
        val all = Cooldown.positions(
            performed = listOf(Pattern.squat, Pattern.pull, Pattern.pushH, Pattern.coreRot, Pattern.calf, Pattern.lunge)) +
            Cooldown.positions(performed = listOf(Pattern.calf, Pattern.lunge, Pattern.coreAntiExt))
        for (position in all) {
            for (step in position.steps) {
                assertFalse(step.english.contains("swap", ignoreCase = true),
                            "${position.id}: the app counts the sides itself — " +
                                "a step must not ask the user to swap them")
            }
        }
    }
}
