//
//  A position and its measure.
//
//  A position is FIVE coordinates — variation, sets, dose, sub-step, cut.
//  `sets` is one of them because a set band cannot be read off the dose:
//  `4×11` and `3×11` carry one dose and different volumes, and entering a band
//  LOWERS the dose. It is stored sparsely with a base of 3.
//
//  The MEASURE is how many growth events separate a position from the very
//  bottom of its ladder. It is a measure, not an encoding: it has no inverse
//  and needs none. Do not reintroduce a single number per pattern.
//

package com.dredfit.core

import kotlin.math.max
import kotlin.math.min

/**
 * Immutable on purpose: Swift's `Position` is a value type, and a Kotlin
 * class with `var` fields would alias where the Swift copy does not. A Swift
 * `var pos = old; pos.dose = d` is `old.copy(dose = d)` here.
 */
data class Position(
    /** 1-based index along the pattern's ladder. */
    val variation: Int,
    /** Sets in the plan. Base 3; bands 4 and 5 exist only on the TOP variation. */
    val sets: Int,
    /** Reps — or seconds — per set. */
    val dose: Int,
    /** The sub-step: the first `sub` sets carry one rung more. */
    val sub: Int,
    /** Sets taken off — the second axis of volume. */
    val cut: Int,
)

/** The same invariant on the way in and after every step of every transition. */
internal fun Engine.fit(p: Pattern, pos: Position): Position {
    val v = Library.index(pattern = p, variation = pos.variation)
    val unit = Library.unit(p, v)
    val sets = min(max(pos.sets, EngineConfig.setsBase), setsCeil(p, v))
    val cut = effCut(sets = sets, cut = pos.cut)
    val dose = Dose.clamped(unit, Dose.snap(unit, pos.dose))
    val raw = Position(variation = v, sets = sets, dose = dose, sub = pos.sub, cut = cut)
    return Position(variation = v, sets = sets, dose = dose,
                    sub = effSub(p, raw, sets = null), cut = cut)
}

internal fun Engine.same(a: Position, b: Position): Boolean = a == b

/** On the top rung of a grid the sub-step is DISABLED: the next rung belongs to
 *  another band or another variation, and one exercise may never mix two. */
internal fun Engine.subDisabled(p: Pattern, pos: Position): Boolean =
    pos.dose >= Dose.grid(Library.unit(p, pos.variation)).max

/** The sub-step actually in force — never more sets than the cut left standing. */
internal fun Engine.effSub(p: Pattern, pos: Position, sets: Int?): Int {
    if (subDisabled(p, pos)) return 0
    val top = max(0, (sets ?: (pos.sets - pos.cut)) - 1)
    return min(max(pos.sub, 0), top)
}

/** The ordinal INSIDE a variation. Doses below a band's entry are legal — a
 *  descent lands there — and the term then goes negative. */
internal fun Engine.ordInVar(p: Pattern, pos: Position): Int {
    val unit = Library.unit(p, pos.variation)
    val g = Dose.grid(unit)
    val topRung = Dose.rung(unit, dose = g.max)
    var o = 0
    var band = EngineConfig.setsBase
    while (band < pos.sets) {
        o += (topRung - Dose.rung(unit, dose = bandStartDose(unit, sets = band))) * band + 1
        band += 1
    }
    o += (Dose.rung(unit, dose = pos.dose) -
        Dose.rung(unit, dose = bandStartDose(unit, sets = pos.sets))) * pos.sets +
        pos.sub
    return o
}

/** What a whole variation costs in growth events, the probe out of it included. */
internal fun Engine.varSpan(p: Pattern, v: Int): Int =
    (Dose.rungCount(Library.unit(p, v)) - 1) * EngineConfig.setsBase + 1

internal fun Engine.varBase(p: Pattern, v: Int): Int {
    var o = 0
    for (u in 1 until Library.index(pattern = p, variation = v)) o += varSpan(p, u)
    return o
}

/** The full measure: the walk along the ladder, less the sets taken off. */
internal fun Engine.posOrd(p: Pattern, pos: Position): Int =
    varBase(p, pos.variation) + ordInVar(p, pos) - pos.cut

/** Per-set doses, DESCENDING — the first `sub` sets carry the next rung. A
 *  uniform plan answers null ("nothing to say"). */
internal fun Engine.planLoads(p: Pattern, pos: Position, sets: Int): List<Int>? {
    val s = effSub(p, pos, sets = sets)
    if (s <= 0) return null
    val step = Dose.grid(Library.unit(p, pos.variation)).step
    return (0 until sets).map { if (it < s) pos.dose + step else pos.dose }
}
