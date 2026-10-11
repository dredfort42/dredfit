//
//  Port of ios/DredfitTests/HoldFactsTests.swift: the arithmetic of a
//  hands-free hold — the writer the exercise summary needs, the allowance a
//  hold ended by thumb pays, and the time a declared hold runs for. Every
//  rule here is a pure function on purpose: a rule stated inside a view is a
//  rule no gating test can reach.
//  `AdjustPanel.holdStep` lives on the panel's Compose file
//  (ui/workout/AdjustPanel.kt) as plain Kotlin, as it is a static on iOS.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe
import com.dredfit.core.generateSession
import com.dredfit.ui.workout.AdjustPanel
import com.dredfit.workout.SetFacts
import com.dredfit.workout.holdEndedByTap
import com.dredfit.workout.holdTarget
import com.dredfit.workout.restGoHeardWithinSec
import com.dredfit.workout.restHandsOverWithCountIn
import com.dredfit.workout.runOpensSet
import org.junit.jupiter.api.BeforeEach
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HoldFactsTest {

    private lateinit var session: Session
    /** The plan of 3×45 seconds. */
    private lateinit var hold: SessionExercise
    /** The plan of 3×15 reps — the uneven-plan cases are built off it. */
    private lateinit var reps: SessionExercise

    @BeforeEach
    fun setUp() {
        val state = EngineState.initial
        for (p in Pattern.allCases) {
            state.doses[p] = Dose.grid(Library.unit(p, 1)).max
            // A ceiling offers a PROBE, which would change what the
            // last set of these exercises even is. "Hard" was said, so the
            // plan is three working sets and nothing else.
            state.lastHard.add(p)
        }
        // The second session: the rotation puts no hold in session one.
        state.counter = 1
        session = Engine.generateSession(state)
        hold = assertNotNull(session.exercises.firstOrNull { it.unit == LoadUnit.hold })
        reps = assertNotNull(session.exercises.firstOrNull { it.unit == LoadUnit.reps })
        // Read off the generator rather than assumed: if the plan moves, this
        // fails here instead of silently testing arithmetic about another one.
        assertEquals(listOf(3, 45), listOf(hold.sets, hold.load))
        assertEquals(listOf(3, 15), listOf(reps.sets, reps.load))
        assertNull(hold.probe)
    }

    // MARK: - Writing one set without truncating the rest

    /** The defect the summary's writer exists to make impossible: correcting
     *  set 1 when sets 2 and 3 are already recorded must not delete them, as
     *  `recording` — which truncates by design — would. */
    @Test
    fun correctingAnEarlierSetLeavesTheLaterOnesStanding() {
        var facts = SetFacts.recording(40, emptyMap(), hold, set = 0)
        facts = SetFacts.recording(38, facts, hold, set = 1)
        facts = SetFacts.recording(36, facts, hold, set = 2)
        assertEquals(listOf(40, 38, 36), SetFacts.allSets(facts, hold))

        val corrected = SetFacts.recordingSet(50, facts, hold, set = 0)
        assertEquals(listOf(50, 38, 36), SetFacts.allSets(corrected, hold),
                     "the sets after the corrected one are facts, not forecasts")
    }

    /** `recording`, the work screen's writer, still truncates: there the sets
     *  after the one under way have not happened yet. This and
     *  `correctingAnEarlierSetLeavesTheLaterOnesStanding` are one rule. */
    @Test
    fun theWorkScreenWriterStillTruncates() {
        var facts = SetFacts.recording(40, emptyMap(), hold, set = 0)
        facts = SetFacts.recording(38, facts, hold, set = 1)
        facts = SetFacts.recording(36, facts, hold, set = 2)

        val rewritten = SetFacts.recording(50, facts, hold, set = 0)
        assertEquals(listOf(50), rewritten[hold.pattern],
                     "a number entered mid-exercise carries forward; it does " +
                         "not stand beside sets that have not been performed")
    }

    /** Gaps are filled with THIS set's plan. Against the flat base an uneven
     *  plan would be filled with the wrong number on its top set. */
    @Test
    fun gapsBeforeTheCorrectedSetAreFilledWithTheirOwnPlan() {
        val uneven = assertNotNull(unevenReps())
        val plan = (0 until uneven.sets).map { uneven.plannedLoad(set = it) }
        assertTrue(plan[0] > plan[1], "the top set is what makes it uneven")
        val facts = SetFacts.recordingSet(plan[2] - 2, emptyMap(), uneven, set = 2)
        assertEquals(listOf(plan[0], plan[1], plan[2] - 2), SetFacts.allSets(facts, uneven),
                     "sets 1 and 2 ran silently, each at its own planned dose")
    }

    /** Everything back on the plan is nothing said at all — the way "put it
     *  back" works, and the reason the entry is dropped rather than stored. */
    @Test
    fun correctingEverythingBackOntoThePlanSaysNothing() {
        var facts = SetFacts.recordingSet(40, emptyMap(), hold, set = 1)
        assertNotNull(facts[hold.pattern])
        facts = SetFacts.recordingSet(45, facts, hold, set = 1)
        assertNull(facts[hold.pattern],
                   "a record equal to the plan set for set is not a record")
    }

    /** An UNEVEN plan performed exactly as written is also nothing said.
     *  Compared against the flat base, 9-8-8 would read as a shortfall on its
     *  own first set and hand the engine a number nobody reported. */
    @Test
    fun anUnevenPlanPerformedAsWrittenIsNothingSaid() {
        val uneven = assertNotNull(unevenReps())
        var facts = SetFacts.recordingSet(uneven.plannedLoad(set = 0), emptyMap(), uneven, set = 0)
        facts = SetFacts.recordingSet(uneven.plannedLoad(set = 1), facts, uneven, set = 1)
        facts = SetFacts.recordingSet(uneven.plannedLoad(set = 2), facts, uneven, set = 2)
        assertNull(facts[uneven.pattern])
    }

    /**
     * Bounded by the exercise, like `allSets`: an index past the last set
     * writes nothing rather than growing an array no exercise can have.
     *
     * The second half is the summary's own semantics and not an accident:
     * the sets AFTER the corrected one keep the numbers they ran at, because
     * on the summary they are already behind. On the work screen the same
     * entry carries forward instead (`recording`), where the sets ahead have
     * not happened and the shortfall is a statement about the exercise.
     */
    @Test
    fun aSetOutsideTheExerciseWritesNothing() {
        val facts = SetFacts.recordingSet(40, emptyMap(), hold, set = 9)
        assertNull(facts[hold.pattern])
        val negative = SetFacts.recordingSet(40, emptyMap(), hold, set = -3)
        assertEquals(listOf(40, 45, 45), SetFacts.allSets(negative, hold),
                     "a negative index is set one, as everywhere else")
    }

    // MARK: - The clock records every set of an uneven plan

    /**
     * An uneven plan held exactly as asked — 20-15-15 here, 35-30-30 in the
     * field — must not come out as 20-20-15 (35-35-30) on the summary, in the
     * journal and in the next plan, with nothing typed and nothing declared.
     * The clock records every set through `recording`, so a hold to plan
     * writes set 1 (nothing said), set 2 (nothing said), then set 3 — and
     * the fill for the two sets already behind has to give set two its own
     * plan, not set ONE's number. Walked the way the flow walks it: the clock
     * is set from `holdTarget`, then records what ran.
     */
    @Test
    fun aHoldRunExactlyToAnUnevenPlanSaysNothing() {
        val uneven = assertNotNull(unevenHold())
        val plan = (0 until uneven.sets).map { uneven.plannedLoad(set = it) }
        assertTrue(plan[0] > plan[1], "the top set is what makes it uneven")
        var facts: Map<Pattern, List<Int>> = emptyMap()
        for (set in 0 until uneven.sets) {
            val ran = SetFacts.holdTarget(facts, uneven, set = set, declared = null)
            assertEquals(plan[set], ran, "set ${set + 1} counts down from its own plan")
            facts = SetFacts.recording(ran, facts, uneven, set = set)
            assertNull(facts[uneven.pattern],
                       "set ${set + 1} held as asked is nothing said — the " +
                           "record must not diverge from the plan on its own")
        }
        assertEquals(plan, SetFacts.allSets(facts, uneven))
        assertNull(SetFacts.override(facts, uneven, skipping = emptySet()), "the rating governs the pattern")
    }

    /** The fill itself, on the set that shows the defect: a third set
     *  recorded with nothing said before it gets sets one and two AT THEIR
     *  OWN PLAN — what `inForce` showed and the clock ran — not set one's
     *  number twice. The summary's writer fills the same way
     *  (`gapsBeforeTheCorrectedSetAreFilledWithTheirOwnPlan`). */
    @Test
    fun gapsBeforeTheSetUnderWayAreFilledAsTheScreenReadThem() {
        val uneven = assertNotNull(unevenHold())
        val plan = (0 until uneven.sets).map { uneven.plannedLoad(set = it) }
        val facts = SetFacts.recording(plan[2] - 5, emptyMap(), uneven, set = 2)
        assertEquals(listOf(plan[0], plan[1], plan[2] - 5), SetFacts.allSets(facts, uneven),
                     "sets 1 and 2 ran silently, each at its own planned dose")
    }

    /** The same rule after a SURPLUS. A number above the plan stays on its
     *  own set (`inForce`), so the clock of the set after it ran the plan —
     *  and that is what the fill has to say it ran once a later set is
     *  recorded, not the surplus. */
    @Test
    fun theFillAfterASurplusIsThePlanTheClockRan() {
        var facts = SetFacts.recording(hold.load + 5, emptyMap(), hold, set = 0)
        assertEquals(hold.load, SetFacts.holdTarget(facts, hold, set = 1, declared = null),
                     "set two counts down from the plan, not from the surplus")
        facts = SetFacts.recording(hold.load - 5, facts, hold, set = 2)
        assertEquals(listOf(hold.load + 5, hold.load, hold.load - 5), SetFacts.allSets(facts, hold))
    }

    // MARK: - The allowance a thumb pays

    /** The tap lands after the effort has stopped — the person comes off the
     *  floor and reaches for the phone — so a hold ended by tap is written
     *  down, never up. */
    @Test
    fun aHoldEndedByTapPaysTheReachAllowance() {
        assertEquals(45, SetFacts.holdEndedByTap(heldSeconds = 48))
        assertEquals(87, SetFacts.holdEndedByTap(heldSeconds = 90))
    }

    /** Never below what a hold can be STORED as. The mis-tap grace lets a set
     *  end at four seconds, and the corridor's floor is five. */
    @Test
    fun theAllowanceNeverFallsThroughTheCorridorFloor() {
        val floor = SetFacts.corridor(LoadUnit.hold).first
        assertEquals(floor, SetFacts.holdEndedByTap(heldSeconds = 6))
        assertEquals(floor, SetFacts.holdEndedByTap(heldSeconds = 4))
    }

    // MARK: - The time a hold is set to run

    /** Without a declaration nothing changes: the clock runs on the plan, and
     *  on whatever an earlier set reported. */
    @Test
    fun withoutADeclarationTheClockIsThePlan() {
        assertEquals(45, SetFacts.holdTarget(emptyMap(), hold, set = 0, declared = null))
        val short = SetFacts.recording(30, emptyMap(), hold, set = 0)
        assertEquals(30, SetFacts.holdTarget(short, hold, set = 1, declared = null),
                     "a shortfall carries forward, as it always did")
    }

    /** A declaration stands in for the plan, on every set of the exercise —
     *  one tap buys the whole movement, and the sets after the first run with
     *  nobody at the phone to re-enter anything. */
    @Test
    fun aDeclarationGovernsEverySetOfTheExercise() {
        for (set in 0 until hold.sets) {
            assertEquals(60, SetFacts.holdTarget(emptyMap(), hold, set = set, declared = 60))
        }
    }

    /** …but a set that was CUT SHORT still speaks: the sets after it follow
     *  what was shown, capped by what was declared. Aiming at 60 and managing
     *  50 does not put 60 back on the clock. */
    @Test
    fun aSetCutShortGovernsTheSetsAfterIt() {
        val facts = SetFacts.recording(50, emptyMap(), hold, set = 0)
        assertEquals(50, SetFacts.holdTarget(facts, hold, set = 1, declared = 60))
        assertEquals(60, SetFacts.holdTarget(facts, hold, set = 0, declared = 60),
                     "the set that was cut short is not re-shortened by itself")
    }

    /** A declaration BELOW the plan means what it says. Doing less than
     *  planned is a decision somebody is entitled to take, and it must not be
     *  quietly lifted back onto the plan. */
    @Test
    fun aDeclarationBelowThePlanIsHonoured() {
        assertEquals(20, SetFacts.holdTarget(emptyMap(), hold, set = 0, declared = 20))
    }

    /** It is carried in the workout snapshot, so it is clamped where it is
     *  read — like every other number that comes back off disk. */
    @Test
    fun aDeclarationOffDiskIsHeldInsideTheCorridor() {
        val corridor = SetFacts.corridor(LoadUnit.hold)
        assertEquals(corridor.last, SetFacts.holdTarget(emptyMap(), hold, set = 0, declared = 9_000))
        assertEquals(corridor.first, SetFacts.holdTarget(emptyMap(), hold, set = 0, declared = -5))
    }

    // MARK: - The set the run opens by itself

    /** One tap buys the exercise, and every working set of it after the first
     *  starts on the go of the rest before it. The predicate is asked by TWO
     *  callers that have to agree — the advance that starts the set, and the
     *  rest screen that offers a pause because it will. */
    @Test
    fun theRunOpensEveryWorkingSetOfTheHoldItIsRunning() {
        for (index in 0 until hold.sets) {
            assertTrue(SetFacts.runOpensSet(index, of = hold, running = true),
                       "set $index of a running hold")
        }
    }

    @Test
    fun nothingIsOpenedWhileNoRunIsOn() {
        // The flag is the tap: without it every set waits to be started, and
        // the next MOVEMENT is a decision of its own either way.
        for (index in 0 until hold.sets) {
            assertFalse(SetFacts.runOpensSet(index, of = hold, running = false))
        }
    }

    @Test
    fun aRepsExerciseIsNeverOpenedByAClock() {
        // Reps are counted by the person, so the clock has nothing to start:
        // "Done" is what ends a set of them.
        for (index in 0 until reps.sets) {
            assertFalse(SetFacts.runOpensSet(index, of = reps, running = true))
        }
    }

    /** The probe is one set of a movement nobody has done, possibly in
     *  another unit — the run never drops anyone into it. */
    @Test
    fun theProbeIsNeverOpenedByTheRun() {
        val probing = holdWithProbe()
        for (index in 0 until probing.sets) {
            assertTrue(SetFacts.runOpensSet(index, of = probing, running = true),
                       "the working sets before a probe still run themselves")
        }
        assertFalse(SetFacts.runOpensSet(probing.sets, of = probing, running = true),
                    "the probe is the one set that waits for a tap")
    }

    /** Indices come off `setIndex + 1` on the rest screen, so the set past the
     *  last one is asked about on every last rest of every hold exercise. */
    @Test
    fun aSetOutsideTheExerciseOpensNothing() {
        assertFalse(SetFacts.runOpensSet(hold.sets, of = hold, running = true))
        assertFalse(SetFacts.runOpensSet(-1, of = hold, running = true))
    }

    // MARK: - Who still owes the count-in

    /** A rest that ran out under the person's eyes IS the count-in, and laying
     *  a second one on top of it would be a defect. */
    @Test
    fun aRestThatRanOutHandsOverWithNoCountIn() {
        assertFalse(SetFacts.restHandsOverWithCountIn(endedByTap = false, overshootSec = 0.0))
        assertFalse(SetFacts.restHandsOverWithCountIn(endedByTap = false, overshootSec = 1.0))
    }

    @Test
    fun aTapStillEarnsTheBeat() {
        // Skip rest is somebody saying they are ready; the hold must not land
        // under the thumb that said it.
        assertTrue(SetFacts.restHandsOverWithCountIn(endedByTap = true, overshootSec = 0.0))
    }

    /** A go played to a locked phone cannot be what started a plank. The app
     *  is suspended across the end of the rest, comes back to find it over,
     *  and owes the beat it never sounded. */
    @Test
    fun aGoTheAppCouldNotSoundStillOwesTheBeat() {
        assertFalse(SetFacts.restHandsOverWithCountIn(
            endedByTap = false, overshootSec = SetFacts.restGoHeardWithinSec))
        assertTrue(SetFacts.restHandsOverWithCountIn(
            endedByTap = false, overshootSec = SetFacts.restGoHeardWithinSec + 0.5))
        assertTrue(SetFacts.restHandsOverWithCountIn(endedByTap = false, overshootSec = 600.0))
    }

    // MARK: - Helpers

    /** The same hold with a probe on the end. BUILT rather than generated: the
     *  rule reads the shape — the sets, the unit and whether a probe hangs off
     *  it — and building it says exactly which of those this is about. */
    private fun holdWithProbe(): SessionExercise =
        SessionExercise(pattern = hold.pattern, name = hold.name, variation = hold.variation,
                        unit = hold.unit, load = hold.load, perSide = hold.perSide,
                        sets = hold.sets, restSetSec = hold.restSetSec,
                        restExerciseSec = hold.restExerciseSec, loads = hold.loads,
                        probe = SessionProbe(variation = hold.variation + 1,
                                             name = "the rung above",
                                             unit = LoadUnit.hold, load = hold.load, perSide = false))

    /** An uneven plan, built the way the engine builds one: a sub-step is one
     *  rung split across the sets, so the top set stands one above the rest.
     *
     *  Off a CLEAN state, not this suite's: the sub-step is disabled on the
     *  top rung of a grid, which is exactly where `setUp` puts
     *  everything, so an uneven plan cannot be built there at all. */
    private fun unevenReps(): SessionExercise? = uneven(reps.pattern)

    /** The same shape on a hold — 20-15-15 s off the initial state, the shape
     *  of the 35-30-30 in `aHoldRunExactlyToAnUnevenPlanSaysNothing`. */
    private fun unevenHold(): SessionExercise? = uneven(hold.pattern)

    private fun uneven(pattern: Pattern): SessionExercise? {
        val state = EngineState.initial
        state.counter = 1
        state.sub[pattern] = 1
        val session = Engine.generateSession(state)
        val ex = session.exercises.firstOrNull { it.pattern == pattern } ?: return null
        val loads = ex.loads ?: return null
        return if (loads.toSet().size > 1) ex else null
    }

    /** One rep, or FIVE seconds: a hold is set on the grid it is planned on,
     *  and a number off the grid — the clock's 38 — lands on the next line in
     *  the tapped direction. The corridor, not the step, is the floor. */
    @Test
    fun theHoldPanelStepsByFiveOntoTheGrid() {
        assertEquals(35, AdjustPanel.holdStep(30, +1))
        assertEquals(25, AdjustPanel.holdStep(30, -1))
        assertEquals(40, AdjustPanel.holdStep(38, +1))
        assertEquals(35, AdjustPanel.holdStep(38, -1))
        assertEquals(0, AdjustPanel.holdStep(5, -1), "the corridor, not the step, is the floor")
        // The tap the panel takes clamps to that corridor.
        assertEquals(5, AdjustPanel.bump(5, -1, LoadUnit.hold, SetFacts.corridor(LoadUnit.hold)))
        assertEquals(11, AdjustPanel.bump(10, +1, LoadUnit.reps, SetFacts.corridor(LoadUnit.reps)))
    }
}
