//
//  What a hold's clock is set to, what a tap ending it is worth, and how far
//  its summary may correct it. Port of ios/Dredfit/SetFacts+Holds.swift,
//  where every rule carries its reason.
//

package com.dredfit.workout

import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise

// MARK: - Correcting a hold on its summary

/**
 * The range a hold's recorded seconds may be corrected within on the
 * movement's summary. ONLY THE LAST WORKING SET is corrected: down to the
 * corridor's floor, and up as far as nothing stopped it — the corridor when
 * no rest followed, what its last side ran when one did (the estimate plus
 * the reach allowance when a thumb ended it).
 */
fun SetFacts.correctionRange(measured: Int, isLastSet: Boolean, restFollowed: Boolean, endedByTap: Boolean): IntRange {
    val corridor = corridor(LoadUnit.hold)
    val fixed = minOf(maxOf(measured, corridor.first), corridor.last)
    if (!isLastSet) return fixed..fixed
    if (!restFollowed) return corridor
    val ran = if (endedByTap) measured + holdReachSecondsConst else measured
    return corridor.first..minOf(maxOf(ran, corridor.first), corridor.last)
}

// MARK: - What a hold is worth when a thumb ends it

/** Seconds taken off a hold that ended by TAP: the tap comes after the
 *  effort stopped. The honest direction is DOWN. */
private const val holdReachSecondsConst = 3

val SetFacts.holdReachSeconds: Int get() = holdReachSecondsConst

/** What a hold ended by tap records: never below the corridor's floor. */
fun SetFacts.holdEndedByTap(heldSeconds: Int): Int =
    maxOf(corridor(LoadUnit.hold).first, heldSeconds - holdReachSecondsConst)

// MARK: - The set the run opens by itself

/** Whether the hands-free run opens the set at `index` BY ITSELF — one
 *  question, two callers (the rest's end and the rest's pause). The probe is
 *  never opened by the run. */
fun SetFacts.runOpensSet(index: Int, of: SessionExercise, running: Boolean): Boolean {
    if (!running || of.unit != LoadUnit.hold) return false
    val total = of.sets + (if (of.probe == null) 0 else 1)
    if (index < 0 || index >= total) return false
    return !(of.probe != null && index >= of.sets)
}

/** How much of a rest's 3-2-1 the app may have missed before the go it
 *  played stops counting as heard. */
private const val restGoHeardWithinSecConst = 3.0

val SetFacts.restGoHeardWithinSec: Double get() = restGoHeardWithinSecConst

/** Whether the set a rest hands over to still needs counting in: after a
 *  TAP, or when the app was away across the end of the rest. */
fun SetFacts.restHandsOverWithCountIn(endedByTap: Boolean, overshootSec: Double): Boolean =
    endedByTap || overshootSec > restGoHeardWithinSecConst

// MARK: - The time a hold is set to run

/**
 * The seconds set `index` of a hold counts down from. Without a declaration
 * this is `inForce`; with one, THE DECLARATION STANDS IN FOR THE PLAN, and a
 * set cut short carries its number onto the sets after it, capped by what was
 * declared. A declaration governs a HOLD only, and is clamped where it is
 * read — it comes back off disk in the snapshot.
 */
fun SetFacts.holdTarget(facts: Map<Pattern, List<Int>>, ex: SessionExercise, set: Int, declared: Int?): Int {
    if (ex.unit != LoadUnit.hold || declared == null) return inForce(facts, ex, set)
    val corridor = corridor(LoadUnit.hold)
    val ceiling = minOf(maxOf(declared, corridor.first), corridor.last)
    val values = facts[ex.pattern] ?: emptyList()
    val index = maxOf(set, 0)
    if (index <= 0 || values.isEmpty()) return ceiling
    return minOf(values[minOf(index, values.size) - 1], ceiling)
}
