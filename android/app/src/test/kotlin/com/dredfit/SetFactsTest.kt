//
//  Port of ios/DredfitTests/SetFactsTests.swift: a fact belongs to the set
//  it happened on — how a set's number is read, written, carried and folded
//  into the one number the engine takes.
//
//  Every test is ported. Swift's `Int.max` is `Int.MAX_VALUE` here: the
//  decoder saturates a value past 32 bits (core/SwiftJson.kt), and the
//  hostile record's `sets` reads back as that.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.applyFeedback
import com.dredfit.core.generateSession
import com.dredfit.workout.SetFacts
import kotlinx.serialization.json.Json
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class SetFactsTest {

    private companion object {
        /** Everything at the ceiling of its first variation: 3×15 reps and
         *  3×45 s, the plan the arithmetic below is written against. Sessions
         *  come from the engine: a hand-built one would be a plan the app
         *  never shows. */
        const val PLAN_DOSE = 15
    }

    private val state = EngineState.initial
    private lateinit var session: Session
    /** The plan of 3×15 reps. */
    private lateinit var reps: SessionExercise
    /** The plan of 3×45 seconds. */
    private lateinit var hold: SessionExercise

    @BeforeTest
    fun setUp() {
        for (p in Pattern.allCases) {
            state.doses[p] = Dose.grid(Library.unit(p, 1)).max
            // A ceiling offers a PROBE, and a probe would change what
            // "the last set" of these exercises even is. "Hard" was said, so
            // the plan here is three working sets and nothing else.
            state.lastHard.add(p)
        }
        // The second session, not the first: the rotation puts no hold in
        // session one, and half of what is being tested here is a hold.
        state.counter = 1
        session = Engine.generateSession(state)
        reps = assertNotNull(session.exercises.firstOrNull { it.unit == LoadUnit.reps })
        hold = assertNotNull(session.exercises.firstOrNull { it.unit == LoadUnit.hold })
        // The plan is checked against what the generator produced, not
        // assumed: if the generator ever moves, these fail here rather than
        // silently testing arithmetic about some other plan.
        assertEquals(listOf(1, 3, PLAN_DOSE), listOf(reps.variation, reps.sets, reps.load))
        assertEquals(listOf(1, 3, 45), listOf(hold.variation, hold.sets, hold.load))
        assertNull(reps.probe)
        assertNull(hold.probe)
    }

    // MARK: - Nothing said

    @Test
    fun noFactsRunToPlan() {
        assertEquals(15, SetFacts.inForce(emptyMap(), reps, set = 0))
        assertEquals(15, SetFacts.inForce(emptyMap(), reps, set = 2))
        assertEquals(listOf(15, 15, 15), SetFacts.allSets(emptyMap(), reps))
        assertNull(SetFacts.override(emptyMap(), reps, skipping = emptySet()))
        assertEquals(emptyMap(), SetFacts.overrides(emptyMap(), skipping = emptyMap(), exercises = listOf(reps, hold)))
    }

    // MARK: - The reported bug

    /**
     * The whole reason this shape exists: 10 entered on the LAST set of
     * 3×15 must leave the two sets already done at 15.
     *
     * The mean of 15-15-10 is 13⅓, and the fraction is what travels: it is
     * the only thing that tells "took the top set of an uneven plan" apart
     * from "did not". Rounded here, the engine would have to substitute the
     * plan's top into the journal instead — a dose that was in none of the
     * sets. The integer is what gets STORED, one step later, so the second
     * assert keeps 13 where it belongs.
     */
    @Test
    fun aFactOnTheLastSetLeavesTheEarlierOnesAlone() {
        val facts = SetFacts.recording(10, emptyMap(), reps, set = 2)
        assertEquals(listOf(15, 15, 10), SetFacts.allSets(facts, reps))
        val mean = assertNotNull(SetFacts.override(facts, reps, skipping = emptySet()))
        assertEquals(40.0 / 3.0, mean, 1e-9, "the fraction reaches the engine")
        assertEquals(13, SetFacts.snap(mean, reps.unit), "and an integer is stored")
    }

    /** The same for a hold stopped early — the path that records itself with
     *  no tap at all. Stopping at 30 s of 45 in the third set reports the
     *  mean of 40, not the 30. */
    @Test
    fun aHoldStoppedEarlyOnTheLastSetReportsTheMean() {
        val facts = SetFacts.recording(SetFacts.snap(30.0, LoadUnit.hold), emptyMap(), hold, set = 2)
        assertEquals(listOf(45, 45, 30), SetFacts.allSets(facts, hold))
        assertEquals(40.0, SetFacts.override(facts, hold, skipping = emptySet()))
    }

    /** What the mean is worth, stated as the engine sees it: a bare 10 would
     *  drop the dose five rungs; the mean drops it two, and the streak still
     *  has room. */
    @Test
    fun theEngineDropsLessAndDeloadsLater() {
        val p = reps.pattern
        val facts = SetFacts.recording(10, emptyMap(), reps, set = 2)
        val mean = assertNotNull(SetFacts.override(facts, reps, skipping = emptySet()))
        val fixed = Engine.applyFeedback(state = state, session = session,
                                         result = FeedbackResult.plan, overrides = mapOf(p to mean))
        val old = Engine.applyFeedback(state = state, session = session,
                                       result = FeedbackResult.plan, overrides = mapOf(p to 10.0))

        // The mean of 15/15/10 lands as 13; a flat 10 is the shape the mean
        // replaces. The next showing IS the number reported.
        assertEquals(10, old.doses[p], "the shape this fix replaces")
        assertEquals(13, fixed.doses[p], "two sets on plan are not a full shortfall")
        assertEquals(1, fixed.failStreak[p])
    }

    // MARK: - Carrying forward

    /** A number entered on the first set is what the screen then shows and
     *  what the hold then counts down, so it IS what the later sets ran at. */
    @Test
    fun aFactOnTheFirstSetCarriesForward() {
        val facts = SetFacts.recording(10, emptyMap(), reps, set = 0)
        assertEquals(listOf(10, 10, 10), SetFacts.allSets(facts, reps))
        assertEquals(10.0, SetFacts.override(facts, reps, skipping = emptySet()))
    }

    @Test
    fun theSecondFactOverridesOnlyFromItsOwnSet() {
        var facts = SetFacts.recording(12, emptyMap(), reps, set = 0)
        facts = SetFacts.recording(9, facts, reps, set = 2)
        assertEquals(listOf(12, 12, 9), SetFacts.allSets(facts, reps))
        assertEquals(11.0, SetFacts.override(facts, reps, skipping = emptySet()))
    }

    /** Correcting the set under way, twice, must not lengthen the record. */
    @Test
    fun rewritingTheSameSetReplacesIt() {
        var facts = SetFacts.recording(10, emptyMap(), reps, set = 1)
        facts = SetFacts.recording(12, facts, reps, set = 1)
        assertEquals(listOf(15, 12, 12), SetFacts.allSets(facts, reps))
    }

    // MARK: - Back to the plan

    @Test
    fun everythingBackOnPlanIsNothingSaid() {
        var facts = SetFacts.recording(10, emptyMap(), reps, set = 0)
        facts = SetFacts.recording(15, facts, reps, set = 0)
        assertNull(facts[reps.pattern], "the rating governs the pattern again")
        assertNull(SetFacts.override(facts, reps, skipping = emptySet()))
    }

    /**
     * One set corrected back while another still differs is still a fact.
     *
     * 10-10-15 means 11⅔. What the test is about is the DIRECTION — this fell
     * short of the plan — so that is asserted in its own right rather than
     * left to be read off a rounded number.
     */
    @Test
    fun onePlanSetAmongOthersIsStillAFact() {
        var facts = SetFacts.recording(10, emptyMap(), reps, set = 0)
        facts = SetFacts.recording(15, facts, reps, set = 2)
        assertEquals(listOf(10, 10, 15), SetFacts.allSets(facts, reps))
        val mean = assertNotNull(SetFacts.override(facts, reps, skipping = emptySet()))
        assertEquals(35.0 / 3.0, mean, 1e-9)
        assertTrue(mean < reps.load.toDouble(), "and it is still short of the plan")
    }

    /**
     * A shortfall must never be reported as MEETING the plan. On the
     * one-second reporting grid the near miss that still snaps onto the plan
     * is 44 s of a 3×45 s plan — mean 44⅔. Rounded up to 45 it would read to
     * the engine as the plan met; handed over raw it misses `metPlan`, which
     * compares the raw value, and the engine snaps a fact DOWN to its grid —
     * one second short would cost the plan a whole rung, 45 s to 40. So the
     * collapse reports nothing, and the session rating governs.
     */
    @Test
    fun aNearMissIsNeverRoundedUpOntoThePlan() {
        val facts = SetFacts.recording(44, emptyMap(), hold, set = 2)
        assertEquals(listOf(45, 45, 44), SetFacts.allSets(facts, hold),
                     "the sets themselves are still recorded and shown")
        assertNull(SetFacts.override(facts, hold, skipping = emptySet()),
                   "44.7 s snaps to 45 — below the plan must not report as on it")

        val repsFacts = SetFacts.recording(reps.load - 1, emptyMap(), reps, set = 2)
        assertNull(SetFacts.override(repsFacts, reps, skipping = emptySet()), "the same on the reps grid")
    }

    /**
     * The rule is about the DIRECTION, not the landing: a mean at or above
     * the plan that snaps onto it is an honest "on plan" fact.
     *
     * The mean is 45⅓ and travels as 45⅓; what the rule is about is that it
     * is not BELOW the plan, so that is what the second assert says.
     */
    @Test
    fun aMeanAtOrAboveThePlanStillReportsIt() {
        val facts = SetFacts.recording(hold.load + 1, emptyMap(), hold, set = 2)
        assertEquals(listOf(45, 45, 46), SetFacts.allSets(facts, hold))
        val mean = assertNotNull(SetFacts.override(facts, hold, skipping = emptySet()))
        assertEquals(136.0 / 3.0, mean, 1e-9)
        assertTrue(mean >= hold.load.toDouble(), "the athlete did not fall short")
    }

    /** The safety property this protects: a shortfall must not claim the
     *  plan. A third set that fell short is not proof the plan was met, and
     *  the position must not rise off the back of it. */
    @Test
    fun aShortfallCannotClaimThePlan() {
        val p = hold.pattern
        val facts = SetFacts.recording(38, emptyMap(), hold, set = 2)
        val overrides = SetFacts.overrides(facts, skipping = emptyMap(), exercises = session.exercises)

        // The guard lives in the COLLAPSE, which is where it is enforced: a
        // mean that falls short is never reported as meeting the plan, however
        // close it lands. The engine reads one number per movement, so this is
        // the only place the claim can be made or lost.
        // Saying NOTHING is a correct answer here and the strongest one: when
        // the grid cannot hold the mean below the plan without over-penalising
        // a near miss, the collapse stays silent and the session rating speaks
        // instead. What it may never do is come back equal to the plan.
        // The collapse hands over the RAW mean, a Double, and the engine puts
        // it on the grid. The comparison is in the same units: a shortfall
        // cannot be reported as the plan done.
        assertNotEquals(hold.load.toDouble(), overrides[p],
                        "a short third set must not be reported as the plan")
        overrides[p]?.let { reported ->
            assertTrue(reported < hold.load.toDouble(), "and never above it either")
        }
    }

    // MARK: - The grid

    /** The reporting grid for holds is one second, finer than the five-second
     *  grid the plan is set on. */
    @Test
    fun holdsSnapToTheSecondAndRepsToOne() {
        assertEquals(52, SetFacts.snap(51.67, LoadUnit.hold))
        assertEquals(53, SetFacts.snap(53.0, LoadUnit.hold))
        assertEquals(13, SetFacts.snap(13.33, LoadUnit.reps))
        assertEquals(14, SetFacts.snap(13.5, LoadUnit.reps))
    }

    @Test
    fun theCorridorsHold() {
        assertEquals(5, SetFacts.snap(3.0, LoadUnit.hold))
        assertEquals(90, SetFacts.snap(400.0, LoadUnit.hold))
        assertEquals(0, SetFacts.snap(-4.0, LoadUnit.reps))
        assertEquals(30, SetFacts.snap(99.0, LoadUnit.reps))
        assertEquals(0, SetFacts.snap(Double.NaN, LoadUnit.reps))
    }

    /** Reached from a snapshot off disk, so no magnitude may trap the
     *  conversion to Int. */
    @Test
    fun noDoubleCanTrapTheSnap() {
        assertEquals(90, SetFacts.snap(1e300, LoadUnit.hold))
        assertEquals(5, SetFacts.snap(-1e300, LoadUnit.hold))
        assertEquals(0, SetFacts.snap(Double.POSITIVE_INFINITY, LoadUnit.reps))
        assertEquals(30, SetFacts.snap(Long.MAX_VALUE.toDouble(), LoadUnit.reps))
    }

    // MARK: - Read back off disk

    /** A workout snapshot carries no decoder of its own, so what it hands
     *  back is sanitized where it is read. */
    @Test
    fun factsOffDiskAreClampedAndCut() {
        val dirty: Map<Pattern, List<Int>> = mapOf(
            reps.pattern to listOf(15, -7, Int.MAX_VALUE, 12, 9, 9, 9, 9),
            hold.pattern to emptyList(),
        )
        val clean = SetFacts.sanitized(dirty)
        assertEquals(listOf(15, 0, EngineConfig.countMax, 12, 9), clean[reps.pattern],
                     "cut to the sets an exercise can have, every value inside its range")
        assertNull(clean[hold.pattern], "an entry holding no sets is not an entry")
    }

    /** `sets` comes back out of the journal unclamped — `SessionExercise` has
     *  no sanitizing decoder — and this walk runs on the main thread inside a
     *  history row. Sizing an allocation from it would let one hand-edited
     *  record take the app down; the same hostile value the journal tests
     *  already use is the input here. */
    @Test
    fun theSetWalkIsBoundedByTheScaleNotTheRecord() {
        val hostile = SessionExercise.fromJson(Json.parseToJsonElement("""
        {"pattern":"squat","name":"x","tier":1,"unit":"reps","load":15,
         "perSide":false,"sets":9223372036854775807,
         "restSetSec":60,"restExerciseSec":60}
        """))
        assertEquals(Int.MAX_VALUE, hostile.sets, "the record really is unclamped")

        val facts = SetFacts.recording(10, emptyMap(), hostile, set = 0)
        assertEquals(listOf(10, 10, 10, 10, 10), SetFacts.allSets(facts, hostile),
                     "the walk stops at the scale's ceiling, not the record's claim")
        assertEquals(10.0, SetFacts.override(facts, hostile, skipping = emptySet()))
    }

    // MARK: - The whole session

    /**
     * The hold's 46 is ABOVE its plan of 45, entered on the FIRST set. The
     * carry is asymmetric: a surplus stays on its own set, so the hold runs
     * 46, 45, 45 and its mean is 45⅓. A symmetric carry would rewrite sets
     * two and three to 46 as well — the app claiming three sets of 46 on the
     * strength of one.
     *
     * The reps side is the control: its 10 is BELOW the plan and on the last
     * set, so the carry has nothing to decide there — 15, 15, 10, mean 13⅓.
     */
    @Test
    fun overridesCoverOnlyWhatWasSaid() {
        var facts = SetFacts.recording(10, emptyMap(), reps, set = 2)
        facts = SetFacts.recording(46, facts, hold, set = 0)
        val overrides = SetFacts.overrides(facts, skipping = emptyMap(), exercises = session.exercises)
        assertEquals(setOf(reps.pattern, hold.pattern), overrides.keys,
                     "every other exercise of the session ran to plan")
        assertEquals(40.0 / 3.0, assertNotNull(overrides[reps.pattern]), 1e-9)
        assertEquals(136.0 / 3.0, assertNotNull(overrides[hold.pattern]), 1e-9)
    }

    // MARK: - The probe set

    /** A probe tapped through on a plain "Done" counts as its target — "tapped
     *  Done" means "did as asked" everywhere in the app. If it recorded
     *  nothing, a probe in reps could only be resolved through the adjust
     *  panel, and anyone who simply taps would never enter a new variation. */
    @Test
    fun tappingThroughAProbeRecordsItsTarget() {
        val probes = SetFacts.recordingProbe(emptyMap(), reps.pattern, isProbe = true, target = 5)
        assertEquals(5, probes[reps.pattern], "a tapped probe did the target it asked for")
    }

    /** The other half, and the one a refactor is likelier to lose: nothing
     *  ELSE records itself. An ordinary set tapped through says nothing, and
     *  the session's rating governs the movement. */
    @Test
    fun anOrdinarySetStillRecordsNothing() {
        assertEquals(emptyMap(), SetFacts.recordingProbe(emptyMap(), reps.pattern, isProbe = false, target = 5),
                     "only the probe reports itself on a bare tap")
    }

    /** A number entered by hand is more precise than "as asked" and wins —
     *  including a shortfall, which is the whole point of the adjust panel. */
    @Test
    fun aNumberEnteredForTheProbeIsNotOverwritten() {
        val entered: Map<Pattern, Int> = mapOf(reps.pattern to 3)
        assertEquals(entered, SetFacts.recordingProbe(entered, reps.pattern, isProbe = true, target = 5),
                     "the panel's number outranks the target")
    }

    /** A set index past the exercise, or below it, must not trap. */
    @Test
    fun indicesOutsideTheExerciseAreClamped() {
        val facts = SetFacts.recording(10, emptyMap(), reps, set = 2)
        assertEquals(10, SetFacts.inForce(facts, reps, set = 99))
        assertEquals(15, SetFacts.inForce(facts, reps, set = -1))
    }

    // MARK: - The carry-forward is asymmetric

    /** BELOW the plan carries forward: someone who managed six of eight is
     *  telling you about the exercise, not about one set of it. */
    @Test
    fun aNumberBelowThePlanStillCarriesForward() {
        val facts = SetFacts.recording(6, emptyMap(), reps, set = 0)
        assertEquals(6, SetFacts.inForce(facts, reps, set = 0))
        assertEquals(6, SetFacts.inForce(facts, reps, set = 1), "set two follows it down")
        assertEquals(6, SetFacts.inForce(facts, reps, set = 2), "and so does set three")
    }

    /** ABOVE the plan does NOT. Carried, it would rewrite the sets ahead
     *  silently — 12 on the first set of 3×15 is not a promise about the next
     *  two — and the person would have to argue with the screen twice. */
    @Test
    fun aNumberAboveThePlanStaysOnItsOwnSet() {
        val above = reps.plannedLoad(set = 0) + 4
        val facts = SetFacts.recording(above, emptyMap(), reps, set = 0)
        assertEquals(above, SetFacts.inForce(facts, reps, set = 0), "its own set keeps it")
        assertEquals(reps.plannedLoad(set = 1), SetFacts.inForce(facts, reps, set = 1),
                     "set two is back on the plan")
        assertEquals(reps.plannedLoad(set = 2), SetFacts.inForce(facts, reps, set = 2),
                     "and so is set three")
    }

    /**
     * On every trajectory that never exceeds the plan, the carry is the plain
     * one and the engine is handed the mean of the sets that ran — or
     * nothing, when every set ran on plan or the mean is a near miss that
     * snaps back onto it. The asymmetry may only ever touch the above-plan
     * case, so this walks every set of every exercise at every value from
     * zero to the plan.
     *
     * Both expected values are computed here, from the trajectory, not from
     * `SetFacts.inForce` — the very function `allSets` is a map over — or
     * from a second call of `SetFacts.overrides`: either way the sweep would
     * be `f(x) == f(x)` and could not fail. Whether the engine is expected to
     * get the mean or nothing is read off the record and `SetFacts.snap`.
     */
    @Test
    fun nothingBelowThePlan_atEverySetAndValue_reachesTheEngineUnchanged() {
        for (ex in session.exercises) {
            // Spelling the expectation out per set is only legitimate on a
            // UNIFORM plan: `setUp` puts no sub-step in the state, so every set
            // asks for the same dose. An uneven plan would need the carry's own
            // fill rule, which is what made reading it back off `inForce`
            // tempting in the first place.
            assertNull(ex.loads, "${ex.pattern}: the sweep assumes a uniform plan")
            for (set in 0 until ex.sets) {
                for (value in 0..ex.plannedLoad(set = set)) {
                    val facts = SetFacts.recording(value, emptyMap(), ex, set = set)
                    // Below the plan the carry is the plain one: the
                    // sets before ran silently on plan, the set itself ran at
                    // `value`, and `value <= planned` carries onto every set
                    // after it (`min(last, planned) == last`).
                    val expected = (0 until ex.sets).map { index ->
                        if (index < set) ex.plannedLoad(set = index) else value
                    }
                    assertEquals(expected, SetFacts.allSets(facts, ex),
                                 "${ex.pattern} set $set at $value: the carry moved")

                    // And the collapse is the mean of exactly those sets —
                    // counted here, never asked for a second time.
                    val mean = expected.sum().toDouble() / expected.size.toDouble()
                    val overrides = SetFacts.overrides(facts, skipping = emptyMap(), exercises = session.exercises)
                    // Two ways to report nothing, both correct: every set landed
                    // on the plan, so there is no fact at all; or the mean falls
                    // short of the plan yet snaps back onto it, and a shortfall
                    // must never be reported as MEETING the plan.
                    val nearMiss = mean < ex.load.toDouble() &&
                        SetFacts.snap(mean, ex.unit) >= ex.load
                    if (facts[ex.pattern] == null || nearMiss) {
                        assertNull(overrides[ex.pattern],
                                   "${ex.pattern} set $set at $value: " +
                                       "nothing was said, so nothing may be reported")
                    } else {
                        assertEquals(mean, assertNotNull(overrides[ex.pattern]), 1e-9,
                                     "${ex.pattern} set $set at $value: " +
                                         "the engine is handed the mean of the sets that ran")
                    }
                }
            }
        }
    }

    /** The order of sets does NOT reach the engine — the fact the warning's
     *  wording is forbidden from contradicting. 12, 8, 8 and 8, 8, 12
     *  collapse to the same number. */
    @Test
    fun theOrderOfSetsDoesNotReachTheEngine() {
        var early: Map<Pattern, List<Int>> = emptyMap()
        early = SetFacts.recording(reps.plannedLoad(set = 0) + 4, early, reps, set = 0)
        early = SetFacts.recording(reps.plannedLoad(set = 1) - 4, early, reps, set = 1)
        early = SetFacts.recording(reps.plannedLoad(set = 2) - 4, early, reps, set = 2)

        var late: Map<Pattern, List<Int>> = emptyMap()
        late = SetFacts.recording(reps.plannedLoad(set = 0) - 4, late, reps, set = 0)
        late = SetFacts.recording(reps.plannedLoad(set = 1) - 4, late, reps, set = 1)
        late = SetFacts.recording(reps.plannedLoad(set = 2) + 4, late, reps, set = 2)

        assertEquals(SetFacts.overrides(late, skipping = emptyMap(), exercises = session.exercises)[reps.pattern],
                     SetFacts.overrides(early, skipping = emptyMap(), exercises = session.exercises)[reps.pattern],
                     "under a mean the order cannot change what the engine sees")
    }

    // MARK: - "The whole plan, or more" (the gate on the "easy" rating)

    private fun didFullPlan(facts: Map<Pattern, List<Int>> = emptyMap(),
                            skips: Map<Pattern, Int> = emptyMap(),
                            skipped: Set<Pattern> = emptySet()): Boolean =
        SetFacts.didFullPlan(facts, skips = skips, skipped = skipped, exercises = session.exercises)

    @Test
    fun sayingNothingIsTheWholePlan() {
        // The convention the whole app rests on: a tap through means the plan
        // was done. Nothing recorded is therefore the passing case, not the
        // failing one — a gate that read silence as a shortfall would dim the
        // card for everyone who never opens the adjuster.
        assertTrue(didFullPlan())
    }

    @Test
    fun aNumberAbovePlanIsStillTheWholePlan() {
        val facts = SetFacts.recording(PLAN_DOSE + 3, emptyMap(), reps, set = 0)
        assertTrue(didFullPlan(facts), "“or more” has to mean more")
    }

    @Test
    fun oneSetUnderPlanClosesTheGate() {
        val facts = SetFacts.recording(PLAN_DOSE - 1, emptyMap(), reps, set = 2)
        assertFalse(didFullPlan(facts))
    }

    @Test
    fun aSurplusOnOneExerciseDoesNotPayForAShortfallOnAnother() {
        // Volume is judged PER EXERCISE. Fourteen extra reps of one movement
        // do not buy a missing rep of another: they are different tissues, and
        // the rating they would unlock speaks about all six at once.
        var facts = SetFacts.recording(PLAN_DOSE - 1, emptyMap(), reps, set = 0)
        facts = SetFacts.recording(hold.plannedLoad(set = 0) + 20, facts, hold, set = 0)
        assertFalse(didFullPlan(facts))
    }

    @Test
    fun aSkippedSetClosesTheGateEvenWithNothingElseSaid() {
        // The one shortfall the engine does NOT already keep the rating away
        // from: a dropped set never becomes an override, so without this the
        // tap would buy the full rise on a movement that lost a third of its
        // volume. This assertion is the whole reason the screen is handed the
        // skips at all.
        assertFalse(didFullPlan(skips = mapOf(reps.pattern to 1)))
        assertTrue(didFullPlan(skips = mapOf(reps.pattern to 0)),
                   "a count of no skipped sets is not a skip")
    }

    @Test
    fun aSkippedExerciseClosesTheGate() {
        assertFalse(didFullPlan(skipped = setOf(reps.pattern)))
    }

    @Test
    fun anUnevenPlanNeedsItsTopSet() {
        // In the gate's own terms: 9-8-8 done as written passes, and 8-8-8
        // does not. The mean would let the top set be traded against the
        // two below it — volume will not.
        // Off a CLEAN state, not this suite's: the sub-step is disabled on the
        // top rung of a grid, which is exactly where `setUp` puts
        // everything, so an uneven plan cannot be built there at all.
        val uneven = EngineState.initial
        uneven.counter = 1
        uneven.sub[reps.pattern] = 1                      // one rung split across sets
        val session = Engine.generateSession(uneven)
        val ex = session.exercises.firstOrNull { it.pattern == reps.pattern }
        val loads = ex?.loads
        if (ex == null || loads == null || loads.toSet().size <= 1) fail("the sub-step did not produce an uneven plan")
        val asWritten = (0 until ex.sets).fold(emptyMap<Pattern, List<Int>>()) { acc, set ->
            SetFacts.recording(ex.plannedLoad(set = set), acc, ex, set = set)
        }
        assertTrue(SetFacts.didFullPlan(asWritten, skips = emptyMap(), skipped = emptySet(), exercises = listOf(ex)))
        val flattened = (0 until ex.sets).fold(emptyMap<Pattern, List<Int>>()) { acc, set ->
            SetFacts.recording(assertNotNull(loads.minOrNull()), acc, ex, set = set)
        }
        assertFalse(SetFacts.didFullPlan(flattened, skips = emptyMap(), skipped = emptySet(), exercises = listOf(ex)),
                    "the top set is part of the plan")
    }
}
