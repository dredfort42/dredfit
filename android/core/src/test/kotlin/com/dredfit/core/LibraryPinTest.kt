//
//  The 59 (pattern, variation) → movement identities, pinned by value — the
//  port of LibraryPinTests.swift.
//
//  golden.json deliberately carries no English names — localized strings are
//  locale-fragile and the trace stays numeric — so without this table a
//  reordering of two rungs inside a ladder would pass every other test while
//  silently rewriting journal history, which re-resolves names from the
//  current library. The variation is POSITIONAL: the order IS the contract.
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LibraryPinTest {

    /** The catalog, movement by movement, in ladder order — the
     *  source-language names the whole catalog is keyed by. */
    private val catalog: Map<Pattern, List<String>> = mapOf(
        Pattern.squat to listOf("Squat", "Split squat", "Bulgarian split squat",
            "Single-leg squat to a chair", "Pistol squat", "Shrimp squat"),
        Pattern.pushH to listOf("Knee push-up", "Incline push-up", "Push-up", "Feet-elevated push-up",
            "Side-shift push-up", "Archer push-up"),
        Pattern.hinge to listOf("Glute bridge", "Assisted single-leg glute bridge", "Single-leg glute bridge",
            "Sliding leg curl", "Negative single-leg sliding curl",
            "Single-leg sliding leg curl", "Assisted Nordic curl"),
        Pattern.pull to listOf("Standing incline row", "High-bar inverted row", "Mid-height inverted row",
            "Inverted row (table)", "Feet-elevated inverted row",
            "Side-shift inverted row", "Archer inverted row"),
        Pattern.pushV to listOf("Wall push-up", "Pike push-up, hands on a table",
            "Pike push-up, hands on a chair", "Pike push-up",
            "Feet-elevated pike push-up", "Wall handstand negative",
            "Wall handstand push-up"),
        Pattern.lunge to listOf("Static lunge", "Reverse lunge", "Paused lunge", "Jump lunge"),
        Pattern.coreAntiExt to listOf("Knee plank", "High plank", "Plank", "Hollow hold", "Long-lever plank"),
        Pattern.coreRot to listOf("Kneeling side plank", "Kneeling side plank, top leg extended",
            "Side plank", "Side plank with leg raise", "Star side plank"),
        Pattern.calf to listOf("Calf raises", "Assisted single-leg calf raise", "Single-leg calf raise",
            "Single-leg calf raise with pause", "Single-leg calf raise on a step"),
        Pattern.pullBar to listOf("Bar hang", "Scapular hang", "Negative pull-up, both feet assisting",
            "Negative pull-up, one foot assisting", "Negative pull-up",
            "Partial pull-up", "Pull-up"),
    )

    /** An assistance rung (kind `°` in the fixture's library) and the
     *  variation it assists. */
    private data class Assist(val pattern: Pattern, val rung: Int, val base: Int)

    /** Nine of them. */
    private val assists: List<Assist> = listOf(
        Assist(Pattern.hinge, 2, 3),
        Assist(Pattern.hinge, 5, 6),
        Assist(Pattern.pull, 3, 4),
        Assist(Pattern.pushV, 2, 4),
        Assist(Pattern.pushV, 3, 4),
        Assist(Pattern.coreRot, 2, 1),
        Assist(Pattern.calf, 2, 3),
        Assist(Pattern.pullBar, 3, 5),
        Assist(Pattern.pullBar, 4, 5),
    )

    /** Every position, by value and in order. A swap of two rungs inside a
     *  ladder — invisible to golden — fails here by name. The Swift test resolves
     *  the pinned keys through the library's bundle; the Kotlin core carries the
     *  English base strings, which ARE the catalog keys, so the key is compared
     *  as is (localization is wired in the app phase). */
    @Test
    fun everyVariationIdentityIsPinned() {
        for (pattern in Pattern.allCases) {
            val expected = catalog.getValue(pattern)
            val entry = ExerciseLibrary.entry(pattern)
            assertEquals(expected.size, entry.count, "${pattern.rawValue}: ladder length")
            for ((index, key) in expected.withIndex()) {
                assertEquals(key, entry.variations[index].name,
                             "${pattern.rawValue} v${index + 1} must be “$key”")
            }
        }
    }

    /** The pin covers the whole library — a new pattern cannot slip past it,
     *  and the count is the catalog's own: 59 positions. */
    @Test
    fun theCatalogCoversEveryPattern() {
        assertEquals(Pattern.allCases.toSet(), catalog.keys)
        assertEquals(59, catalog.values.sumOf { it.size })
    }

    /** Every position carries a full card: three steps and two mistakes. */
    @Test
    fun everyPositionCarriesItsTechnique() {
        for (pattern in Pattern.allCases) {
            for ((index, variation) in ExerciseLibrary.entry(pattern).variations.withIndex()) {
                val ctx = "${pattern.rawValue} v${index + 1}"
                assertFalse(variation.name.isEmpty(), "$ctx: name")
                assertEquals(3, variation.steps.size, "$ctx: steps")
                assertEquals(2, variation.mistakes.size, "$ctx: mistakes")
                for (line in variation.steps + variation.mistakes) {
                    assertFalse(line.isEmpty(), "$ctx: empty technique line")
                }
            }
        }
    }

    /** An assistance rung inherits its base's technique with EXACTLY ONE line
     *  changed — the one where the assistance lives. Asserted by count so a
     *  copy-pasted card that drifted from its base cannot pass as inheritance,
     *  and a rung that changed nothing cannot pass as a rung. */
    @Test
    fun assistanceRungsChangeExactlyOneLine() {
        for (assist in assists) {
            val entry = ExerciseLibrary.entry(assist.pattern)
            val a = entry.variation(assist.rung)
            val b = entry.variation(assist.base)
            val ctx = "${assist.pattern.rawValue} v${assist.rung} assists v${assist.base}"
            assertEquals(b.mistakes, a.mistakes, "$ctx: mistakes are inherited whole")
            val same = a.steps.zip(b.steps).count { (x, y) -> x == y }
            assertEquals(2, same, "$ctx: exactly one step differs")
        }
    }

    /** The density invariant: `w` rises along every ladder, and no step up is
     *  heavier than ×1.50. The single exception is the unit boundary, where
     *  the ratio is undefined — and the ladder is allowed at most one of those. */
    @Test
    fun densityInvariantHolds() {
        for (pattern in Pattern.allCases) {
            val entry = ExerciseLibrary.entry(pattern)
            var boundaries = 0
            for (v in 2..entry.count) {
                val lower = entry.variation(v - 1)
                val upper = entry.variation(v)
                val ctx = "${pattern.rawValue} v${v - 1}→v$v"
                assertTrue(upper.w > lower.w, "$ctx: w must rise")
                if (entry.probeOnly(variation = v)) {
                    boundaries += 1
                    continue
                }
                assertTrue(upper.w / lower.w <= 1.50, "$ctx: density ×1.50")
            }
            assertTrue(boundaries <= 1, "${pattern.rawValue}: at most one unit change per ladder")
        }
    }

    /** The three warm-up movements the core carries stand on no strength
     *  ladder and keep their full text — the warm-up reads them. */
    @Test
    fun warmupMovementsSurvivedTheLadders() {
        assertEquals(3, WarmupTechnique.all.size)
        for (move in WarmupTechnique.all) {
            assertFalse(move.name.isEmpty(), "${move.id}: name")
            assertEquals(3, move.steps.size, "${move.id}: steps")
            assertEquals(2, move.mistakes.size, "${move.id}: mistakes")
        }
        // None of them may be back in a strength ladder.
        val ladderNames = Pattern.allCases.flatMap {
            ExerciseLibrary.entry(it).variations.map { v -> v.name }
        }.toSet()
        for (move in WarmupTechnique.all) {
            assertFalse(ladderNames.contains(move.name),
                        "${move.id} belongs to the warm-up, not to a ladder")
        }
    }
}
