//
//  What v3 added, tested where golden cannot reach: the clean start and the
//  v2 state the v3 decode refuses, the probe and its three outcomes, the entry
//  of 3×4, adaptation by honest facts, the ceiling on any assignment, and the
//  one unit boundary in the library. Port of EngineV3Tests.swift.
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EngineV3Test {

    // MARK: - Helpers

    /** A state with one pattern moved and everything else fresh. Everything
     *  the helper takes past the variation and the dose travels in `Seed`: a
     *  long list of loose parameters is a list nobody reads. */
    private data class Seed(
        val sets: Int = EngineConfig.setsBase,
        val shown: Map<Int, Int> = emptyMap(),
        val counter: Int = 0,
        val hasBar: Boolean = false,
    )

    private fun state(p: Pattern, variation: Int, dose: Int, seed: Seed = Seed()): EngineState {
        val s = EngineState.initial
        s.counter = seed.counter
        s.hasBar = seed.hasBar
        s.vars[p] = variation
        s.doses[p] = dose
        if (seed.sets != EngineConfig.setsBase) s.sets[p] = seed.sets
        if (seed.shown.isNotEmpty()) s.shown[p] = seed.shown.toMutableMap()
        return s
    }

    /** Squat on the ceiling of its first variation, ready for a probe. */
    private fun squatAtCeiling(): EngineState =
        state(Pattern.squat, variation = 1, dose = 15, seed = Seed(shown = mapOf(1 to 15)))

    private fun exercise(session: Session, p: Pattern): SessionExercise =
        assertNotNull(session.exercises.firstOrNull { it.pattern == p },
                      "${p.rawValue} is not in this session")

    // MARK: - A v2 state does not decode as v3 (it is dispatched to MigrationV2)

    /** A state written by v2 carries `levels` and no `vars`, and the decode
     *  FAILS on it. That failure is the DISPATCH: the app then reads the v2
     *  shape and migrates it (`Engine.migrateFromV2`); only a state that is
     *  neither shape starts from `initial`. */
    @Test
    fun stateFromV2FailsToDecode() {
        val v2 = """
            {"counter":42,"levels":["squat",34,"push_h",20],"failStreak":["squat",0],
             "hasBar":true,"lessRun":0,"returnRun":0,"rampWindow":0,"weekAgeDays":0}
        """.trimIndent()
        assertFailsWith<EngineStateDecodingException>(
            "a v2 state must not decode as v3 — it is dispatched to the v2 reader") {
            EngineState.decode(v2)
        }
    }

    /** And a clean start: every pattern on its first rung, 3×4 (3×15 s),
     *  nothing shown yet. */
    @Test
    fun cleanStartIsEveryPatternAtThreeByFour() {
        val session = Engine.generateSession(EngineState.initial)
        assertEquals(EngineConfig.patternsPerSession, session.exercises.size)
        for (ex in session.exercises) {
            assertEquals(1, ex.variation, "${ex.pattern.rawValue}: first rung")
            assertEquals(3, ex.sets, "${ex.pattern.rawValue}: three sets")
            assertEquals(Dose.grid(ex.unit).min, ex.load, "${ex.pattern.rawValue}: the floor")
            assertNull(ex.loads, "${ex.pattern.rawValue}: a clean start is uniform")
            assertNull(ex.probe, "${ex.pattern.rawValue}: nothing to probe from the floor")
        }
        assertTrue(EngineState.initial.shown.isEmpty())
        assertEquals(0, Engine.totalProgress(EngineState.initial))
    }

    /** A v3 state survives the round trip it is actually stored through. */
    @Test
    fun stateRoundTripsThroughCodable() {
        val s = squatAtCeiling()
        s.sets[Pattern.calf] = 3           // sparse fields written explicitly, then healed away
        s.lastHard = mutableSetOf(Pattern.pull)
        s.creditPaused = mutableSetOf(Pattern.pullBar)
        s.setsHold[Pattern.hinge] = 2
        s.weekAgeDays = 2.5
        val data = s.encode()
        val back = EngineState.decode(data)
        assertEquals(s.sanitized(), back.sanitized())
        assertEquals<Map<Int, Int>?>(mapOf(1 to 15), back.shown[Pattern.squat])
        assertEquals<Set<Pattern>>(setOf(Pattern.pull), back.lastHard)
    }

    // MARK: - The probe

    /** The probe replaces the LAST of the remaining sets: one working set
     *  fewer, one set of the next variation, and the session's volume does not
     *  grow. */
    @Test
    fun probeReplacesTheLastSetAndDoesNotGrowTheSession() {
        val session = Engine.generateSession(squatAtCeiling())
        val squat = exercise(session, Pattern.squat)
        assertEquals(2, squat.sets, "two working sets, not three")
        val probe = assertNotNull(squat.probe)
        assertEquals(2, probe.variation)
        assertEquals(4, probe.load, "the target is the floor of the grid")
        assertTrue(probe.perSide, "the split squat is trained one side at a time")
        assertEquals(Library.name(Pattern.squat, 2), probe.name)
        // Volume: 2×15 of the old plus 1×4 per side of the new, against 3×15.
        assertEquals(30, squat.plannedVolume)
    }

    /** A probe is offered only on the ceiling, only below the top variation,
     *  and only when the last answer was not "hard". */
    @Test
    fun probeConditionsAreAllThree() {
        val below = squatAtCeiling()
        below.doses[Pattern.squat] = 14
        assertNull(exercise(Engine.generateSession(below), Pattern.squat).probe,
                   "below the ceiling there is nothing to probe from")

        val top = squatAtCeiling()
        top.vars[Pattern.squat] = Library.count(Pattern.squat)
        top.doses[Pattern.squat] = 15
        assertNull(exercise(Engine.generateSession(top), Pattern.squat).probe,
                   "the top variation has nowhere to go")

        val hard = squatAtCeiling()
        hard.lastHard = mutableSetOf(Pattern.squat)
        assertNull(exercise(Engine.generateSession(hard), Pattern.squat).probe,
                   "«hard» was said and has not been unsaid")
    }

    /** Outcome one: the number came back at or above the floor — the variation
     *  changes, and the entry is ALWAYS 3×4. */
    @Test
    fun probeResolvedEntersTheNextVariationAtThreeByFour() {
        val start = squatAtCeiling()
        val session = Engine.generateSession(start)
        val after = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                         overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                         probes = mapOf(Pattern.squat to 6))
        assertEquals(2, after.vars[Pattern.squat])
        assertEquals(4, after.doses[Pattern.squat], "entry is the floor of the grid")
        assertEquals(3, after.sets[Pattern.squat] ?: EngineConfig.setsBase)
        assertEquals(0, after.sub[Pattern.squat] ?: 0)
        assertEquals(0, after.cutOf(Pattern.squat))
        // The journal records what the probe actually showed, and the old
        // variation's entry is the point of return.
        assertEquals(6, after.shown[Pattern.squat]?.get(2))
        assertEquals(15, after.shown[Pattern.squat]?.get(1))

        // And the plan that follows is 3×4 per side.
        val next = after.copy()
        next.counter = 0                     // put the squat back into session one
        val plan = exercise(Engine.generateSession(next), Pattern.squat)
        assertEquals(3, plan.sets)
        assertEquals(4, plan.load)
        assertTrue(plan.perSide)
        assertNull(plan.loads)
    }

    /** Outcome two: the number came back BELOW the floor — the variation is
     *  out of reach. Nothing moves but the journal of facts, and the
     *  appearance still counts as an ordinary one. */
    @Test
    fun probeFailedMovesNothingButTheJournal() {
        val start = squatAtCeiling()
        val session = Engine.generateSession(start)
        val after = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                         overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                         probes = mapOf(Pattern.squat to 2))
        assertEquals(1, after.vars[Pattern.squat], "still on the old variation")
        assertEquals(15, after.doses[Pattern.squat], "still on its ceiling")
        assertEquals(0, after.sub[Pattern.squat] ?: 0)
        assertEquals(2, after.shown[Pattern.squat]?.get(2), "what was shown is still recorded")
        assertFalse(after.lastHard.contains(Pattern.squat), "a failed probe is not a failure")
        // The probe comes back on the next appearance.
        val next = after.copy()
        next.counter = 0
        assertNotNull(exercise(Engine.generateSession(next), Pattern.squat).probe)
    }

    /** Outcome three: no number at all — the probe did not resolve, and
     *  nothing at all changes, the journal included. */
    @Test
    fun probeUnresolvedChangesNothing() {
        val start = squatAtCeiling()
        val session = Engine.generateSession(start)
        val after = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                         overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                         probes = emptyMap())
        assertEquals(1, after.vars[Pattern.squat])
        assertEquals(15, after.doses[Pattern.squat])
        assertNull(after.shown[Pattern.squat]?.get(2))
        assertEquals(15, after.shown[Pattern.squat]?.get(1), "the journal of the OLD variation is untouched")
    }

    /** A "hard" answer on the movement is ordinary "hard" handling, and the
     *  probe of that session does not count even with a number reported. */
    @Test
    fun probeIsNotCountedWhenTheMovementWasHard() {
        val start = squatAtCeiling()
        val session = Engine.generateSession(start)
        val after = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                         overrides = mapOf(Pattern.squat to 9.0), skipped = emptySet(),
                                         gapDays = null, probes = mapOf(Pattern.squat to 12))
        assertEquals(1, after.vars[Pattern.squat], "the probe is not counted")
        assertEquals(9, after.doses[Pattern.squat], "the honest number set the dose")
        assertNull(after.shown[Pattern.squat]?.get(2), "and nothing was recorded for the new variation")
        assertTrue(after.lastHard.contains(Pattern.squat))
    }

    /** A skipped exercise resolves nothing: the pattern was not trained. */
    @Test
    fun skippedExerciseResolvesNoProbe() {
        val start = squatAtCeiling()
        val session = Engine.generateSession(start)
        val after = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                         overrides = emptyMap(), skipped = setOf(Pattern.squat),
                                         gapDays = null, probes = mapOf(Pattern.squat to 12))
        assertEquals(1, after.vars[Pattern.squat])
        assertNull(after.shown[Pattern.squat]?.get(2))
    }

    // MARK: - Honest numbers, both ways

    /** A fact ABOVE the plan sets the next dose to what was shown — not to
     *  "plan + 1". This is the one mechanism that walks a person back to their
     *  own level after a clean start, and `maxUp` does not bound it. */
    @Test
    fun factAbovePlanAdoptsWhatWasShown() {
        val start = EngineState.initial
        val session = Engine.generateSession(start)
        val after = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                         overrides = mapOf(Pattern.squat to 12.0), skipped = emptySet(),
                                         gapDays = null, probes = emptyMap())
        assertEquals(12, after.doses[Pattern.squat])
        assertEquals(0, after.sub[Pattern.squat] ?: 0)
        assertEquals(12, after.shown[Pattern.squat]?.get(1))
        assertEquals(1, after.vars[Pattern.squat], "a fact can never jump a variation")
    }

    /** A fact BELOW the floor of the variation sends the pattern one variation
     *  down, landing under the journal — not on the floor of a tier, because
     *  there are no tier floors.
     *
     *  The journal's 11 is a CEILING, not the landing. The trainee is leaving
     *  "Bulgarian split squats" at 3×8 per side — work 48; landing on 3×11
     *  would be 66, a 37.5 % rise straight after they showed a fact below the
     *  variation's floor. The landing walks down and stops at 8: work 48,
     *  exactly what they were doing. */
    @Test
    fun factBelowTheFloorLandsNoHeavier() {
        val start = state(Pattern.squat, variation = 3, dose = 8,
                          seed = Seed(shown = mapOf(2 to 11, 3 to 8)))
        val session = Engine.generateSession(start)
        val after = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                         overrides = mapOf(Pattern.squat to 2.0), skipped = emptySet(),
                                         gapDays = null, probes = emptyMap())
        assertEquals(2, after.vars[Pattern.squat])
        assertEquals(8, after.doses[Pattern.squat], "the point of return, but never heavier")
        assertTrue(Engine.noHarder(Pattern.squat, from = start.position(Pattern.squat),
                                   to = after.position(Pattern.squat), shown = start.shown),
                   "a descent may not add work")
        assertEquals(3, after.sets[Pattern.squat] ?: EngineConfig.setsBase)
        assertTrue(after.lastHard.contains(Pattern.squat))
    }

    /** Two appearances per variation is what the walk back costs, and here it
     *  is: floor → own numbers → ceiling → probe. */
    @Test
    fun walkingBackTakesTwoAppearancesPerVariation() {
        var s = EngineState.initial
        var appearances = 0
        // Appearance 1: the plan is 3×4, the person does 20.
        while (s.vars[Pattern.squat] != 3 && appearances < 8) {
            val session = Engine.generateSession(s)
            val squat = session.exercises.firstOrNull { it.pattern == Pattern.squat }
            if (squat == null) {
                s.counter += 1
                continue
            }
            appearances += 1
            val overrides = mutableMapOf<Pattern, Double>()
            val probes = mutableMapOf<Pattern, Int>()
            if (squat.probe != null) {
                probes[Pattern.squat] = 20         // the new variation is comfortably there
            } else {
                overrides[Pattern.squat] = 20.0    // an honest number well above the plan
            }
            s = Engine.applyFeedback(state = s, session = session, result = FeedbackResult.plan,
                                     overrides = overrides, skipped = emptySet(), gapDays = null,
                                     probes = probes)
        }
        assertEquals(3, s.vars[Pattern.squat], "the Bulgarian split squat")
        assertEquals(4, appearances, "two appearances per variation, four to the Bulgarian split squat")
    }

    // MARK: - Nothing is ever assigned that was not shown

    /** The ceiling on every assignment, swept over a long mixed trajectory:
     *  the highest dose in any plan is at most one rung above the journal of
     *  the variation it belongs to. */
    @Test
    fun assignedDoseNeverExceedsWhatWasShownPlusOneRung() {
        var s = EngineState.initial
        s.hasBar = true
        val answers = listOf(FeedbackResult.plan, FeedbackResult.more, FeedbackResult.plan,
                             FeedbackResult.plan, FeedbackResult.more, FeedbackResult.less,
                             FeedbackResult.plan, FeedbackResult.more)
        for (step in 0 until 120) {
            val session = Engine.generateSession(s)
            for (ex in session.exercises) {
                val journal = s.shown[ex.pattern]?.get(ex.variation) ?: Dose.grid(ex.unit).min
                val top = ex.load + (if (ex.loads?.any { it > ex.load } == true) Dose.grid(ex.unit).step else 0)
                assertTrue(top <= journal + Dose.grid(ex.unit).step,
                           "step $step ${ex.pattern.rawValue} v${ex.variation}: " +
                               "assigned $top against a journal of $journal")
                assertTrue(ex.sets >= EngineConfig.setsFloor)
            }
            val probes = mutableMapOf<Pattern, Int>()
            for (ex in session.exercises) {
                val probe = ex.probe ?: continue
                probes[ex.pattern] = Dose.grid(probe.unit).min
            }
            s = Engine.applyFeedback(state = s, session = session,
                                     result = answers[step % answers.size],
                                     overrides = emptyMap(), skipped = emptySet(),
                                     gapDays = 7.0 / 3.0, probes = probes)
        }
    }

    /** Entry into a variation is ALWAYS 3×4 (3×15 s), on every path a sweep
     *  can reach: the only door is a probe, and the probe sets the floor. */
    @Test
    fun everyVariationEntryIsThreeByTheFloor() {
        var s = EngineState.initial
        s.hasBar = true
        var entries = 0
        for (i in 0 until 200) {
            val before = s.vars.toMap()
            val session = Engine.generateSession(s)
            val probes = mutableMapOf<Pattern, Int>()
            for (ex in session.exercises) {
                val probe = ex.probe ?: continue
                probes[ex.pattern] = Dose.grid(probe.unit).min
            }
            s = Engine.applyFeedback(state = s, session = session, result = FeedbackResult.more,
                                     overrides = emptyMap(), skipped = emptySet(),
                                     gapDays = 7.0 / 3.0, probes = probes)
            for (p in Pattern.allCases) {
                val now = assertNotNull(s.vars[p])
                if (now > assertNotNull(before[p])) {
                    entries += 1
                    assertEquals(Dose.grid(Library.unit(p, now)).min, s.doses[p],
                                 "step $i ${p.rawValue}: entry at the floor")
                    assertEquals(EngineConfig.setsBase, s.sets[p] ?: EngineConfig.setsBase,
                                 "${p.rawValue}: entry on three sets")
                    assertEquals(0, s.sub[p] ?: 0, "${p.rawValue}: entry with no sub-step")
                    assertEquals(0, s.cutOf(p), "${p.rawValue}: entry with nothing cut")
                }
            }
        }
        assertTrue(entries > 20, "the sweep must actually reach some entries")
    }

    // MARK: - The one unit boundary

    /** `pull_bar` 2→3 crosses from seconds to reps. The ratio of `w` is
     *  undefined there, so the density invariant skips it and the only way
     *  across is a probe — in BOTH directions the journal keeps its own unit. */
    @Test
    fun pullBarUnitBoundaryIsCrossedByProbeOnly() {
        val entry = ExerciseLibrary.entry(Pattern.pullBar)
        assertEquals(LoadUnit.hold, entry.variation(2).unit)
        assertEquals(LoadUnit.reps, entry.variation(3).unit)
        assertTrue(entry.probeOnly(variation = 3))

        // Up: 45 s on the scapular hang, probe for 4 reps of the negative.
        val start = state(Pattern.pullBar, variation = 2, dose = 45,
                          seed = Seed(shown = mapOf(1 to 45, 2 to 45), counter = 1, hasBar = true))
        val session = Engine.generateSession(start)
        val bar = exercise(session, Pattern.pullBar)
        assertEquals(LoadUnit.hold, bar.unit)
        val probe = assertNotNull(bar.probe)
        assertEquals(LoadUnit.reps, probe.unit)
        assertEquals(4, probe.load)

        val up = Engine.applyFeedback(state = start, session = session, result = FeedbackResult.plan,
                                      overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                      probes = mapOf(Pattern.pullBar to 5))
        assertEquals(3, up.vars[Pattern.pullBar])
        assertEquals(4, up.doses[Pattern.pullBar])
        assertEquals(5, up.shown[Pattern.pullBar]?.get(3))

        // Down: an honest zero on the negative sends the branch back to the
        // hang, under the seconds the journal remembers.
        //
        // The journal's 45 s is only the ceiling, and nothing on the hold's
        // grid fits under the 3×4 reps just refused: this is one of the three
        // accepted gaps — a unit change, where reps and seconds have no
        // defined ratio — so the landing takes the grid floor of the hold,
        // which is the lightest thing that exists.
        val back = up.copy()
        back.counter = 1
        val session2 = Engine.generateSession(back)
        val down = Engine.applyFeedback(state = back, session = session2, result = FeedbackResult.plan,
                                        overrides = mapOf(Pattern.pullBar to 0.0), skipped = emptySet(),
                                        gapDays = null, probes = emptyMap())
        assertEquals(2, down.vars[Pattern.pullBar])
        assertEquals(15, down.doses[Pattern.pullBar], "the floor of the hold grid, not its ceiling")
        assertEquals(LoadUnit.hold, Library.unit(Pattern.pullBar, assertNotNull(down.vars[Pattern.pullBar])))
    }

    // MARK: - "Next time, more"

    /** One step is one growth event along the dose: a sub-step, then the
     *  rung. Two steps from 3×8 give 9-9-8; the raise touches nothing else. */
    @Test
    fun raiseDoseWalksSubStepsThenTheRung() {
        val s = state(Pattern.squat, variation = 2, dose = 8, seed = Seed(shown = mapOf(2 to 8)))
        val one = Engine.raiseDose(state = s, pattern = Pattern.squat, steps = 1)
        assertEquals(8, one.doses[Pattern.squat])
        assertEquals(1, one.sub[Pattern.squat])
        val two = Engine.raiseDose(state = s, pattern = Pattern.squat, steps = 2)
        assertEquals(2, two.sub[Pattern.squat])
        assertEquals(s.shown, two.shown, "the journal is written by an appearance, never by a wish")
        assertEquals(s.counter, two.counter)
        // Three sub-steps on a band of three is the next rung.
        var three = two.copy()
        three = Engine.raiseDose(state = three, pattern = Pattern.squat, steps = 1)
        assertEquals(9, three.doses[Pattern.squat])
        assertNull(three.sub[Pattern.squat])
    }

    /** The grid's ceiling parks the raise: the steps burn, nothing crosses
     *  into a variation, and the clamp on the input is the engine's
     *  (`raiseStepsMax`), not the caller's good manners. */
    @Test
    fun raiseDoseStandsOnTheCeilingAndClampsItsInput() {
        val top = squatAtCeiling()
        val parked = Engine.raiseDose(state = top, pattern = Pattern.squat, steps = 2)
        assertEquals(15, parked.doses[Pattern.squat])
        assertEquals(1, parked.vars[Pattern.squat], "a raise never crosses a variation")
        val s = state(Pattern.squat, variation = 2, dose = 8)
        assertEquals(EngineConfig.raiseStepsMax,
                     Engine.raiseDose(state = s, pattern = Pattern.squat, steps = 99).sub[Pattern.squat])
        assertEquals(s, Engine.raiseDose(state = s, pattern = Pattern.squat, steps = -1))
        assertEquals(s, Engine.raiseDose(state = s, pattern = Pattern.squat, steps = 0))
    }

    /** Under a cut the sub-step counts the sets ON SCREEN: with one set
     *  taken off a band of three, the second step must still change the plan
     *  — the band count would clamp it straight back (`effSub`). */
    @Test
    fun raiseDoseCountsTheSetsOnScreenUnderACut() {
        val s = state(Pattern.squat, variation = 2, dose = 8)
        s.cut[Pattern.squat] = 1
        val one = Engine.raiseDose(state = s, pattern = Pattern.squat, steps = 1)
        assertEquals(1, one.sub[Pattern.squat])
        val two = Engine.raiseDose(state = s, pattern = Pattern.squat, steps = 2)
        assertEquals(9, two.doses[Pattern.squat], "the second step is the rung, not a clamped repeat")
        assertNull(two.sub[Pattern.squat])
        assertEquals(1, two.cut[Pattern.squat], "the cut is not the raise's to touch")
    }

    /** The composed entry point lands the raise LAST: a fact above the plan
     *  sets the dose from the fact and zeroes the sub-step, and a raise
     *  applied before it would vanish. Here it survives. */
    @Test
    fun raiseLandsAfterTheFeedback() {
        val s = state(Pattern.squat, variation = 2, dose = 8, seed = Seed(shown = mapOf(2 to 8)))
        val session = Engine.generateSession(s)
        val next = Engine.applyFeedback(state = s, session = session, result = FeedbackResult.plan,
                                        overrides = mapOf(Pattern.squat to 10.0), skipped = emptySet(),
                                        setsSkipped = emptyMap(), gapDays = 7.0 / 3.0,
                                        probes = emptyMap(), raised = mapOf(Pattern.squat to 1))
        assertEquals(10, next.doses[Pattern.squat], "fast adaptation: the fact is the next dose")
        assertEquals(1, next.sub[Pattern.squat], "…and the raise sits on top of it")
    }
}
