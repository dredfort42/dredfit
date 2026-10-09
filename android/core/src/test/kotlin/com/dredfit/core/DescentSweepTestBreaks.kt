//
//  The fourth path of the descent sweep: what a break writes — the silent
//  decay and the comeback's landing ceiling. Kept apart from the rated and
//  handle paths only for file length; it reuses the same enumeration and
//  the same two-measure `assertDescent` (the `DescentSweep` helpers in
//  DescentSweepTest.kt — Kotlin cannot extend a test class across files the
//  way the Swift extension does).
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DescentSweepBreaksTest {

    // MARK: - Path 4 · what a break writes

    /**
     * The silent decay is a descent too, and it walks `fallDoses` from
     * whatever the person was standing on — bands and cut included.
     */
    @Test
    fun silentDecay_fromEveryPosition_neverMakesThePlanHeavier() {
        var measured = 0
        for (p in Pattern.allCases) {
            val journal = DescentSweep.fullJournal(p)
            for (q in DescentSweep.allPositions(p)) {
                val after = Engine.applySilentDecay(state = DescentSweep.seeded(p, q), gapDays = 10).position(p)
                if (DescentSweep.assertDescent(p, from = q, to = after, shown = journal) {
                        "${DescentSweep.describe(p, q)} decayed to ${DescentSweep.describe(p, after)}"
                    }) measured += 1
            }
        }
        assertTrue(measured > 5000, "only $measured cells reached the independent measure")
    }

    /**
     * The fourth path down: on a gap that hits a row of the landing-ceiling
     * table the comeback walks rungs and then holds the landing to the
     * ceiling (`Breaks`). A walk that ends above it is replaced by the
     * ceiling's floor on the base band, with nothing cut; one that ends on it
     * keeps its band and cut and drops to the floor dose. Swept from every position with a
     * cut or a band: what the write does to somebody training on two sets,
     * or on a band of four or five, is asserted for each of them.
     *
     * What `applyComeback` promises here is the CEILING, absolutely: the
     * landing is never above `ceilVar`, and landing on `ceilVar` is always the
     * floor of its grid, whatever the position was.
     */
    @Test
    fun comebackLandingCeiling_fromEveryCutAndBandPosition_landsOnTheFloorOfItsVariation() {
        for (p in Pattern.allCases) {
            val positions = DescentSweep.allPositions(p).filter { it.cut > 0 || it.sets > EngineConfig.setsBase }
            for ((minGap, floorIndex) in EngineConfig.comebackLandingCeil) {
                val ceiling = Engine.ceilVar(pattern = p, floorIndex = floorIndex)
                for (q in positions) {
                    val after = Engine.applyComeback(state = DescentSweep.seeded(p, q), gapDays = minGap).position(p)
                    assertTrue(after.variation <= ceiling,
                               "${DescentSweep.describe(p, q)} after $minGap days landed above the ceiling")
                    if (after.variation != ceiling) continue
                    assertEquals(Dose.grid(Library.unit(p, ceiling)).min, after.dose,
                                 "${DescentSweep.describe(p, q)} after $minGap days: the ceiling must be a grid floor")
                    assertEquals(0, after.sub, "${DescentSweep.describe(p, q)}: a return takes the sub-step everywhere")
                }
            }
        }
    }

    /**
     * And the return is a DESCENT, so "no heavier" binds it as well —
     * including the gaps where the ceiling replaces the walk's landing, and
     * including the cut and the bands.
     *
     * The reference's verifier runs this sweep over every position for the
     * silent decay only; for the comeback it checks narrower things, such as
     * a longer break never landing higher. This sweep goes further on purpose,
     * and is no stricter rule: the engine already passes it, so it pins what
     * the model does rather than raising a bar past it.
     */
    @Test
    fun comeback_fromEveryCutAndBandPosition_neverMakesThePlanHeavier() {
        // Both sides of the return table: gaps before its first row walk rungs
        // only, gaps on a row also take the landing ceiling.
        val gaps = listOf(EngineConfig.comebackMinGapDays, 30) +
            EngineConfig.comebackLandingCeil.map { it.first }
        var measured = 0
        for (p in Pattern.allCases) {
            val journal = DescentSweep.fullJournal(p)
            val positions = DescentSweep.allPositions(p).filter { it.cut > 0 || it.sets > EngineConfig.setsBase }
            for (gap in gaps) {
                for (q in positions) {
                    val after = Engine.applyComeback(state = DescentSweep.seeded(p, q), gapDays = gap).position(p)
                    if (DescentSweep.assertDescent(p, from = q, to = after, shown = journal) {
                            "${DescentSweep.describe(p, q)} returned after $gap days to ${DescentSweep.describe(p, after)}"
                        }) {
                        measured += 1
                    }
                }
            }
        }
        assertTrue(measured > 15_000, "only $measured cells reached the independent measure")
    }

    /**
     * The depth of a comeback does not RISE with the length of the break.
     * The sweep above is about two points — this plan against the last one —
     * and a curve that dips and comes back up satisfies it at every step
     * while breaking the card's own sentence, "the longer the break, the
     * lower the plan meets you".
     *
     * A probing appearance is where it would break: with the memory written
     * by the working sets alone, one set below the position, a descent would
     * take the set the probe only borrowed until the dose fell far enough for
     * three sets to fit under that base again, and the plan would jump back UP —
     * 84 days would meet a person higher than 56. `Engine.shownWorkOf` counts
     * the borrowed set for that reason.
     */
    @Test
    fun comeback_afterAProbingAppearance_neverRisesWithTheLengthOfTheBreak() {
        val gaps = listOf(14, 16, 18, 20, 24, 28, 35, 42, 49, 56, 63, 70, 77, 84, 95, 110, 120)
        // Every dose at the ceiling of its variation with the journal to prove
        // it — the one state that offers a probe (`probeAllowed`).
        val state = EngineState.initial
        state.counter = 11
        for (p in Pattern.allCases) {
            val grid = Dose.grid(Library.unit(p, 1))
            state.doses[p] = grid.max
            state.shown[p] = mutableMapOf(1 to grid.max)
        }
        val shown = Engine.generateSession(state.sanitized())
        val probing = shown.exercises.filter { it.probe != null }.map { it.pattern }.toSet()
        // Without this the sweep measures an ordinary descent and goes green
        // on a state that never exercised the rule.
        assertFalse(probing.isEmpty(), "the seed produced no probing appearance")

        val played = Engine.applyFeedback(state = state.sanitized(), session = shown,
                                          result = FeedbackResult.plan, overrides = emptyMap(),
                                          skipped = emptySet(), setsSkipped = emptyMap(),
                                          gapDays = 7.0 / 3, probes = emptyMap())
        for (p in Pattern.allCases) {
            var previous = Int.MAX_VALUE
            for (gap in gaps) {
                val after = Engine.applyComeback(state = played, gapDays = gap)
                val ex = Engine.generateSession(after).exercises.firstOrNull { it.pattern == p } ?: continue
                val work = Engine.exerciseWork(ex)
                assertTrue(work <= previous,
                           "${p.rawValue}: a $gap-day break lands on $work, a shorter one on $previous")
                previous = work
            }
        }
    }

    /**
     * The other half of the same rule, stated on the axis the repair acts on:
     * a descent out of a probing appearance keeps the sets the POSITION holds.
     * The probe borrowed a set for one session; nothing about coming back
     * says it may be kept.
     */
    @Test
    fun comeback_afterAProbingAppearance_keepsTheSetsThePositionHolds() {
        val state = EngineState.initial
        state.counter = 11
        for (p in Pattern.allCases) {
            val grid = Dose.grid(Library.unit(p, 1))
            state.doses[p] = grid.max
            state.shown[p] = mutableMapOf(1 to grid.max)
        }
        val shown = Engine.generateSession(state.sanitized())
        assertTrue(shown.exercises.any { it.probe != null },
                   "the seed produced no probing appearance")
        val played = Engine.applyFeedback(state = state.sanitized(), session = shown,
                                          result = FeedbackResult.plan, overrides = emptyMap(),
                                          skipped = emptySet(), setsSkipped = emptyMap(),
                                          gapDays = 7.0 / 3, probes = emptyMap())
        for (gap in listOf(14, 20, 35, 56, 84, 120)) {
            val after = Engine.applyComeback(state = played, gapDays = gap).sanitized()
            for (ex in Engine.generateSession(after).exercises.filter { it.probe == null }) {
                val q = after.position(ex.pattern)
                assertEquals(Engine.setsAfterCut(sets = q.sets, cut = q.cut), ex.sets,
                             "${ex.pattern.rawValue}: $gap days gave ${ex.sets} sets " +
                             "against a position of ${Engine.setsAfterCut(sets = q.sets, cut = q.cut)}")
            }
        }
    }

    /**
     * The two ends of the ceiling table are fixed points: the deepest return
     * lands on the first variation, the shallowest may stay on the top one.
     * Without this the linear stretch in `ceilVar` could drift by one and
     * every check above would still pass.
     */
    @Test
    fun comebackCeilingTable_atBothEnds_spansTheWholeLadder() {
        for (p in Pattern.allCases) {
            assertEquals(1, Engine.ceilVar(pattern = p, floorIndex = 1),
                         "${p.rawValue}: the deepest return lands on the first variation")
            assertEquals(Library.count(p),
                         Engine.ceilVar(pattern = p, floorIndex = EngineConfig.comebackCeilFloors),
                         "${p.rawValue}: the shallowest return may stay on the top variation")
        }
    }
}
