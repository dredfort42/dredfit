//
//  A fact belongs to the set it happened on.
//
//  Port of the READING half of ios/Dredfit/SetFacts.swift — what the journal,
//  the snapshot and a changed rating need: the stored shapes, their
//  sanitizers, and the fold of per-set facts into the one number the engine
//  takes. The writing half (`recording`, the hold rules) arrives with the
//  workout screens. The reasoning behind every rule is in the Swift file.
//

package com.dredfit.workout

import com.dredfit.core.EngineConfig
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.core.roundedAwayFromZero

object SetFacts {

    /** What the journal and the snapshot keep of the skipped sets: sorted
     *  indices, and nothing at all when no set was skipped. */
    fun stored(sets: Map<Pattern, Set<Int>>): Map<Pattern, List<Int>>? =
        if (sets.isEmpty()) null else sets.mapValues { it.value.sorted() }

    /** The skipped sets the fold and every display leave out: the ones with
     *  no number the person entered for them before the skip. */
    fun leftOut(skipped: Map<Pattern, Set<Int>>, keeping: Map<Pattern, Set<Int>>): Map<Pattern, Set<Int>> {
        val out = LinkedHashMap<Pattern, Set<Int>>()
        for ((pattern, sets) in skipped) {
            val left = sets - (keeping[pattern] ?: emptySet())
            if (left.isNotEmpty()) out[pattern] = left
        }
        return out
    }

    // MARK: - The corridors

    /** The corridor a reportable number lives in. */
    fun corridor(unit: LoadUnit): IntRange = if (unit == LoadUnit.hold) 5..90 else 0..30

    /** `value` snapped to one unit and held inside its corridor. */
    fun snap(value: Double, unit: LoadUnit): Int {
        val corridor = corridor(unit)
        if (!value.isFinite()) return corridor.first
        // Clamped while still a Double: off disk a snapshot can carry any number.
        val stepped = roundedAwayFromZero(value)
        return minOf(maxOf(stepped, corridor.first.toDouble()), corridor.last.toDouble()).toInt()
    }

    /** The per-set shape as the app is willing to read it back off disk. */
    fun sanitized(facts: Map<Pattern, List<Int>>): Map<Pattern, List<Int>> {
        val out = LinkedHashMap<Pattern, List<Int>>()
        for ((pattern, values) in facts) {
            val clean = values.take(EngineConfig.setsMax).map { minOf(maxOf(it, 0), EngineConfig.countMax) }
            if (clean.isNotEmpty()) out[pattern] = clean
        }
        return out
    }

    /** Swift's `sanitized(skips:)`: no movement loses more sets than the
     *  scale has bands, and a count of none is no fact. */
    fun sanitizedSkips(skips: Map<Pattern, Int>): Map<Pattern, Int> {
        val out = LinkedHashMap<Pattern, Int>()
        for ((pattern, count) in skips) {
            val clean = minOf(maxOf(count, 0), EngineConfig.setsMax)
            if (clean > 0) out[pattern] = clean
        }
        return out
    }

    /** Swift's `sanitized(skippedSets:)`: indices an exercise can have. */
    fun sanitizedSkippedSets(skippedSets: Map<Pattern, List<Int>>): Map<Pattern, Set<Int>> {
        val out = LinkedHashMap<Pattern, Set<Int>>()
        for ((pattern, indices) in skippedSets) {
            val clean = indices.filter { it in 0 until EngineConfig.setsMax }.toSet()
            if (clean.isNotEmpty()) out[pattern] = clean
        }
        return out
    }

    // MARK: - Reading

    /** The number set `index` runs at. THE CARRY-FORWARD IS ASYMMETRIC: a
     *  number below the plan carries onto the sets ahead, one above it stays
     *  on its own set. */
    fun inForce(facts: Map<Pattern, List<Int>>, ex: SessionExercise, set: Int): Int {
        val index = maxOf(set, 0)
        val values = facts[ex.pattern]
        if (values.isNullOrEmpty()) return ex.plannedLoad(set = index)
        if (index < values.size) return values[index]
        return minOf(values.last(), ex.plannedLoad(set = index))
    }

    /** Every set of the exercise — bounded by the scale, not by the record. */
    fun allSets(facts: Map<Pattern, List<Int>>, ex: SessionExercise): List<Int> {
        val sets = minOf(maxOf(ex.sets, 1), EngineConfig.setsMax)
        return (0 until sets).map { inForce(facts, ex, set = it) }
    }

    /** Every set but the skipped ones with no number of their own, each with
     *  its index; with every set skipped, every set reads as in `allSets`. */
    fun performed(facts: Map<Pattern, List<Int>>, ex: SessionExercise,
                  skipping: Set<Int>): List<Pair<Int, Int>> {
        val every = allSets(facts, ex).mapIndexed { i, v -> i to v }
        val done = every.filter { it.first !in skipping }
        return done.ifEmpty { every }
    }

    /** The RAW mean of the performed sets — the engine snaps it. A mean below
     *  the base that would round onto it reports nothing. */
    fun override(facts: Map<Pattern, List<Int>>, ex: SessionExercise, skipping: Set<Int>): Double? {
        if (facts[ex.pattern].isNullOrEmpty()) return null
        val values = performed(facts, ex, skipping).map { it.second }
        if (values.isEmpty()) return null
        val raw = values.fold(0.0) { acc, v -> acc + v } / values.size
        if (raw < ex.load && snap(raw, ex.unit) >= ex.load) return null
        return raw
    }

    /** The whole session's `overrides`, keyed the way the engine wants them.
     *  A pattern whose fold reports nothing is absent, as Swift's
     *  `result[p] = nil` leaves it. */
    fun overrides(facts: Map<Pattern, List<Int>>, skipping: Map<Pattern, Set<Int>>,
                  exercises: List<SessionExercise>): Map<Pattern, Double> {
        val result = LinkedHashMap<Pattern, Double>()
        for (ex in exercises) {
            if (facts[ex.pattern] == null) continue
            val value = override(facts, ex, skipping[ex.pattern] ?: emptySet())
            if (value != null) result[ex.pattern] = value else result.remove(ex.pattern)
        }
        return result
    }
}
