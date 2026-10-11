//
//  "No path of descent makes the plan heavier", swept from every position of
//  every ladder, enumerated the way the reference's verifier enumerates them,
//  through each path down that this file covers. Port of DescentSweepTests.swift
//  (the break paths live in DescentSweepTestBreaks.kt and share `DescentSweep`).
//
//  WHY AN ENUMERATION. A sweep that builds its starting position exactly one
//  way — base band, `cut 0`, `sub 0` — can call itself exhaustive ("every
//  variation and every rung of every ladder") while everything bands 4 and 5,
//  the cut and the sub-step add to a position stays outside it. The sweep here
//  is deliberately driven by the enumeration of positions the reference's
//  verifier sweeps, rather than by one hand-written start.
//
//  The four paths: `fallBy` (a rated descent), `fallDoses` (whole rungs — the
//  deload, the decay, the comeback), `easierPosition` (the handle), and the
//  direct write in the comeback's landing ceiling (`Breaks`).
//
//  TWO MEASURES, ON PURPOSE. Every "no heavier" below is asserted twice: once
//  through `Engine.noHarder`, and once through `Work` — a measure this file
//  computes itself out of the position and the catalog. The second is not a
//  belt-and-braces duplicate of the first: on a landing it is the ONLY one of
//  the two that can fail. `Work` carries the mutation that proves it.
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Helpers shared by `DescentSweepTest` and `DescentSweepBreaksTest` (Kotlin
 *  cannot split a class across files the way the Swift extension does). */
internal object DescentSweep {

    /**
     * The closed list of boundaries where "no heavier" is structurally
     * unreachable — the variation below is trained per side, or in other units,
     * and even its lightest plan outweighs two sets of the one above. Keyed by
     * the UPPER variation of the crossing, exactly as `IMPOSSIBLE_LANDINGS` in
     * `verify2.js` is.
     *
     * The list is closed and named by number. Widening it silently is not
     * allowed: each line is an accepted gap `landInVar` names, not a threshold.
     */
    object AcceptedGap {

        //   hinge 4→3     sliding leg curl (two legs) → one-leg glute bridge   ×2.00
        //   hinge 7→6     assisted nordic curl        → one-leg sliding curl   ×2.00
        //   pull_bar 3→2  negatives (reps)            → scapular hang (s)      ×1.50
        val landings: Map<Pattern, Set<Int>> = mapOf(Pattern.hinge to setOf(4, 7), Pattern.pullBar to setOf(3))

        /**
         * How much heavier an accepted gap may land when the independent measure
         * CAN see it — the most any path below reaches from any position, and
         * it is reached exactly: 3×4 on two legs (12) → 3×4 per side (24) on
         * both hinge gaps. Flat, not per boundary: a descent that crosses both
         * hinge gaps at once (7 → 1) only reaches ×1.50.
         *
         * An accepted gap is therefore BOUNDED here rather than skipped. The list
         * names accepted numbers, not a licence, and a `continue` on those cells
         * would turn a closed list of three into a hole.
         */
        const val factor = 2

        fun closes(p: Pattern, leaving: Int): Boolean = landings[p]?.contains(leaving) ?: false

        /** True when a descent from `from` to `to` steps over any of them. */
        fun crossed(p: Pattern, from: Int, to: Int): Boolean {
            val lo = minOf(from, to) + 1
            val hi = maxOf(from, to)
            if (lo > hi) return false                        // no boundary was crossed at all
            return (lo..hi).any { closes(p, leaving = it) }
        }
    }

    /**
     * The one thing the independent measure below is NOT allowed to look at: the
     * single boundary in the library where a ladder changes units — pull_bar v3
     * (negatives, in reps) → v2 (scapular hang, in seconds). Reps and seconds are
     * not commensurable — the density invariant skips this boundary for that
     * reason (`ExerciseEntry.probeOnly`) — and the ×3.75 the raw numbers give
     * across that step is an artefact of the two grids, not a measure of work.
     *
     * Listed by number and pinned against the catalog by
     * `theUnitCrossings_areTheOneBoundaryTheCatalogHas`, because an
     * exclusion that widens on its own is how a sweep goes quiet. Keyed by the
     * UPPER variation, as `AcceptedGap` is.
     */
    object UnitCrossing {

        val boundaries: Map<Pattern, Set<Int>> = mapOf(Pattern.pullBar to setOf(3))

        fun crossed(p: Pattern, from: Int, to: Int): Boolean {
            val lo = minOf(from, to) + 1
            val hi = maxOf(from, to)
            if (lo > hi) return false
            return (lo..hi).any { boundaries[p]?.contains(it) ?: false }
        }
    }

    /**
     * THE INDEPENDENT MEASURE — the work a plan costs, computed here instead of
     * asked of the engine.
     *
     * WHY THE DUPLICATED ARITHMETIC IS DELIBERATE. `Engine.landInVar` searches
     * for its landing under `planLoad(...).total <= budget`, starts that search
     * at the journal's ceiling and only ever walks DOWN, and writes
     * `sets: setsBase` into every landing it returns. `Engine.noHarder` then
     * checks those same three facts — `b.total <= a.total`, `b.load <= journal`,
     * `b.sets <= setsBase` — with the same `Engine.planLoad`. On any landing that
     * came out of `landInVar` the postcondition is therefore true BY
     * CONSTRUCTION, whatever `planLoad` and `landInVar` actually compute.
     *
     * The mutation that proves it: halving `total` in `Engine.planLoad` for one
     * pattern and one variation (`.squat`, variation 2) turns `GoldenTests` and
     * `EngineV3Tests.testFactBelowTheFloorLandsNoHeavier` red, and in this file
     * only `Work` sees it — with the `noHarder` assertions alone, every test here
     * stays green, every sweep in this file included.
     *
     * So this must NOT be "simplified" back into `Engine.planLoad`: routing both
     * sides of the comparison through the function under test is exactly the
     * tautology. What the measure deliberately does not do is second-guess the
     * MODEL — it is the same quantity the engine budgets a landing by (sets ×
     * dose × sides), taken from the other side of the boundary between the test
     * and the code.
     */
    object Work {

        /**
         * Sets, doses and sides straight off the position and the catalog: the
         * plan as the athlete performs it, set by set.
         *
         * Deliberately does not `fit` its argument — a landing is measured
         * exactly as it was written, not as the sanitizer would rewrite it.
         */
        fun of(p: Pattern, q: Position): Int {
            val sets = maxOf(EngineConfig.setsFloor, q.sets - maxOf(0, q.cut))
            val grid = Dose.grid(Library.unit(p, q.variation))
            // The sub-step is off on the top rung of a grid and never asks for
            // more sets than the cut left standing.
            val carrying = if (q.dose >= grid.max) 0 else minOf(maxOf(q.sub, 0), maxOf(0, sets - 1))
            return (0 until sets).map { if (it < carrying) q.dose + grid.step else q.dose }
                .sum() * Library.sides(p, q.variation)
        }
    }

    /**
     * Every position of a pattern that `fit` accepts as its own — the input
     * of the reference's `allPositions`. Doses BELOW a band's entry are in on
     * purpose: a descent lands there. The round-trip filter keeps a position
     * `fit` would rewrite (a band on a non-top variation, a sub-step wider
     * than the sets left standing) out of the sweep, so a failure means
     * "wrong", never "illegal".
     */
    fun allPositions(p: Pattern): List<Position> {
        val out = mutableListOf<Position>()
        for (v in 1..Library.count(p)) {
            val unit = Library.unit(p, v)
            val bands = if (Library.isTop(p, v)) (EngineConfig.setsBase..EngineConfig.setsMax).toList()
                        else listOf(EngineConfig.setsBase)
            for (sets in bands) {
                for (rung in 0 until Dose.rungCount(unit)) {
                    for (sub in 0 until sets) {
                        for (cut in 0..Engine.cutMax(sets = sets)) {
                            val raw = Position(variation = v, sets = sets,
                                               dose = Dose.dose(unit, atRung = rung),
                                               sub = sub, cut = cut)
                            val q = Engine.fit(p, raw)
                            if (q.sub == sub && q.cut == cut) out.add(q)
                        }
                    }
                }
            }
        }
        return out
    }

    /**
     * "The ceiling was shown in every variation" — the most generous journal
     * there is, and therefore the worst case for every "no heavier" check:
     * the landing has the largest possible ceiling to walk down from.
     */
    fun fullJournal(p: Pattern): MutableMap<Pattern, MutableMap<Int, Int>> {
        val row = mutableMapOf<Int, Int>()
        for (v in 1..Library.count(p)) row[v] = Dose.grid(Library.unit(p, v)).max
        return mutableMapOf(p to row)
    }

    fun describe(p: Pattern, q: Position): String =
        "${p.rawValue} v${q.variation} ${q.sets}×${q.dose} sub ${q.sub} cut ${q.cut}"

    /** One pattern moved to `q`, everything else fresh, journal at the ceiling. */
    fun seeded(p: Pattern, q: Position): EngineState {
        val s = EngineState.initial
        s.vars[p] = q.variation
        s.doses[p] = q.dose
        if (q.sets != EngineConfig.setsBase) s.sets[p] = q.sets
        if (q.sub > 0) s.sub[p] = q.sub
        if (q.cut > 0) s.cut[p] = q.cut
        s.shown = fullJournal(p)
        return s
    }

    /**
     * The independent measure first, then the engine's own postcondition.
     *
     * The two are asserted on different domains, and that asymmetry is the
     * whole point (see `Work`):
     *
     *   • `Work` runs everywhere the quantities are commensurable, accepted
     *     gaps included — bounded there by `AcceptedGap.factor` instead of
     *     waved through — and steps aside only at the unit boundary, where
     *     the model itself declines to define a measure;
     *   • `Engine.noHarder` keeps the domain the accepted gaps leave it, and
     *     adds the one thing `Work` cannot see: that the landing is inside the
     *     JOURNAL of what was shown.
     *
     * Returns whether the independent measure actually ran on this cell, so a
     * sweep can assert that its own exclusions did not quietly eat it.
     */
    fun assertDescent(p: Pattern, from: Position, to: Position,
                      shown: Map<Pattern, Map<Int, Int>>, what: () -> String): Boolean {
        val gap = AcceptedGap.crossed(p, from = from.variation, to = to.variation)
        val measurable = !UnitCrossing.crossed(p, from = from.variation, to = to.variation)
        if (measurable) {
            val before = Work.of(p, from)
            val after = Work.of(p, to)
            assertTrue(after <= (if (gap) AcceptedGap.factor * before else before),
                       "${what()}: work $before → $after" +
                       (if (gap) ", past the ×${AcceptedGap.factor} an accepted gap may land" else ""))
        }
        if (!gap) {
            assertTrue(Engine.noHarder(p, from = from, to = to, shown = shown),
                       "${what()}: the engine's own postcondition rejects it")
        }
        return measurable
    }
}

class DescentSweepTest {

    // MARK: - The sweep's own guard

    /**
     * Every check below is only as complete as this enumeration, and an
     * enumeration that quietly loses an axis reads as "greener than before" —
     * which is exactly how a one-shaped sweep can claim to cover "every rung
     * of every ladder" while covering one band, one cut and one sub-step.
     */
    @Test
    fun positionDomain_overEveryLadder_reachesBothBandsTheCutAndTheSubStep() {
        val bands = mutableSetOf<Int>()
        var withCut = 0
        var withSub = 0
        var belowBandEntry = 0
        var total = 0
        for (p in Pattern.allCases) {
            for (q in DescentSweep.allPositions(p)) {
                total += 1
                bands.add(q.sets)
                if (q.cut > 0) withCut += 1
                if (q.sub > 0) withSub += 1
                val entry = Engine.bandStartDose(Library.unit(p, q.variation), sets = q.sets)
                if (q.sets > EngineConfig.setsBase && q.dose < entry) belowBandEntry += 1
                assertTrue(Engine.setsAfterCut(sets = q.sets, cut = q.cut) >= EngineConfig.setsFloor,
                           "${DescentSweep.describe(p, q)} is below the shared floor of sets")
            }
        }
        assertEquals((EngineConfig.setsBase..EngineConfig.setsMax).toSet(), bands,
                     "bands 4 and 5 must be in the domain, on the top variation")
        assertTrue(withCut > 0, "the cut axis must be in the domain")
        assertTrue(withSub > 0, "the sub-step must be in the domain")
        assertTrue(belowBandEntry > 0,
                   "doses below a band's entry must be in the domain — a descent lands there")
        assertTrue(total > 1000, "the domain must be the ladders, not a handful of cells")
    }

    /**
     * The independent measure has exactly one blind spot, and it is pinned to
     * the catalog rather than trusted: the library changes units ONCE, at
     * pull_bar v3 → v2. A ladder that grew a second unit boundary would
     * silently widen the skip in `assertDescent` and take a slice of "no
     * heavier" out of the sweep with it — so a new one has to be a decision
     * here, in writing.
     */
    @Test
    fun theUnitCrossings_areTheOneBoundaryTheCatalogHas() {
        val found = mutableMapOf<Pattern, MutableSet<Int>>()
        for (p in Pattern.allCases) {
            for (v in (2..Library.count(p)).filter { Library.unit(p, it) != Library.unit(p, it - 1) }) {
                found.getOrPut(p) { mutableSetOf() }.add(v)
            }
        }
        assertEquals(DescentSweep.UnitCrossing.boundaries, found,
                     "a unit boundary needs a measure before it needs a skip")
        assertEquals(LoadUnit.reps, Library.unit(Pattern.pullBar, 3), "pull_bar v3 is counted in reps")
        assertEquals(LoadUnit.hold, Library.unit(Pattern.pullBar, 2), "pull_bar v2 is counted in seconds")
    }

    /**
     * Bands are a property of the TOP variation and of nothing else.
     * Asserted on the domain rather than on `setsCeil`, because a sweep that
     * silently enumerated a band on a mid-ladder variation would spend its
     * whole run on positions the engine can never hold.
     */
    @Test
    fun setBands_onEveryVariationBelowTheTop_collapseToTheBase() {
        for (p in Pattern.allCases) {
            for (v in (1..Library.count(p)).filter { !Library.isTop(p, it) }) {
                val raw = Position(variation = v, sets = EngineConfig.setsMax,
                                   dose = Dose.grid(Library.unit(p, v)).min, sub = 0, cut = 0)
                assertEquals(EngineConfig.setsBase, Engine.fit(p, raw).sets,
                             "${p.rawValue} v$v: a band may only stand on the top variation")
            }
            assertEquals(EngineConfig.setsMax, Engine.setsCeil(p, Library.count(p)),
                         "${p.rawValue}: the top variation carries the bands")
        }
    }

    // MARK: - Path 1 · `fallBy`, the rated descent

    /**
     * No heavier, over the WHOLE domain. A single step is the unit of the
     * invariant; several in a row are swept too, because a landing composes
     * with the steps that follow it and the composition is where a band
     * boundary can hide.
     */
    @Test
    fun fallBy_fromEveryPositionOfEveryLadder_neverMakesThePlanHeavier() {
        var measured = 0
        for (p in Pattern.allCases) {
            val journal = DescentSweep.fullJournal(p)
            for (q in DescentSweep.allPositions(p)) {
                for (steps in 1..4) {
                    val to = Engine.fallBy(p, q, steps, shown = journal)
                    if (DescentSweep.assertDescent(p, from = q, to = to, shown = journal) {
                            "${DescentSweep.describe(p, q)} − $steps → ${DescentSweep.describe(p, to)}"
                        }) measured += 1
                }
            }
        }
        // The floor is loose on purpose: it guards against an exclusion eating
        // the sweep, not against a ladder growing.
        assertTrue(measured > 20_000, "only $measured cells reached the independent measure")
    }

    /**
     * A descent may not cross a band DOWNWARD: (4,11) → (3,15) carries one
     * less set and a HIGHER dose per set, which is the defect the gate was
     * written for. Volume inside a band comes off through the cut instead.
     */
    @Test
    fun fallBy_insideABand_takesVolumeThroughTheCutAndNeverRaisesTheDose() {
        for (p in Pattern.allCases) {
            val journal = DescentSweep.fullJournal(p)
            for (q in DescentSweep.allPositions(p).filter { it.sets > EngineConfig.setsBase }) {
                val to = Engine.fallBy(p, q, 1, shown = journal)
                if (to.variation != q.variation) continue
                assertTrue(to.sets <= q.sets,
                           "${DescentSweep.describe(p, q)}: a descent may not add a band")
                assertTrue(to.dose <= q.dose,
                           "${DescentSweep.describe(p, q)} → ${DescentSweep.describe(p, to)}: dose per set rose")
            }
        }
    }

    // MARK: - Path 2 · `fallDoses`, whole rungs

    /**
     * The path the deload, the silent decay and the comeback all walk. It
     * zeroes the sub-step and therefore reaches cells `fallBy` never sees
     * from the same start.
     */
    @Test
    fun fallDoses_fromEveryPositionOfEveryLadder_neverMakesThePlanHeavier() {
        var measured = 0
        for (p in Pattern.allCases) {
            val journal = DescentSweep.fullJournal(p)
            for (q in DescentSweep.allPositions(p)) {
                for (steps in 1..4) {
                    val to = Engine.fallDoses(p, q, steps, shown = journal)
                    if (DescentSweep.assertDescent(p, from = q, to = to, shown = journal) {
                            "${DescentSweep.describe(p, q)} − $steps rungs → ${DescentSweep.describe(p, to)}"
                        }) measured += 1
                }
            }
        }
        assertTrue(measured > 20_000, "only $measured cells reached the independent measure")
    }

    // MARK: - Path 3 · the handle "give me something easier"

    /**
     * The landing under the journal, no heavier, through the handle — from
     * every position and not only from the floor of a variation: the handle
     * carries the CUT across the boundary, so a person on two sets is the
     * case that has to be swept.
     */
    @Test
    fun easierPosition_fromEveryPositionAboveTheFirst_landsInsideTheJournalAndNoHeavier() {
        var measured = 0
        for (p in Pattern.allCases) {
            val journal = DescentSweep.fullJournal(p)
            for (q in DescentSweep.allPositions(p).filter { it.variation > 1 }) {
                val to = assertNotNull(Engine.easierPosition(pattern = p, position = q, shown = journal),
                                       "${DescentSweep.describe(p, q)}: the handle must act above the first variation")
                val grid = Dose.grid(Library.unit(p, to.variation))
                assertEquals(q.variation - 1, to.variation,
                             "${DescentSweep.describe(p, q)}: the handle steps exactly one variation down")
                assertTrue(to.dose <= Engine.landingDose(p, to.variation, shown = journal),
                           "${DescentSweep.describe(p, q)} → ${DescentSweep.describe(p, to)}: above what was shown there")
                assertTrue(to.dose >= grid.min,
                           "${DescentSweep.describe(p, q)} → ${DescentSweep.describe(p, to)}: below the grid floor")
                assertEquals(EngineConfig.setsBase, to.sets,
                             "${DescentSweep.describe(p, q)} → ${DescentSweep.describe(p, to)}: a landing is in the base band")
                if (DescentSweep.assertDescent(p, from = q, to = to, shown = journal) {
                        "${DescentSweep.describe(p, q)} → ${DescentSweep.describe(p, to)}, a handle labelled easier"
                    }) {
                    measured += 1
                }
            }
        }
        assertTrue(measured > 4000, "only $measured cells reached the independent measure")
    }

    /**
     * On the first variation the handle is inert for EVERY pattern: there is
     * nothing below it in the library.
     */
    @Test
    fun easierPosition_onTheFirstVariationOfEveryLadder_isInert() {
        for (p in Pattern.allCases) {
            for (q in DescentSweep.allPositions(p).filter { it.variation == 1 }) {
                assertNull(Engine.easierPosition(pattern = p, position = q, shown = DescentSweep.fullJournal(p)),
                           "${DescentSweep.describe(p, q)}: there is nothing below the first variation")
            }
        }
    }

    // MARK: - The boundary itself, against every shape of journal

    /**
     * The one point from which a descent MUST cross: the floor of a variation
     * on the floor of the sets. Swept against four journals — none, the grid
     * floor, one rung up, the ceiling — because the landing reads the journal
     * and every earlier check pinned only the richest of the four.
     */
    @Test
    fun landing_fromTheBottomOfEveryVariation_staysInsideTheJournalAndTheBaseBand() {
        var crossings = 0
        var measured = 0
        for (p in Pattern.allCases) {
            for (v in 2..Library.count(p)) {
                val below = Dose.grid(Library.unit(p, v - 1))
                for (remembered in listOf<Int?>(null, below.min, below.min + below.step, below.max)) {
                    val shown: MutableMap<Pattern, Map<Int, Int>> = mutableMapOf(p to emptyMap())
                    if (remembered != null) shown[p] = mapOf(v - 1 to remembered)
                    val grid = Dose.grid(Library.unit(p, v))
                    val bottom = Engine.fit(p, Position(variation = v, sets = EngineConfig.setsBase,
                                                        dose = grid.min, sub = 0,
                                                        cut = Engine.cutMax(sets = EngineConfig.setsBase)))
                    val to = Engine.fallBy(p, bottom, 1, shown = shown)
                    crossings += 1
                    val ctx = "${p.rawValue} v$v → ${DescentSweep.describe(p, to)}, journal ${remembered?.toString() ?: "—"}"
                    assertEquals(v - 1, to.variation, "$ctx: a descent off the floor must change variation")
                    assertTrue(to.dose <= Engine.landingDose(p, v - 1, shown = shown),
                               "$ctx: the landing is above the journal")
                    assertTrue(to.dose >= below.min, "$ctx: the landing is below the grid floor")
                    assertEquals(EngineConfig.setsBase, to.sets, "$ctx: a landing is in the base band")
                    assertEquals(0, to.sub, "$ctx: a descent takes the sub-step")
                    assertTrue(Engine.setsAfterCut(sets = to.sets, cut = to.cut) >= EngineConfig.setsFloor,
                               "$ctx: the floor of sets was broken")
                    if (DescentSweep.AcceptedGap.closes(p, leaving = v)) {
                        // An accepted gap: there is nothing below the grid floor
                        // to land on, and that is the only thing assertable here
                        // ABOUT THE DOSE. The work such a landing costs is
                        // bounded all the same, in `assertDescent`.
                        assertEquals(below.min, to.dose, "$ctx: an accepted gap must lie on the grid floor")
                    }
                    if (DescentSweep.assertDescent(p, from = bottom, to = to, shown = shown) { ctx }) measured += 1
                }
            }
        }
        assertTrue(crossings > 0, "no boundary was swept at all")
        assertTrue(measured > 150,                         // 192 of the 196
                   "only $measured crossings reached the independent measure")
    }

    /**
     * THE NEGATIVE CONTROL of the no-heavier landing, and the reason the third
     * clause of `noHarder` cannot be deleted in silence.
     *
     * Every other check in this file measures what `landInVar` DOES, and the
     * behaviour of `landInVar` does not depend on the predicate: with
     * `b.total <= a.total` deleted, every other test here stays green. The
     * predicate must also REJECT the landing `landInVar` walks down from — the
     * journal's ceiling on the full band — wherever that landing weighs more
     * than the position left behind.
     */
    @Test
    fun noHarder_againstTheLandingItReplaced_rejectsIt() {
        var rejections = 0
        for (p in Pattern.allCases) {
            for (v in 2..Library.count(p)) {
                val below = Dose.grid(Library.unit(p, v - 1))
                for (remembered in listOf(below.min, below.min + below.step, below.max)) {
                    val shown: Map<Pattern, Map<Int, Int>> = mapOf(p to mapOf(v - 1 to remembered))
                    val grid = Dose.grid(Library.unit(p, v))
                    val bottom = Engine.fit(p, Position(variation = v, sets = EngineConfig.setsBase,
                                                        dose = grid.min, sub = 0,
                                                        cut = Engine.cutMax(sets = EngineConfig.setsBase)))
                    val old = Engine.fit(p, Position(variation = v - 1, sets = EngineConfig.setsBase,
                                                     dose = Engine.landingDose(p, v - 1, shown = shown),
                                                     sub = 0, cut = 0))
                    if (Engine.planLoad(p, old).total <= Engine.planLoad(p, bottom).total) continue
                    rejections += 1
                    assertFalse(Engine.noHarder(p, from = bottom, to = old, shown = shown),
                                "${p.rawValue} v$v: the predicate ACCEPTED the landing on the journal's ceiling " +
                                "${old.dose}×${old.sets}, work " +
                                "${Engine.planLoad(p, bottom).total} → ${Engine.planLoad(p, old).total}")
                }
            }
        }
        assertTrue(rejections > 0, "the negative control never ran — the predicate is unbound")
    }
}
