//
//  Descent and the "no harder" gate.
//
//  There are no TIER FLOORS. A descent through a variation boundary lands in
//  the variation below with the JOURNAL OF WHAT WAS SHOWN there as its
//  ceiling (the grid floor where the person has never been), walked down
//  until the plan weighs no more than the one being left — `landInVar`, which
//  also names the boundaries where nothing fits. The one crossing that skips
//  it is a comeback's landing ceiling (Breaks.kt).
//

package com.dredfit.core

import kotlin.math.max

/** A variation's point of return. The grid floor when the trainee has never
 *  been there; the journal is clamped by the dose FLOOR. */
internal fun Engine.landingDose(p: Pattern, v: Int, shown: Map<Pattern, Map<Int, Int>>): Int {
    val unit = Library.unit(p, v)
    val recorded = shown[p]?.get(v) ?: return Dose.grid(unit).min
    return Dose.clamped(unit, Dose.snap(unit, recorded))
}

/**
 * THE LANDING DOES NOT ADD WORK. The journal gives a CEILING, not the dose
 * itself. Two axes, in this order: dose first at the full band, then the cut.
 * When no pair fits, the grid floor at the sets they were doing — an accepted
 * gap (two hinge boundaries and one pull_bar unit boundary, ×2.00 at worst).
 */
internal fun Engine.landInVar(p: Pattern, v: Int, shown: Map<Pattern, Map<Int, Int>>,
                              from: Position? = null): Position {
    val vi = Library.index(pattern = p, variation = v)
    val unit = Library.unit(p, vi)
    val grid = Dose.grid(unit)
    val ceiling = landingDose(p, vi, shown = shown)
    fun make(dose: Int, cut: Int): Position =
        Position(variation = vi, sets = EngineConfig.setsBase, dose = dose, sub = 0, cut = cut)
    if (from == null) return make(ceiling, 0)
    val budget = planLoad(p, fit(p, from)).total
    val carried = effCut(sets = EngineConfig.setsBase, cut = from.cut)
    for (cut in (if (carried == 0) listOf(0) else listOf(0, carried))) {
        var d = ceiling
        while (d >= grid.min) {
            if (planLoad(p, make(d, cut)).total <= budget) return make(d, cut)
            d -= grid.step
        }
    }
    return make(grid.min, carried)
}

/**
 * Dose is spent before sets: the reverse of a growth event while there is
 * room inside the variation; on the dose floor a set taken off; on the floor
 * of the variation the variation below, landing under its journal. A descent
 * deliberately does NOT cross a band downward — (4,11) → (3,15) would raise
 * the dose per set.
 */
internal fun Engine.fallBy(p: Pattern, pos: Position, n: Int,
                           shown: Map<Pattern, Map<Int, Int>>): Position {
    var cur = fit(p, pos)
    var k = max(0, n)
    while (k > 0) {
        val g = Dose.grid(Library.unit(p, cur.variation))
        if (cur.sub > 0) {
            cur = fit(p, Position(variation = cur.variation, sets = cur.sets,
                                  dose = cur.dose, sub = cur.sub - 1, cut = cur.cut))
        } else if (cur.dose > g.min) {
            // The reverse of a growth event: (dose d, sub 0) → (d−1, band−1).
            cur = fit(p, Position(variation = cur.variation, sets = cur.sets,
                                  dose = cur.dose - g.step, sub = cur.sets - 1, cut = cur.cut))
        } else if (setsAfterCut(sets = cur.sets, cut = cur.cut) > EngineConfig.setsFloor) {
            cur = fit(p, Position(variation = cur.variation, sets = cur.sets,
                                  dose = cur.dose, sub = cur.sub, cut = cur.cut + 1))
        } else if (cur.variation > 1) {
            cur = landInVar(p, cur.variation - 1, shown = shown, from = cur)
        } else {
            break                           // the bottom of the whole ladder
        }
        k -= 1
    }
    return fit(p, cur)
}

/** Descent by WHOLE rungs of dose (deload, comeback, silent decay). The
 *  sub-step is zeroed; on the dose floor a set taken off becomes the rung. */
internal fun Engine.fallDoses(p: Pattern, pos: Position, n: Int,
                              shown: Map<Pattern, Map<Int, Int>>): Position {
    var cur = fit(p, Position(variation = pos.variation, sets = pos.sets,
                              dose = pos.dose, sub = 0, cut = pos.cut))
    var k = max(0, n)
    while (k > 0) {
        val g = Dose.grid(Library.unit(p, cur.variation))
        if (cur.dose > g.min) {
            cur = fit(p, Position(variation = cur.variation, sets = cur.sets,
                                  dose = cur.dose - g.step, sub = 0, cut = cur.cut))
        } else if (setsAfterCut(sets = cur.sets, cut = cur.cut) > EngineConfig.setsFloor) {
            cur = fit(p, Position(variation = cur.variation, sets = cur.sets,
                                  dose = cur.dose, sub = 0, cut = cur.cut + 1))
        } else if (cur.variation > 1) {
            cur = landInVar(p, cur.variation - 1, shown = shown, from = cur)
        } else {
            break
        }
        k -= 1
    }
    return cur
}

/** What a plan weighs, in the units of the measure. */
internal data class PlanLoad(val sets: Int, val load: Int, val total: Int)

internal fun Engine.planLoad(p: Pattern, pos: Position): PlanLoad {
    val sets = setsAfterCut(sets = pos.sets, cut = pos.cut)
    val s = effSub(p, pos, sets = sets)
    val step = Dose.grid(Library.unit(p, pos.variation)).step
    val sides = Library.sides(p, pos.variation)
    return PlanLoad(sets = sets, load = pos.dose, total = (sets * pos.dose + s * step) * sides)
}

/**
 * The gate is a CHECK rather than a filter: the paths of descent are built to
 * pass it, and the tests call it on what they produce — no production code
 * does. The accepted gaps `landInVar` names are the only landings that fail it.
 */
internal fun Engine.noHarder(p: Pattern, from: Position, to: Position,
                             shown: Map<Pattern, Map<Int, Int>>): Boolean {
    val a = planLoad(p, fit(p, from))
    val b = planLoad(p, fit(p, to))
    if (to.variation > from.variation) return false        // up is not a descent
    if (to.variation == from.variation) return b.load <= a.load && b.total <= a.total
    // Without `b.total <= a.total` the gate would pass every landing.
    val journal = landingDose(p, to.variation, shown = shown)
    return b.load <= journal && b.sets <= EngineConfig.setsBase && b.total <= a.total
}
