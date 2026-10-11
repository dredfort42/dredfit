//
//  The set axis: the cut, the bands on the top variation, and growth.
//
//  NO FUNCTION HERE CARRIES A DEFAULT ARGUMENT, deliberately. An omitted floor
//  argument was a repeated defect class — a compile error is a stronger guard
//  than a grep, and it stays that way now that the floor is shared by every
//  caller. The same holds for this port.
//

package com.dredfit.core

import kotlin.math.max
import kotlin.math.min

// MARK: - The cut

/** Nobody cuts below the shared floor of sets. */
fun Engine.cutMax(sets: Int): Int = max(0, sets - EngineConfig.setsFloor)

internal fun Engine.effCut(sets: Int, cut: Int): Int = min(max(cut, 0), cutMax(sets = sets))

internal fun Engine.setsAfterCut(sets: Int, cut: Int): Int = sets - effCut(sets = sets, cut = cut)

/** The one and only clamp on a set count, so the floor holds for the
 *  COMPOSITION of every mechanism that cuts sets. */
internal fun Engine.clampSets(n: Int, floor: Int): Int = max(floor, n)

// MARK: - The bands on the top variation

/** Once the dose tops out on the TOP variation, growth continues in sets:
 *  `sets → sets+1` at `⌊sets × ceiling / (sets+1)⌋`, snapped down to the grid. */
internal fun Engine.bandEntryDose(unit: LoadUnit, setsFrom: Int): Int =
    Dose.snap(unit, (setsFrom * Dose.grid(unit).max) / (setsFrom + 1))

/** Where a band starts: the grid floor for the base, the band entry dose above. */
internal fun Engine.bandStartDose(unit: LoadUnit, sets: Int): Int =
    if (sets <= EngineConfig.setsBase) Dose.grid(unit).min else bandEntryDose(unit, setsFrom = sets - 1)

/** Bands exist only on the top variation of a ladder. */
internal fun Engine.setsCeil(p: Pattern, v: Int): Int =
    if (Library.isTop(p, v)) EngineConfig.setsMax else EngineConfig.setsBase

// MARK: - Growth

/**
 * Sets come back FIRST, and only then does the dose grow — at most ONE set per
 * session, and only once the hold has run out. The sub-step is counted against
 * the BAND, so under a cut, while the hold ticks, an event can land on a set
 * the cut hides and be lost — kept on purpose (see SetsHandle.swift).
 *
 * Growth NEVER crosses a variation: the only way into a new one is a probe.
 * `bandCeil` is the highest band this growth may enter (a push gets the pull
 * slot's sets as they stand after the session).
 */
internal fun Engine.riseBy(p: Pattern, pos: Position, n: Int,
                           allowSetsBack: Boolean, bandCeil: Int): Position {
    var cur = fit(p, pos)
    var k = max(0, n)
    val back = if (allowSetsBack) minOf(cur.cut, k, EngineConfig.setsBackPerSession) else 0
    if (back > 0) {
        cur = cur.copy(cut = cur.cut - back)
        k = 0
    }
    while (k > 0) {
        val unit = Library.unit(p, cur.variation)
        val g = Dose.grid(unit)
        if (cur.dose < g.max) {
            // A sub-step: +1 rep (or +5 s) in ONE set, counted against the BAND.
            cur = if (cur.sub + 1 < cur.sets) {
                cur.copy(sub = cur.sub + 1)
            } else {
                cur.copy(dose = cur.dose + g.step, sub = 0)
            }
            k -= 1
            continue
        }
        if (Library.isTop(p, cur.variation) && cur.sets < min(EngineConfig.setsMax, bandCeil)) {
            val from = cur.sets
            cur = cur.copy(sets = from + 1, dose = bandEntryDose(unit, setsFrom = from), sub = 0)
            k -= 1
            continue
        }
        break   // parked on the ceiling: waiting for a probe or the pull, or at the top of the scale
    }
    return fit(p, cur)
}

/** The hold is armed by sets coming back ON SCREEN: the cut went down and the
 *  plan shows more sets than before. One rule for the appearance and the
 *  cross-credit. */
internal fun Engine.setsCameBack(from: Position, to: Position): Boolean =
    to.cut < from.cut &&
        setsAfterCut(sets = to.sets, cut = to.cut) > setsAfterCut(sets = from.sets, cut = from.cut)

/**
 * Growth BOUNDED BY THE JOURNAL — the cross-credit, the one place a position
 * rises WITHOUT the pattern appearing. A set it returns ENDS it, as a set
 * return ends growth in `riseBy`.
 */
internal fun Engine.riseWithinJournal(p: Pattern, pos: Position, n: Int,
                                      allowSetsBack: Boolean,
                                      shown: Map<Pattern, Map<Int, Int>>): Position {
    var cur = fit(p, pos)
    val row = shown[p] ?: emptyMap()
    fun allowed(q: Position): Boolean {
        val g = Dose.grid(Library.unit(p, q.variation))
        val journal = max(g.min, min(row[q.variation] ?: g.min, g.max))
        return q.dose <= journal
    }
    var k = max(0, n)
    while (k > 0) {
        // Only a pull branch is ever credited, and the cap reaches pushes
        // alone, so no band here waits for anything.
        val step = riseBy(p, cur, 1, allowSetsBack = allowSetsBack, bandCeil = EngineConfig.setsMax)
        if (same(step, cur) || !allowed(step)) break
        val returned = step.cut < cur.cut
        cur = step
        k -= 1
        if (returned) break
    }
    return cur
}
