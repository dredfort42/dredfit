//
//  Exercise catalog: ten patterns, 59 positions along their ladders.
//  Base language English; the translations live in the String Catalog
//  ios/DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings, keyed
//  by these very strings — the app phase generates Android resources from it.
//  Technique: 3 steps + 2 common mistakes per position. Mirrors LIBRARY and
//  TECHNIQUE in the reference adaptive_engine.js.
//
//  The ladder is the ONLY place a difficulty measure lives, and it has exactly
//  two jobs: the ORDER of the rungs, and the density invariant
//  (`w(N+1)/w(N) <= 1.50`). No dose is ever computed from `w`.
//

package com.dredfit.core

import kotlin.math.max
import kotlin.math.min

/** Three steps and two common mistakes. An assistance rung inherits the
 *  technique of the variation it assists with ONE line replaced, and
 *  `assisted` is the only way to express that: two copies of one text drift. */
internal data class Technique(val steps: List<String>, val mistakes: List<String>) {
    fun assisted(step: Int, line: String): Technique {
        val replaced = steps.toMutableList()
        replaced[step] = line
        return Technique(steps = replaced, mistakes = mistakes)
    }
}

data class ExerciseVariation(
    val name: String,
    val unilateral: Boolean,
    /** The unit is a property of the VARIATION, not of the pattern: a ladder
     *  may cross from seconds to reps once, and `pull_bar` does. */
    val unit: LoadUnit,
    /** Share of body weight on the working link, per rep — per second for a
     *  hold. Orders the ladder and bounds its density; never a dose. */
    val w: Double,
    val steps: List<String>,
    val mistakes: List<String>,
)

data class ExerciseEntry(
    val pattern: Pattern,
    /** Index = variation − 1. Variations are 1-based everywhere else. */
    val variations: List<ExerciseVariation>,
) {
    val count: Int get() = variations.size

    /** Total by construction: reading the library must never trap. */
    fun variation(v: Int): ExerciseVariation =
        variations[Library.index(pattern = pattern, variation = v) - 1]

    fun unit(forVariation: Int): LoadUnit = variation(forVariation).unit

    /** The one boundary the density invariant skips — DERIVED from the units
     *  rather than carried as a flag, so the copy cannot come back. */
    fun probeOnly(variation: Int): Boolean {
        val i = Library.index(pattern = pattern, variation = variation)
        return i > 1 && variations[i - 1].unit != variations[i - 2].unit
    }
}

/** Reading the ladders. The engine asks nothing else of the catalog. */
object Library {

    fun count(pattern: Pattern): Int = ExerciseLibrary.entry(pattern).count

    /** 1-based and clamped. See `ExerciseEntry.variation` for why it clamps. */
    fun index(pattern: Pattern, variation: Int): Int = min(max(variation, 1), count(pattern))

    fun at(pattern: Pattern, v: Int): ExerciseVariation = ExerciseLibrary.entry(pattern).variation(v)

    fun unit(pattern: Pattern, v: Int): LoadUnit = at(pattern, v).unit

    /** 2 for a movement trained one side at a time, 1 otherwise. */
    fun sides(pattern: Pattern, v: Int): Int = if (at(pattern, v).unilateral) 2 else 1

    fun name(pattern: Pattern, v: Int): String = at(pattern, v).name

    fun isTop(pattern: Pattern, v: Int): Boolean = index(pattern = pattern, variation = v) == count(pattern)
}

object ExerciseLibrary {

    /** Swift's `entry(for:)`; every pattern has an entry by construction. */
    fun entry(pattern: Pattern): ExerciseEntry = entries.getValue(pattern)

    val entries: Map<Pattern, ExerciseEntry> = mapOf(
        Pattern.squat to ExerciseEntry(pattern = Pattern.squat, variations = squat),
        Pattern.pushH to ExerciseEntry(pattern = Pattern.pushH, variations = pushH),
        Pattern.hinge to ExerciseEntry(pattern = Pattern.hinge, variations = hinge),
        Pattern.pull to ExerciseEntry(pattern = Pattern.pull, variations = pull),
        Pattern.pushV to ExerciseEntry(pattern = Pattern.pushV, variations = pushV),
        Pattern.lunge to ExerciseEntry(pattern = Pattern.lunge, variations = lunge),
        Pattern.coreAntiExt to ExerciseEntry(pattern = Pattern.coreAntiExt, variations = coreAntiExt),
        Pattern.coreRot to ExerciseEntry(pattern = Pattern.coreRot, variations = coreRot),
        Pattern.calf to ExerciseEntry(pattern = Pattern.calf, variations = calf),
        Pattern.pullBar to ExerciseEntry(pattern = Pattern.pullBar, variations = pullBar),
    )

    /** One rung of a ladder, spelled out so the ladder files read as tables. */
    internal fun rung(name: String, w: Double, unit: LoadUnit, perSide: Boolean,
                      technique: Technique): ExerciseVariation =
        ExerciseVariation(name = name, unilateral = perSide, unit = unit, w = w,
                          steps = technique.steps, mistakes = technique.mistakes)
}
