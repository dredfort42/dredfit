//
//  Port of ios/DredfitTests/CooldownTests.swift: the cool-down composed zone
//  by zone for the session, from standing down to lying, its stage machine
//  (issue #35), and where a recomposed block picks up.
//

package com.dredfit

import com.dredfit.core.EngineConfig
import com.dredfit.store.MAX_HIDDEN_BLOCK_MOVES
import com.dredfit.workout.Cooldown
import com.dredfit.workout.CooldownPosition
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedBlock.Step
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.WarmupHalves
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.cooldownLanding
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class CooldownTest {

    /** Every position of the pool of ten, surfaced by setting each one aside in
     *  turn over the rotation: the fallbacks only appear when their zone's
     *  first choice is gone. */
    private val wholePool: List<CooldownPosition>
        get() {
            val seen = mutableListOf<CooldownPosition>()
            val first = Cooldown.positions(sessionNumber = 1)
            for (hidden in listOf(emptySet<String>()) + first.map { setOf(it.id) }) {
                for (session in 1..Cooldown.rotationPeriod) {
                    for (position in Cooldown.positions(sessionNumber = session, hiding = hidden)) {
                        if (seen.none { it.id == position.id }) seen += position.copy(needsSetup = false)
                    }
                }
            }
            return seen
        }

    @Test
    fun thePoolIsTen() {
        assertEquals(10, wholePool.map { it.id }.toSet().size)
    }

    /** The same six zones in every session, standing first and lying last. */
    @Test
    fun sixPositionsOneZoneEachFromStandingToLying() {
        assertEquals(listOf("chest-opener", "half-fold", "hip-flexors",
                            "child-side-reach", "lying-figure-four", "lying-twist"),
                     Cooldown.positions(sessionNumber = 1).map { it.id })
        assertEquals(listOf("wrists", "half-fold", "hip-flexors",
                            "rest-pose", "lying-figure-four", "lying-twist"),
                     Cooldown.positions(sessionNumber = 2).map { it.id },
                     "two zones alternate their variant from session to session")
        assertEquals(2, Cooldown.rotationPeriod)
        assertEquals(Cooldown.positions(sessionNumber = 1), Cooldown.positions(sessionNumber = 3))
    }

    @Test
    fun compositionIsDeterministic() {
        val first = Cooldown.positions(sessionNumber = 7, hiding = setOf("half-fold"))
        repeat(5) {
            assertEquals(first, Cooldown.positions(sessionNumber = 7, hiding = setOf("half-fold")))
        }
    }

    /** The point of the block's order: one trip down, and nobody gets up
     *  again — whatever is set aside, because a refilled zone is put back on
     *  its own level rather than where the gap was. */
    @Test
    fun theBlockOnlyEverGoesDownAndPaysForOneDescent() {
        val ids = wholePool.map { it.id }
        for (hidden in hiddenSets(ids)) {
            for (session in 1..Cooldown.rotationPeriod) {
                val block = Cooldown.positions(sessionNumber = session, hiding = hidden)
                val named = "session $session, set aside ${hidden.sorted()}"
                assertEquals(Cooldown.positionCount, block.size, named)
                val levels = block.map { it.level }
                assertEquals(levels.sorted(), levels, "$named: the block climbs back up")
                assertEquals(1, block.count { it.needsSetup }, "$named: one descent, one supplement")
                assertEquals(block.firstOrNull { it.level > CooldownPosition.Level.standing }?.id,
                             block.firstOrNull { it.needsSetup }?.id,
                             "$named: the supplement belongs to the trip down")
            }
        }
    }

    /** A zone set aside entirely is refilled from its own level: the finishing
     *  twist gives its slot to another position lying down, not to one that
     *  would put the person back on their feet. */
    @Test
    fun anEmptiedZoneIsRefilledFromItsOwnLevel() {
        assertEquals("knees-to-chest",
                     Cooldown.positions(sessionNumber = 1, hiding = setOf("lying-twist")).lastOrNull()?.id)
        assertEquals("standing-hip-flexors",
                     Cooldown.positions(sessionNumber = 1, hiding = setOf("hip-flexors"))
                         .firstOrNull { it.id.contains("hip-flexors") }?.id,
                     "someone who cannot kneel still gets the hip flexors, standing")
    }

    /** The standing lunge is the kneeling one for somebody who cannot kneel,
     *  not a stretch of its own: drawn to refill another zone, it would give
     *  the block the hip flexors twice, and a second switch pause. */
    @Test
    fun theStandingLungeOnlyEverStandsInForTheKneelingOne() {
        for (hidden in hiddenSets(wholePool.map { it.id })) {
            for (session in 1..Cooldown.rotationPeriod) {
                val ids = Cooldown.positions(sessionNumber = session, hiding = hidden).map { it.id }
                assertEquals("hip-flexors" in hidden && "standing-hip-flexors" !in hidden,
                             ids.contains("standing-hip-flexors"),
                             "session $session, set aside ${hidden.sorted()}")
            }
        }
    }

    /** A list longer than the cap — a hand-edited state file — is honoured only
     *  as far as the block stays six. The standing lunge refills no other zone,
     *  so it is not spare: with four set aside and the kneeling lunge still
     *  drawn, honouring the fourth would leave five. */
    @Test
    fun aListPastTheCapStillComposesSix() {
        val hidden = setOf("chest-opener", "wrists", "half-fold", "rest-pose")
        for (session in 1..Cooldown.rotationPeriod) {
            assertEquals(Cooldown.positionCount, Cooldown.positions(sessionNumber = session, hiding = hidden).size,
                         "session $session")
        }
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
        // 15 + 15, and 15 + 4 + 15 where the switch is a re-set (issue #35):
        // the slot splits into two equal whole sides, and the pause is the
        // app-layer constant shared with the workout's per-side holds.
        assertEquals(Cooldown.positionSeconds, Cooldown.sideSeconds * 2, "the sides must consume the whole slot")
        assertEquals(15, Cooldown.sideSeconds)
        assertEquals(4, Cooldown.sideSwitchPauseSec)   // on trial
    }

    // MARK: - The stage machine (issue #35)

    /** Session one: chest opener, half fold, hip flexors (a re-set between
     *  sides), the side reach, the figure-four and the twist (switched on the
     *  spot) — every kind of position the block has. */
    private val machinePositions: List<CooldownPosition>
        get() = Cooldown.positions(sessionNumber = 1)

    private fun index(of: String): Int =
        assertNotNull(machinePositions.indexOfFirst { it.id == of }.takeIf { it >= 0 }, "$of is not in session one")

    @Test
    fun aSideReSetWalksTheSidesAroundThePause() {
        val positions = machinePositions
        val lunge = index(of = "hip-flexors")
        assertEquals(GuidedStage.firstHalf,
                     GuidedBlock.step(after = Step(lunge, GuidedStage.getReady), positions = positions)?.stage)
        assertEquals(GuidedStage.switchPause,
                     GuidedBlock.step(after = Step(lunge, GuidedStage.firstHalf), positions = positions)?.stage,
                     "changing the front leg of a kneeling lunge is a re-set")
        assertEquals(GuidedStage.secondHalf,
                     GuidedBlock.step(after = Step(lunge, GuidedStage.switchPause), positions = positions)?.stage)
        val next = GuidedBlock.step(after = Step(lunge, GuidedStage.secondHalf), positions = positions)
        assertEquals(lunge + 1, next?.index)
        assertEquals(GuidedStage.getReady, next?.stage)
    }

    /** The warm-up's rule for its circles, here for sides: where the body
     *  stays put, the second side starts on the tone with the clock running. */
    @Test
    fun aSwitchOnTheSpotRunsNoPause() {
        val positions = machinePositions
        for (id in listOf("child-side-reach", "lying-figure-four", "lying-twist")) {
            val at = index(of = id)
            assertEquals(GuidedStage.secondHalf,
                         GuidedBlock.step(after = Step(at, GuidedStage.firstHalf), positions = positions)?.stage,
                         "$id: a switch on the spot must not stop the clock")
            assertEquals(Cooldown.positionSeconds, Cooldown.slotSeconds(positions[at]))
        }
        assertEquals(Cooldown.positionSeconds + Cooldown.sideSwitchPauseSec,
                     Cooldown.slotSeconds(positions[index(of = "hip-flexors")]))
    }

    @Test
    fun theBlockEndsAfterTheFarSideOfTheTwist() {
        val positions = machinePositions
        assertNull(GuidedBlock.step(after = Step(positions.size - 1, GuidedStage.secondHalf), positions = positions))
    }

    @Test
    fun advanceNamesThePauseItEnters() {
        // The boundary crossed right now decides the signal: the first
        // side's end enters the pause (the falling switch tone), the
        // pause's end enters the second side (the usual go).
        val positions = machinePositions
        val lunge = index(of = "hip-flexors")
        val intoPause = GuidedBlock.cooldown.advance(from = Step(lunge, GuidedStage.firstHalf), overshoot = 0,
                                                     positions = positions)
        assertEquals(GuidedStage.switchPause, intoPause?.entered)
        assertEquals(Cooldown.sideSwitchPauseSec, intoPause?.remaining)
        val intoSecond = GuidedBlock.cooldown.advance(from = Step(lunge, GuidedStage.switchPause), overshoot = 0,
                                                      positions = positions)
        assertEquals(GuidedStage.secondHalf, intoSecond?.entered)
        assertEquals(Cooldown.sideSeconds, intoSecond?.remaining)
    }

    @Test
    fun advanceAbsorbsBackgroundedTimeAcrossStages() {
        // 22 s past the first side's end: the pause (4) and the second side
        // (15) are consumed whole, landing 3 s into the next position — which
        // opens with its transition (#52), the plain one: the trip down was
        // paid on the way into the lunge.
        val positions = machinePositions
        val lunge = index(of = "hip-flexors")
        val landing = GuidedBlock.cooldown.advance(from = Step(lunge, GuidedStage.firstHalf), overshoot = 22,
                                                   positions = positions)
        assertEquals(lunge + 1, landing?.index)
        assertEquals(GuidedStage.getReady, landing?.stage)
        assertEquals(GetReady.seconds - 3, landing?.remaining)
        // An overshoot past the whole block is simply over.
        assertNull(GuidedBlock.cooldown.advance(from = Step(lunge, GuidedStage.firstHalf), overshoot = 10_000,
                                                positions = positions))
    }

    /** The halves decide whether the app counts the sides itself and whether
     *  the clock stops between them, so they have to agree with the
     *  position's own instructions (I-10): a re-set only where the base of the
     *  body changes. */
    @Test
    fun theHalvesAgreeWithWhatTheBodyDoes() {
        val reSet = setOf("hip-flexors", "standing-hip-flexors")
        val onTheSpot = setOf("wrists", "child-side-reach", "lying-figure-four", "lying-twist")
        for (position in wholePool) {
            when (position.halves) {
                WarmupHalves.sides -> assertTrue(position.id in reSet, position.id)
                WarmupHalves.sidesOnTheSpot -> assertTrue(position.id in onTheSpot, position.id)
                WarmupHalves.directions -> fail("${position.id}: no stretch of the pool reverses")
                null -> assertFalse(position.id in reSet + onTheSpot, position.id)
            }
        }
    }

    @Test
    fun noPositionTellsTheUserToSwapSidesItself() {
        for (position in wholePool) {
            for (step in position.steps) {
                assertFalse(step.english.contains("swap", ignoreCase = true),
                            "${position.id}: the app counts the sides itself — " +
                                "a step must not ask the user to swap them")
                assertFalse(step.english.contains("wall", ignoreCase = true),
                            "${position.id}: the block needs no wall")
            }
        }
    }

    // MARK: - Where a recomposed block picks up

    /** Session one with the kneeling lunge set aside stands through [chest
     *  opener, half fold, standing lunge]; setting the standing lunge aside too
     *  on slot 2 empties the hip flexors' zone, and its refill is the wrists —
     *  standing, so they sort in at slot 1, above the slot on screen, and the
     *  half fold slides to 2. A clamped ordinal would name the half fold —
     *  already done. */
    @Test
    fun hidingThePositionOnScreenNeverReopensOneAlreadyDone() {
        val before = Cooldown.positions(sessionNumber = 1, hiding = setOf("hip-flexors"))
        assertEquals(listOf("chest-opener", "half-fold", "standing-hip-flexors",
                            "child-side-reach", "lying-figure-four", "lying-twist"), before.map { it.id },
                     "the composition this was measured on")
        val after = Cooldown.positions(sessionNumber = 1, hiding = setOf("hip-flexors", "standing-hip-flexors"))
        val passed = before.take(2).map { it.id }.toSet()
        assertTrue(after[2].id in passed, "the ordinal the clamp kept names a position already done")
        val landing = assertNotNull(WorkoutSession.cooldownLanding(after, after = passed, reached = before[2].level))
        assertEquals("child-side-reach", after[landing].id)
    }

    /** The one the athlete cannot even see coming: "Bring back" does not
     *  dismiss the technique sheet. Session one with both standing upper-body
     *  stretches set aside is [half fold, kneeling lunge, side reach, rest
     *  pose, figure-four, twist]; restoring the wrists on slot 1 puts them
     *  back at the top, where standing positions go, and pushes everything
     *  after them one slot right, so a clamped ordinal would name the half
     *  fold — already done. */
    @Test
    fun bringingAPositionBackNeverReopensOneAlreadyDone() {
        val before = Cooldown.positions(sessionNumber = 1, hiding = setOf("chest-opener", "wrists"))
        assertEquals(listOf("half-fold", "hip-flexors", "child-side-reach",
                            "rest-pose", "lying-figure-four", "lying-twist"), before.map { it.id },
                     "the composition this was measured on")
        val after = Cooldown.positions(sessionNumber = 1, hiding = setOf("chest-opener"))
        val passed = before.take(1).map { it.id }.toSet()
        assertTrue(after[1].id in passed, "the ordinal the clamp kept names a position already done")
        val landing = assertNotNull(WorkoutSession.cooldownLanding(after, after = passed, reached = before[1].level))
        assertEquals("hip-flexors", after[landing].id)
    }

    /** Bringing a zone's first choice back drops the stand-in that ran in its
     *  place. Session one with the kneeling lunge set aside: kneeling in the
     *  side reach, the standing lunge behind them, the athlete brings the
     *  kneeling lunge back. Measured from the ids alone the block would land
     *  on it — up onto one knee, the hip flexors twice, seven positions. */
    @Test
    fun bringingBackAPositionAboveTheAthleteWaitsForTheNextWorkout() {
        val before = Cooldown.positions(sessionNumber = 1, hiding = setOf("hip-flexors"))
        val after = Cooldown.positions(sessionNumber = 1)
        val passed = before.take(3).map { it.id }.toSet()
        assertEquals("child-side-reach", before[3].id, "the composition this was measured on")
        val landing = assertNotNull(WorkoutSession.cooldownLanding(after, after = passed, reached = before[3].level))
        assertEquals("child-side-reach", after[landing].id, "the block carries on where the athlete kneels")
    }

    /** Every change the sheet can make, at every slot of every composition the
     *  app can draw: set the position on screen aside while the cap allows, or
     *  bring back any one already aside. The block that then runs — what is
     *  behind the athlete, and the new list from the landing on — never gets
     *  them up, never runs a position twice, never holds both lunges and never
     *  runs more than six. "Up" is measured from the position on screen as
     *  well: it is not in either half of the run, and a landing above it reads
     *  as a block that only goes down. */
    @Test
    fun noChangeMidBlockGetsTheAthleteUpOrLengthensTheBlock() {
        for (hidden in hiddenSets(wholePool.map { it.id })) {
            for (session in 1..Cooldown.rotationPeriod) {
                val before = Cooldown.positions(sessionNumber = session, hiding = hidden)
                for (slot in before.indices) {
                    val changes = hidden.map { hidden - it }.toMutableList()
                    if (hidden.size < MAX_HIDDEN_BLOCK_MOVES) changes += hidden + before[slot].id
                    for (change in changes) {
                        val after = Cooldown.positions(sessionNumber = session, hiding = change)
                        val behind = before.take(slot)
                        val landing = WorkoutSession.cooldownLanding(after, after = behind.map { it.id }.toSet(),
                                                                     reached = before[slot].level)
                        val run = behind + (landing?.let { after.drop(it) } ?: emptyList())
                        val named = "session $session, set aside ${hidden.sorted()}, " +
                            "slot $slot, then ${change.sorted()}"
                        val levels = run.map { it.level }
                        assertEquals(levels.sorted(), levels, "$named: the athlete gets up again")
                        if (landing != null) {
                            assertTrue(after[landing].level >= before[slot].level,
                                       "$named: sent up from the position on screen")
                        }
                        assertEquals(run.size, run.map { it.id }.toSet().size, "$named: a position runs twice")
                        assertFalse(run.any { it.id == "hip-flexors" } && run.any { it.id == "standing-hip-flexors" },
                                    "$named: both lunges")
                        assertTrue(run.size <= Cooldown.positionCount,
                                   "$named: the block runs longer than it promised")
                    }
                }
            }
        }
    }

    private fun hiddenSets(ids: List<String>): List<Set<String>> {
        val out = mutableListOf<Set<String>>(emptySet())
        for (size in 1..MAX_HIDDEN_BLOCK_MOVES) {
            out += combinations(ids, size)
        }
        return out
    }

    private fun combinations(ids: List<String>, size: Int): List<Set<String>> {
        if (size <= 0) return listOf(emptySet())
        if (ids.size < size) return emptyList()
        val out = mutableListOf<Set<String>>()
        for ((offset, id) in ids.withIndex()) {
            for (rest in combinations(ids.drop(offset + 1), size - 1)) {
                out += rest + id
            }
        }
        return out
    }
}
