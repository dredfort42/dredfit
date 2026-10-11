//
//  A fact belongs to the set it happened on.
//
//  Port of ios/Dredfit/SetFacts.swift: the stored shapes and their
//  sanitizers, how a set's number is read and written, and the fold of the
//  per-set facts into the one number the engine takes. The hold rules are
//  SetFactsHolds.kt, the absence and the settlement SetFactsInterruption.kt.
//  The reasoning behind every rule is in the Swift file. (`SetFactsLabel`,
//  the SwiftUI view at its end, arrives with the rating screen.)
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

    /** Whether `count` more skipped sets can be RECORDED as skipped sets: a
     *  movement counts as trained only while the floor's worth of sets
     *  survives. Counted on the PLAN IN FRONT OF THE PERSON. */
    fun skipFits(count: Int, of: Int, alreadySkipped: Int): Boolean =
        of - alreadySkipped - count >= EngineConfig.setsFloor

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

    /** What is in force for set `index` when that differs from the SET'S OWN
     *  plan; null when the set simply runs to plan. */
    fun offPlan(facts: Map<Pattern, List<Int>>, ex: SessionExercise, set: Int): Int? {
        val value = inForce(facts, ex, set)
        return if (value == ex.plannedLoad(set = set)) null else value
    }

    /** Whether recorded sets differ from THIS plan, set for set — never
     *  against the flat base. */
    fun differs(values: List<Int>, from: SessionExercise): Boolean =
        values.withIndex().any { (i, v) -> v != from.plannedLoad(set = i) }

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

    // MARK: - Writing

    /**
     * Records `value` for the set under way and nothing else; the sets before
     * it keep what they ran at and are filled in first, AS THE SCREEN READ
     * THEM (`inForce`, set for set — never the last number carried forward,
     * or 35-30-30 held as asked would read 35-35-30). Everything landing back
     * on the plan, compared per set, is nothing said at all.
     */
    fun recording(value: Int, facts: Map<Pattern, List<Int>>, ex: SessionExercise, set: Int): Map<Pattern, List<Int>> {
        val out = LinkedHashMap(facts)
        val values = (facts[ex.pattern] ?: emptyList()).toMutableList()
        val index = maxOf(set, 0)
        while (values.size < index) {
            val planned = ex.plannedLoad(set = values.size)
            values += minOf(values.lastOrNull() ?: planned, planned)
        }
        val written = values.take(index) + value
        val onPlan = written.withIndex().all { (i, v) -> v == ex.plannedLoad(set = i) }
        if (onPlan) out.remove(ex.pattern) else out[ex.pattern] = written
        return out
    }

    /**
     * Records ONE set and leaves every other set of the exercise standing —
     * the summary's writer, where every set is already behind. The exercise
     * is frozen as the cards read it (`inForce`) and one value changes; a
     * record back on the plan set for set is dropped. Bounded by the
     * exercise's own length.
     */
    fun recordingSet(value: Int, facts: Map<Pattern, List<Int>>, ex: SessionExercise, set: Int): Map<Pattern, List<Int>> {
        val index = maxOf(set, 0)
        val sets = minOf(maxOf(ex.sets, 1), EngineConfig.setsMax)
        if (index >= sets) return facts
        val values = (0 until sets).map { inForce(facts, ex, set = it) }.toMutableList()
        values[index] = value
        val out = LinkedHashMap(facts)
        val onPlan = values.withIndex().all { (i, v) -> v == ex.plannedLoad(set = i) }
        if (onPlan) out.remove(ex.pattern) else out[ex.pattern] = values
        return out
    }

    // MARK: - The collapse

    /** How long ONE side of a per-side hold runs: what the first side ran,
     *  never longer than the plan, floored at the hold corridor's minimum
     *  (a 3 s side could neither be stored nor stopped). */
    fun holdSideSeconds(planned: Int, firstSideHeld: Int?): Int {
        if (firstSideHeld == null) return planned
        val floor = corridor(LoadUnit.hold).first
        return maxOf(minOf(firstSideHeld, planned), minOf(floor, planned))
    }

    /** A number above the plan of THIS set, on a set that is not the last.
     *  The note built on it must not claim the engine measures order — the
     *  fold is the mean. */
    fun maximumOutOfOrder(value: Int, ex: SessionExercise, set: Int): Boolean =
        set < ex.sets - 1 && value > ex.plannedLoad(set = set)

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

    /** The knowable half of the probe's condition: a fold below the plan's
     *  mean is already the step down the engine will take. */
    fun foldFallsShort(facts: Map<Pattern, List<Int>>, of: SessionExercise, skipping: Set<Int>): Boolean {
        val fold = override(facts, of, skipping) ?: return false
        return fold < of.plannedVolume.toDouble() / maxOf(of.sets, 1).toDouble()
    }

    /** What the PROBE set records when it ends: its own target, unless a
     *  number was entered by hand. `isProbe` is a parameter on purpose — the
     *  half "nothing else records itself" is the one a refactor loses. */
    fun recordingProbe(probes: Map<Pattern, Int>, pattern: Pattern, isProbe: Boolean, target: Int): Map<Pattern, Int> {
        if (!isProbe || probes[pattern] != null) return probes
        return LinkedHashMap(probes).also { it[pattern] = target }
    }

    /** "The whole plan, or more": nothing set aside, no set dropped, every
     *  exercise reaching the VOLUME it was asked for. The probe is outside it. */
    fun didFullPlan(facts: Map<Pattern, List<Int>>, skips: Map<Pattern, Int>, skipped: Set<Pattern>,
                    exercises: List<SessionExercise>): Boolean {
        if (skipped.isNotEmpty() || !skips.values.all { it <= 0 }) return false
        return exercises.all { ex -> allSets(facts, ex).sum() >= ex.plannedVolume }
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
