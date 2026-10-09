//
//  The rotation and the slots, the bar gate, growth and parking, the skip,
//  determinism, the counter and the double-feedback guard, the breaks, the
//  handles, the sanitizer, and what the plan says.
//
//  "No path of descent makes the plan heavier" is swept in
//  `DescentSweepTest`, over the whole domain and all four paths down.
//
//  The port of EngineTests.swift. `EngineState` is a mutable class here, so
//  every Swift value copy that is later mutated is an explicit `copy()`.
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EngineTest {

    // MARK: - Rotation and slots

    /** The pull slot stands in every session; over eight sessions each
     *  rotating pattern comes up exactly five times. */
    @Test
    fun pullInEverySessionAndRotationCoverage() {
        val counts = mutableMapOf<Pattern, Int>()
        val state = EngineState.initial
        repeat(8) {
            val session = Engine.generateSession(state)
            assertEquals(EngineConfig.patternsPerSession, session.exercises.size)
            assertTrue(session.exercises.any { it.pattern == Pattern.pull }, "the pull slot is fixed")
            for (ex in session.exercises) counts[ex.pattern] = (counts[ex.pattern] ?: 0) + 1
            state.counter += 1
        }
        assertEquals(8, counts[Pattern.pull])
        for (p in Pattern.ordered.filter { it != Pattern.pull }) {
            assertEquals(5, counts[p], "${p.rawValue} must appear five times in eight")
        }
    }

    /** The exercises of a session come out in the canonical order, never in
     *  the order the rotation happened to pick them. */
    @Test
    fun sessionExercisesFollowCanonicalOrder() {
        for (counter in 0 until 16) {
            val state = EngineState.initial
            state.counter = counter
            val order = Engine.generateSession(state).exercises.map { it.pattern }
            val ranks = order.map { p ->
                Pattern.ordered.indexOf(if (p == Pattern.pullBar) Pattern.pull else p)
            }
            assertEquals(ranks.sorted(), ranks, "session ${counter + 1} is out of order")
        }
    }

    /** With the bar on, the odd sessions hand the pull slot to the vertical
     *  branch — and with it off, the branch never appears. */
    @Test
    fun hasBarAlternatesThePullSlot() {
        val state = EngineState.initial
        state.hasBar = true
        for (counter in 0 until 8) {
            state.counter = counter
            val patterns = Engine.generateSession(state).exercises.map { it.pattern }
            assertTrue(patterns.contains(if (counter % 2 == 1) Pattern.pullBar else Pattern.pull),
                       "session ${counter + 1} took the wrong branch")
            assertFalse(patterns.contains(if (counter % 2 == 1) Pattern.pull else Pattern.pullBar))
        }
        state.hasBar = false
        for (counter in 0 until 8) {
            state.counter = counter
            assertFalse(Engine.generateSession(state).exercises.any { it.pattern == Pattern.pullBar },
                        "with no bar the vertical branch is never planned")
        }
    }

    /** The two branches of the pull slot keep their own positions. */
    @Test
    fun pullBranchesAreIndependent() {
        val state = EngineState.initial
        state.hasBar = true
        state.vars[Pattern.pullBar] = 5
        state.doses[Pattern.pullBar] = 7
        state.counter = 1
        val bar = Engine.generateSession(state).exercises.firstOrNull { it.pattern == Pattern.pullBar }
        assertEquals(5, bar?.variation)
        assertEquals(7, bar?.load)
        assertEquals(1, state.vars[Pattern.pull], "the horizontal branch did not move")
    }

    // MARK: - Growth, parking and the floor

    /** Answering "on plan" forever climbs the whole ladder — through probes,
     *  which are the only door — and ends parked on the top variation's last
     *  band. Growth never crosses a variation on its own. */
    @Test
    fun alwaysPlanClimbsToTheTopAndParks() {
        var state = EngineState.initial
        // The longest ladders are seven variations of twelve rungs each, and
        // the top ones cap growth at one event per appearance — so the walk to
        // the very top is long by construction, not by accident.
        repeat(1500) {
            val session = Engine.generateSession(state)
            val probes = mutableMapOf<Pattern, Int>()
            for (ex in session.exercises) {
                val probe = ex.probe ?: continue
                probes[ex.pattern] = Dose.grid(probe.unit).min
            }
            state = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.plan,
                                         overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                         probes = probes)
        }
        for (p in Pattern.ordered) {
            assertEquals(Library.count(p), state.vars[p], "${p.rawValue}: the top variation")
            assertEquals(EngineConfig.setsMax, state.sets[p] ?: EngineConfig.setsBase,
                         "${p.rawValue}: the last band")
            val v = assertNotNull(state.vars[p])
            assertEquals(Dose.grid(Library.unit(p, v)).max, state.doses[p],
                         "${p.rawValue}: the top of the grid")
        }
    }

    /** Answering "hard" forever lands on the bottom of the whole ladder and
     *  stops there: first variation, floor of the grid, floor of the sets. */
    @Test
    fun alwaysLessFloorsAtTheBottom() {
        var state = EngineState.initial
        state.vars[Pattern.squat] = 4
        state.doses[Pattern.squat] = 9
        repeat(200) {
            val session = Engine.generateSession(state)
            state = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.less,
                                         overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                         probes = emptyMap())
        }
        for (p in Pattern.ordered) {
            assertEquals(1, state.vars[p], "${p.rawValue}: the bottom variation")
            assertEquals(Dose.grid(Library.unit(p, 1)).min, state.doses[p],
                         "${p.rawValue}: the floor of the grid")
            assertEquals(EngineConfig.setsFloor,
                         Engine.setsAfterCut(sets = state.sets[p] ?: EngineConfig.setsBase,
                                             cut = state.cutOf(p)),
                         "${p.rawValue}: the floor of the sets")
        }
    }

    /** Three shortfalls in a row deload the movement by whole rungs of dose. */
    @Test
    fun deloadFiresOnTheThirdConsecutiveShortfall() {
        var state = EngineState.initial
        state.doses[Pattern.squat] = 12
        state.shown[Pattern.squat] = mutableMapOf(1 to 12)
        for (round in 1..3) {
            // The squat does not stand in every session of the rotation, and a
            // streak is counted in APPEARANCES — so put it back in every time
            // rather than letting the rotation silently skip a round.
            state.counter = 0
            val session = Engine.generateSession(state)
            val before = assertNotNull(state.doses[Pattern.squat])
            state = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.plan,
                                         overrides = mapOf(Pattern.squat to (before - 1).toDouble()),
                                         skipped = emptySet(), gapDays = null, probes = emptyMap())
            if (round < 3) {
                assertEquals(round, state.failStreak[Pattern.squat])
            } else {
                assertEquals(0, state.failStreak[Pattern.squat], "the streak resets on the deload")
            }
        }
        // Two honest shortfalls take it to 10; the third takes it to 9 and the
        // deload then drops three more rungs.
        assertEquals(6, state.doses[Pattern.squat])
    }

    // MARK: - The skip

    @Test
    fun skippedPatternKeepsItsPositionAndStreak() {
        val state = EngineState.initial
        state.failStreak[Pattern.squat] = 2
        val session = Engine.generateSession(state)
        val after = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.more,
                                         overrides = emptyMap(), skipped = setOf(Pattern.squat),
                                         gapDays = null, probes = emptyMap())
        assertEquals(state.doses[Pattern.squat], after.doses[Pattern.squat],
                     "an untrained pattern does not move")
        assertEquals(2, after.failStreak[Pattern.squat], "and its streak is frozen, not reset")
        assertNull(after.shown[Pattern.squat], "and nothing is written to its journal")
        val afterPush = assertNotNull(after.doses[Pattern.pushH]) + (after.sub[Pattern.pushH] ?: 0)
        assertTrue(afterPush > assertNotNull(state.doses[Pattern.pushH]),
                   "the rest of the session still moved")
    }

    @Test
    fun skipBeatsAnOverride() {
        val state = EngineState.initial
        val session = Engine.generateSession(state)
        val after = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.plan,
                                         overrides = mapOf(Pattern.squat to 14.0),
                                         skipped = setOf(Pattern.squat), gapDays = null,
                                         probes = emptyMap())
        assertEquals(4, after.doses[Pattern.squat], "the fact for a skipped movement is ignored")
        assertNull(after.shown[Pattern.squat])
    }

    @Test
    fun allSkippedAdvancesOnlyTheCounter() {
        val state = EngineState.initial
        val session = Engine.generateSession(state)
        val skipped = session.exercises.map { it.pattern }.toSet()
        val after = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.more,
                                         overrides = emptyMap(), skipped = skipped, gapDays = null,
                                         probes = emptyMap())
        assertEquals(1, after.counter)
        assertEquals(state.vars, after.vars)
        assertEquals(state.doses, after.doses)
        assertTrue(after.shown.isEmpty())
    }

    /** A fact about a movement that is not in today's session is dropped — the
     *  trap the fixture's own author-guard exists to catch. */
    @Test
    fun factForAMovementOutsideTheSessionIsIgnored() {
        val state = EngineState.initial
        state.counter = 0
        val session = Engine.generateSession(state)
        assertFalse(session.exercises.any { it.pattern == Pattern.calf })
        val after = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.plan,
                                         overrides = mapOf(Pattern.calf to 13.0), skipped = emptySet(),
                                         gapDays = null, probes = emptyMap())
        assertEquals(state.doses[Pattern.calf], after.doses[Pattern.calf])
        assertNull(after.shown[Pattern.calf])
    }

    // MARK: - Determinism and the double-feedback guard

    @Test
    fun determinism() {
        var a = EngineState.initial
        var b = EngineState.initial
        repeat(40) {
            val sa = Engine.generateSession(a)
            val sb = Engine.generateSession(b)
            assertEquals(sa, sb)
            a = Engine.applyFeedback(state = a, session = sa, result = FeedbackResult.more,
                                     overrides = mapOf(Pattern.pull to 7.0), skipped = emptySet(),
                                     gapDays = 2.0, probes = emptyMap())
            b = Engine.applyFeedback(state = b, session = sb, result = FeedbackResult.more,
                                     overrides = mapOf(Pattern.pull to 7.0), skipped = emptySet(),
                                     gapDays = 2.0, probes = emptyMap())
        }
        assertEquals(a, b)
    }

    /** The same (state, session) pair fed back twice is a silent no-op. */
    @Test
    fun replayedFeedbackIsANoOp() {
        val state = EngineState.initial
        val session = Engine.generateSession(state)
        val once = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.plan,
                                        overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                        probes = emptyMap())
        val twice = Engine.applyFeedback(state = once, session = session, result = FeedbackResult.plan,
                                         overrides = emptyMap(), skipped = emptySet(), gapDays = null,
                                         probes = emptyMap())
        assertEquals(once, twice)
    }

    /** The guard holds for the composed entry point too: the skipped sets and
     *  the raise must not land a second time on a replayed session. */
    @Test
    fun replayedFeedbackWithCutsAndRaisesIsANoOp() {
        val state = EngineState.initial
        val session = Engine.generateSession(state)
        val p = session.exercises[0].pattern
        val once = Engine.applyFeedback(state = state, session = session, result = FeedbackResult.plan,
                                        setsSkipped = mapOf(p to 1), raised = mapOf(p to 1))
        val twice = Engine.applyFeedback(state = once, session = session, result = FeedbackResult.plan,
                                         setsSkipped = mapOf(p to 1), raised = mapOf(p to 1))
        assertEquals(once, twice)
    }

    // MARK: - Breaks

    /** The silent decay acts only inside the blind zone of 7…13 days. */
    @Test
    fun silentDecayActsOnlyInsideTheBlindZone() {
        val state = EngineState.initial
        state.doses[Pattern.squat] = 10
        for (gap in listOf(0, 3, 6, 14, 40)) {
            assertEquals(10, Engine.applySilentDecay(state = state, gapDays = gap).doses[Pattern.squat],
                         "gap $gap is outside the blind zone")
        }
        for (gap in listOf(7, 10, 13)) {
            assertEquals(9, Engine.applySilentDecay(state = state, gapDays = gap).doses[Pattern.squat],
                         "gap $gap costs exactly one rung")
        }
    }

    /** BY CONSTRUCTION, a decay plus a weakened comeback is the plain
     *  comeback. Walking one step and then drop−1 steps is walking drop
     *  steps, because every mechanism walks the same rungs. */
    @Test
    fun decayPlusWeakenedComebackEqualsPlainComeback() {
        val state = EngineState.initial
        state.vars[Pattern.squat] = 4
        state.doses[Pattern.squat] = 9
        state.vars[Pattern.coreAntiExt] = 3
        state.doses[Pattern.coreAntiExt] = 35
        state.shown = mutableMapOf(
            Pattern.squat to mutableMapOf(3 to 12, 4 to 9),
            Pattern.coreAntiExt to mutableMapOf(2 to 30, 3 to 35),
        )

        val peeked = Engine.applyComeback(
            state = Engine.applySilentDecay(state = state, gapDays = 10),
            gapDays = 30, alreadyDecayed = true)
        val plain = Engine.applyComeback(state = state, gapDays = 30, alreadyDecayed = false)
        assertEquals(plain.vars, peeked.vars)
        assertEquals(plain.doses, peeked.doses)
        assertEquals(plain.sub, peeked.sub)
        assertEquals(plain.cut, peeked.cut)
        assertEquals(plain.sets, peeked.sets)
    }

    /** A comeback never moves the counter — a break is not a training event. */
    @Test
    fun comebackLeavesTheCounterAlone() {
        val state = EngineState.initial
        state.counter = 11
        val after = Engine.applyComeback(state = state, gapDays = 40, alreadyDecayed = false)
        assertEquals(11, after.counter)
        assertEquals(1, after.returnRun)
        assertEquals(EngineConfig.rampWindowSessions, after.rampWindow)
    }

    /** A run of returns (§22.3): comebacks in a row with no session between
     *  them each deepen the drop by one. At the 14-day minimum the first
     *  return walks the base two rungs, 12 → 10; the second walks three,
     *  10 → 7 — not another two, which would land on 8. */
    @Test
    fun returnsInARowDeepenTheDrop() {
        val state = EngineState.initial
        state.doses[Pattern.squat] = 12
        state.shown[Pattern.squat] = mutableMapOf(1 to 12)
        val first = Engine.applyComeback(state = state, gapDays = 14)
        assertEquals(10, first.doses[Pattern.squat])
        assertEquals(1, first.returnRun)
        val second = Engine.applyComeback(state = first, gapDays = 14)
        assertEquals(7, second.doses[Pattern.squat], "the second return in a row drops one rung deeper")
        assertEquals(2, second.returnRun)
    }

    // MARK: - Handles

    /** "Give me something easier" lands under the JOURNAL of the variation
     *  below, not on a floor — there are no tier floors.
     *
     *  The journal is a CEILING, not the landing: landing on it would hand a
     *  trainee the largest volume they had ever done there right after they
     *  asked for something easier. The landing walks the journal DOWN until
     *  the work stops growing, so the assertion is a bound, plus a direct
     *  check that a button labelled "easier" is in fact easier. */
    @Test
    fun easierVariationLandsNoHeavier() {
        val state = EngineState.initial
        state.vars[Pattern.squat] = 3
        state.doses[Pattern.squat] = 7
        state.shown = mutableMapOf(Pattern.squat to mutableMapOf(2 to 11, 3 to 7))
        val before = state.position(Pattern.squat)
        val after = Engine.easierVariation(state = state, pattern = Pattern.squat)
        assertEquals(2, after.vars[Pattern.squat])
        val landed = after.position(Pattern.squat)
        assertTrue(landed.dose <= 11, "never above what was done there")
        assertTrue(landed.dose >= Dose.grid(Library.unit(Pattern.squat, 2)).min)
        assertTrue(Engine.noHarder(Pattern.squat, from = before, to = landed, shown = state.shown),
                   "the handle says easier, so it must be easier")
    }

    /** On the first variation the handle is inert: there is nothing below it. */
    @Test
    fun easierVariationIsInertOnTheFirstRung() {
        val state = EngineState.initial
        assertEquals(state, Engine.easierVariation(state = state, pattern = Pattern.squat))
    }

    // MARK: - The sanitizer

    /** A file written by a future version, opened after a downgrade: entries
     *  for unknown patterns are dropped rather than failing the whole decode. */
    @Test
    fun unknownPatternDecodesLeniently() {
        val json = """
        {"counter":3,"vars":["squat",2,"kettlebell_swing",9],
         "doses":["squat",7,"kettlebell_swing",99],"failStreak":["squat",1]}
        """
        val state = EngineState.decode(json)
        assertEquals(2, state.vars[Pattern.squat])
        assertEquals(7, state.doses[Pattern.squat])
        assertEquals(1, state.vars.size, "the unknown pattern was dropped")
        assertEquals(Pattern.allCases.size, state.sanitized().vars.size,
                     "and the sanitizer fills the rest in")
    }

    /** A corrupt counter must not feed the rotation: it would index out of
     *  bounds, and near Int.max it would trap the process on every plan. */
    @Test
    fun garbageCounterIsHealed() {
        val json = """
        {"counter":-5,"vars":["squat",1],"doses":["squat",4],"failStreak":["squat",0]}
        """
        val state = EngineState.decode(json)
        assertEquals(0, state.counter)
        assertEquals(1, Engine.generateSession(state).sessionNumber)
    }

    /** Out-of-range coordinates are healed, not preserved: a variation past
     *  the ladder, a dose off the grid, a band on a variation that has none. */
    @Test
    fun outOfRangePositionsAreHealed() {
        val state = EngineState.initial
        state.vars[Pattern.squat] = 99
        state.doses[Pattern.squat] = 37
        state.sets[Pattern.lunge] = 5          // not the top variation — no bands there
        state.sub[Pattern.hinge] = 9
        state.cut[Pattern.calf] = 9
        val clean = state.sanitized()
        assertEquals(Library.count(Pattern.squat), clean.vars[Pattern.squat])
        assertEquals(15, clean.doses[Pattern.squat], "clamped to the top of the grid")
        assertEquals(EngineConfig.setsBase, clean.sets[Pattern.lunge] ?: EngineConfig.setsBase)
        assertEquals(2, clean.sub[Pattern.hinge] ?: 0, "at most sets − 1")
        assertEquals(EngineConfig.setsBase - EngineConfig.setsFloor, clean.cutOf(Pattern.calf))
    }

    /** Reading the library is TOTAL — the rule `ExerciseEntry.variation` is
     *  written for: "a plan built from a dirty state has to stay a valid input
     *  to `applyFeedback`, and the sanitizer is not the only door into this
     *  type". Nothing else in this package's tests asks the catalog for a variation
     *  off the end of a ladder, so a `variations[v - 1]` written in place of
     *  the clamp would pass every other test here and trap on the first dirty
     *  state that reached a plan. */
    @Test
    fun libraryRead_withAVariationOffTheLadder_clampsInsteadOfTrapping() {
        for (p in Pattern.allCases) {
            val entry = ExerciseLibrary.entry(p)
            val last = Library.count(p)
            for (v in listOf(Int.MIN_VALUE, -1, 0, last + 1, Int.MAX_VALUE)) {
                val clamped = Library.index(pattern = p, variation = v)
                assertTrue(clamped in 1..last,
                           "${p.rawValue}: variation $v must clamp into the ladder")
                assertEquals(entry.variation(clamped), entry.variation(v),
                             "${p.rawValue}: variation $v must read the clamped rung")
                assertEquals(Library.unit(p, clamped), entry.unit(forVariation = v),
                             "${p.rawValue}: the unit of variation $v is the clamped rung's")
                assertEquals(entry.probeOnly(variation = clamped), entry.probeOnly(variation = v),
                             "${p.rawValue}: probeOnly of variation $v is the clamped rung's")
                assertFalse(Library.name(p, v).isEmpty(),
                            "${p.rawValue}: variation $v must still name a movement")
            }
        }
    }

    // MARK: - What the plan says

    @Test
    fun displayStringsAreWellFormed() {
        val state = EngineState.initial
        state.doses[Pattern.squat] = 9
        state.sub[Pattern.squat] = 1
        state.vars[Pattern.coreAntiExt] = 3
        state.doses[Pattern.coreAntiExt] = 30
        state.vars[Pattern.lunge] = 2
        val session = Engine.generateSession(state)
        for (ex in session.exercises) {
            assertFalse(ex.display.isEmpty())
            assertFalse(ex.name.isEmpty())
            if (ex.loads == null) {
                assertTrue(ex.display.contains("${ex.sets}×${ex.load}"),
                           "${ex.pattern.rawValue}: a uniform plan reads N×dose")
            } else {
                assertTrue(ex.display.contains("-"),
                           "${ex.pattern.rawValue}: an uneven plan reads 9-8-8")
            }
        }
    }

    /** The announced duration is a real number of minutes, and the probe is
     *  inside it: a session with a probe is not shorter than the same session
     *  without one. */
    @Test
    fun durationCountsTheProbe() {
        val withProbe = EngineState.initial
        withProbe.doses[Pattern.squat] = 15
        withProbe.shown[Pattern.squat] = mutableMapOf(1 to 15)
        val noProbe = withProbe.copy()
        noProbe.lastHard = mutableSetOf(Pattern.squat)

        val a = Engine.generateSession(withProbe)
        val b = Engine.generateSession(noProbe)
        assertNotNull(assertNotNull(a.exercises.firstOrNull { it.pattern == Pattern.squat }).probe)
        assertNull(assertNotNull(b.exercises.firstOrNull { it.pattern == Pattern.squat }).probe)
        assertTrue(a.estimatedTotalMin > 0)
        assertEquals(b.estimatedTotalMin, a.estimatedTotalMin, 2.0,
                     "the probe replaces a set, it does not add a block of work")
    }

    /** The duration is rounded as the reference's `toFixed(1)`: the nearest
     *  tenth to the exact double, a tie to the larger number. 2079 s / 60 sits
     *  just under 34.65 (34.6, where `roundedAwayFromZero(x * 10)` says 34.7);
     *  2115 s / 60 is exactly 35.25, a real tie (35.3, where half-to-even —
     *  `kotlin.math.round` too — says 35.2). */
    @Test
    fun durationRoundsLikeTheReference() {
        fun minutes(seconds: Int): Double {
            val hold = SessionExercise(pattern = Pattern.coreAntiExt, name = "hold", variation = 1,
                                       unit = LoadUnit.hold, load = seconds, perSide = false, sets = 1,
                                       restSetSec = 0, restExerciseSec = 0, loads = null, probe = null)
            return Engine.estimatedMin(exercises = listOf(hold), ends = 0)
        }
        assertEquals(34.6, minutes(2079))
        assertEquals(35.3, minutes(2115))
    }
}
