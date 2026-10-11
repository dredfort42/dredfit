//
//  Port of ios/DredfitTests/MigrationV2Tests+Table.swift: the two baked
//  tables the v2 → v3 migration is made of, checked against values that do
//  NOT come out of those tables. Engine-only, and nothing in android/core
//  covers them, so they live here beside their Swift twin.
//
//  DO NOT "SIMPLIFY" THIS FILE by reading the expectations back from
//  `Engine.v2TierToVariation` / `Engine.v2LevelTable`: a test that takes its
//  expectation from the thing under test cannot fail — rewriting every row to
//  `[1, 1, 1, 1]` is exactly what it could not see. GoldenTest does not close
//  the gap either: the `migration_v2` scenario is seeded with the reference's
//  OUTPUT. The values were transcribed by hand from the local reference
//  sources (see the Swift file).
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.V2State
import com.dredfit.core.migrateFromV2
import com.dredfit.core.v2LevelTable
import com.dredfit.core.v2TierToVariation
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** The removed v2 format, as data — a second, independent copy, duplicated
 *  on purpose: v2's library and level arithmetic are gone from the runtime. */
object V2FormatSnapshot {

    /** v2's `decodeLevel` flattened: one row per level L ∈ [0, 47], each
     *  `[tier, sets, reps, seconds]`. */
    val levelTable: List<List<Int>> = listOf(
        listOf(1, 3, 8, 20), listOf(1, 3, 9, 22), listOf(1, 3, 10, 24), listOf(1, 3, 11, 26), listOf(1, 3, 12, 29), listOf(1, 3, 13, 32),
        listOf(1, 3, 14, 35), listOf(1, 3, 15, 39), listOf(2, 3, 6, 15), listOf(2, 3, 7, 17), listOf(2, 3, 8, 19), listOf(2, 3, 9, 21),
        listOf(2, 3, 10, 23), listOf(2, 3, 11, 25), listOf(2, 3, 12, 28), listOf(2, 3, 13, 31), listOf(3, 3, 5, 15), listOf(3, 3, 6, 17),
        listOf(3, 3, 7, 19), listOf(3, 3, 8, 21), listOf(3, 3, 9, 23), listOf(3, 3, 10, 25), listOf(3, 3, 11, 28), listOf(3, 3, 12, 31),
        listOf(4, 3, 4, 10), listOf(4, 3, 5, 11), listOf(4, 3, 6, 12), listOf(4, 3, 7, 13), listOf(4, 3, 8, 14), listOf(4, 3, 9, 15),
        listOf(4, 3, 10, 17), listOf(4, 3, 11, 19), listOf(4, 4, 6, 20), listOf(4, 4, 7, 23), listOf(4, 4, 8, 26), listOf(4, 4, 9, 29),
        listOf(4, 4, 10, 32), listOf(4, 4, 11, 35), listOf(4, 4, 12, 38), listOf(4, 4, 13, 41), listOf(4, 5, 8, 24), listOf(4, 5, 9, 27),
        listOf(4, 5, 10, 30), listOf(4, 5, 11, 33), listOf(4, 5, 12, 36), listOf(4, 5, 13, 39), listOf(4, 5, 14, 42), listOf(4, 5, 15, 45),
    )

    /** v2 tier (1…4) → v3 variation, indexed `[tier - 1]`: the whole of what
     *  an upgrade decides about where a person stands. */
    val tierToVariation: Map<Pattern, List<Int>> = mapOf(
        Pattern.squat to listOf(1, 3, 5, 6),
        Pattern.pushH to listOf(1, 3, 4, 6),
        Pattern.hinge to listOf(1, 2, 3, 4),
        Pattern.pull to listOf(1, 4, 5, 7),
        Pattern.pushV to listOf(1, 4, 5, 7),
        Pattern.lunge to listOf(1, 2, 3, 4),
        Pattern.coreAntiExt to listOf(1, 3, 4, 5),
        Pattern.coreRot to listOf(1, 3, 4, 5),
        Pattern.calf to listOf(1, 3, 4, 5),
        Pattern.pullBar to listOf(1, 5, 6, 7),
    )

    /** `LIBRARY[p].unilateral` in v2 — without it no v3-only measure sees a
     *  two-sided tier landing on a one-sided rung (real work ×2). */
    val unilateral: Map<Pattern, List<Boolean>> = mapOf(
        Pattern.squat to listOf(false, true, true, true),
        Pattern.pushH to listOf(false, false, false, true),
        Pattern.hinge to listOf(false, true, true, false),
        Pattern.pull to listOf(false, false, false, true),
        Pattern.pushV to listOf(false, false, false, false),
        Pattern.lunge to listOf(true, true, true, true),
        Pattern.coreAntiExt to listOf(false, false, false, false),
        Pattern.coreRot to listOf(true, true, true, true),
        Pattern.calf to listOf(false, true, true, true),
        Pattern.pullBar to listOf(false, false, false, false),
    )

    /** `LIBRARY[p].unit` / `.units` in v2: only `pull_bar` changed unit along
     *  its own ladder (a hang, then reps). */
    val unit: Map<Pattern, List<LoadUnit>> = Pattern.allCases.associateWith { p ->
        when (p) {
            Pattern.coreAntiExt, Pattern.coreRot -> List(4) { LoadUnit.hold }
            Pattern.pullBar -> listOf(LoadUnit.hold, LoadUnit.reps, LoadUnit.reps, LoadUnit.reps)
            else -> List(4) { LoadUnit.reps }
        }
    }

    /** What one v2 session at level `L` really cost: `sets × dose × sides`, in
     *  v2's own unit and sidedness — the quantity `Engine.planLoad` computes
     *  for v3, which stays internal: the test brings its own measure. */
    fun work(pattern: Pattern, level: Int): Int {
        val row = assertNotNull(levelTable.getOrNull(level), "L=$level is outside v2's forty-eight levels")
        assertEquals(4, row.size, "L=$level: a v2 row is [tier, sets, reps, seconds]")
        val tier = row[0]
        val tierUnit = assertNotNull(unit[pattern]?.getOrNull(tier - 1), "${pattern.rawValue} has no tier $tier unit")
        val tierPerSide = assertNotNull(unilateral[pattern]?.getOrNull(tier - 1),
                                        "${pattern.rawValue} has no tier $tier sidedness")
        return row[1] * (if (tierUnit == LoadUnit.hold) row[3] else row[2]) * (if (tierPerSide) 2 else 1)
    }
}

// Bounds-checked reads (`getOrNull`) throughout: a mis-transcribed snapshot
// must fail as a NAMED assertion, not as an index crash.
class MigrationV2TableTest {

    private val v2Tiers = 1..4

    private fun shippedRow(p: Pattern): List<Int> =
        assertNotNull(Engine.v2TierToVariation[p], "${p.rawValue} has no row in the shipped table")

    // MARK: - The forty cells that decide where an upgrade lands

    @Test
    fun v2TierToVariation_everyCell_matchesTheIndependentSnapshot() {
        assertEquals(Pattern.allCases.toSet(), Engine.v2TierToVariation.keys,
                     "every pattern must be migrated: one missing row means that movement is left behind")
        for (p in Pattern.allCases) {
            val expected = assertNotNull(V2FormatSnapshot.tierToVariation[p], "${p.rawValue} has no row in the snapshot")
            assertEquals(expected, shippedRow(p), "${p.rawValue}: the four rungs an upgrade lands on, tier 1…4")
        }
    }

    /** v2's sidedness must survive the jump: a bilateral tier landing on a
     *  unilateral rung keeps the rep count and doubles the session. */
    @Test
    fun v2TierToVariation_everyMappedRung_keepsTheSidednessOfTheTierItReplaces() {
        for (p in Pattern.allCases) {
            val row = shippedRow(p)
            for (tier in v2Tiers) {
                val variation = assertNotNull(row.getOrNull(tier - 1), "${p.rawValue} has no tier $tier")
                val wasUnilateral = assertNotNull(V2FormatSnapshot.unilateral[p]?.getOrNull(tier - 1),
                                                  "${p.rawValue} has no tier $tier in the snapshot")
                val expected = if (wasUnilateral) 2 else 1
                assertEquals(expected, Library.sides(p, variation),
                             "${p.rawValue} tier $tier lands on variation $variation: v2 trained it on $expected side(s)")
            }
        }
    }

    /** The dose crosses as a bare NUMBER, so its unit must be the same on
     *  both sides: nine reps read as nine seconds is a different workout. */
    @Test
    fun v2TierToVariation_everyMappedRung_keepsTheUnitOfTheTierItReplaces() {
        for (p in Pattern.allCases) {
            val row = shippedRow(p)
            for (tier in v2Tiers) {
                val variation = assertNotNull(row.getOrNull(tier - 1), "${p.rawValue} has no tier $tier")
                val expected = assertNotNull(V2FormatSnapshot.unit[p]?.getOrNull(tier - 1),
                                             "${p.rawValue} has no tier $tier in the snapshot")
                assertEquals(expected, Library.unit(p, variation),
                             "${p.rawValue} tier $tier lands on variation $variation: the unit must not change under the dose")
            }
        }
    }

    /** A higher v2 tier never lands below a lower one, and no cell points past
     *  its ladder: `Library.index` CLAMPS, so an out-of-range cell would be
     *  swallowed in silence onto the top rung. */
    @Test
    fun v2TierToVariation_everyRow_risesStrictlyAndStaysInsideItsLadder() {
        for (p in Pattern.allCases) {
            val row = shippedRow(p)
            assertEquals(v2Tiers.count(), row.size, "${p.rawValue}: v2 had exactly four tiers, and each needs a landing")
            for (tier in v2Tiers) {
                val variation = assertNotNull(row.getOrNull(tier - 1), "${p.rawValue} has no tier $tier")
                assertTrue(variation >= 1, "${p.rawValue} tier $tier: variations are 1-based")
                assertTrue(variation <= Library.count(p),
                           "${p.rawValue} tier $tier: variation $variation is past the end of a ${Library.count(p)}-rung ladder")
                if (tier > 1) {
                    val below = assertNotNull(row.getOrNull(tier - 2), "${p.rawValue} has no tier ${tier - 1}")
                    assertTrue(variation > below,
                               "${p.rawValue}: tier $tier must land above tier ${tier - 1}, or two v2 tiers collapse onto one rung")
                }
            }
        }
    }

    // MARK: - The forty-eight rows of the removed level format

    @Test
    fun v2LevelTable_allFortyEightRows_matchTheIndependentSnapshot() {
        assertEquals(V2FormatSnapshot.levelTable.size, Engine.v2LevelTable.size,
                     "v2 encoded L ∈ [0, 47]: a shorter table clamps real levels onto the wrong row")
        for (level in V2FormatSnapshot.levelTable.indices) {
            val shipped = assertNotNull(Engine.v2LevelTable.getOrNull(level), "L=$level is missing from the shipped table")
            assertEquals(V2FormatSnapshot.levelTable[level], shipped,
                         "L=$level: [tier, sets, reps, seconds] as v2's decodeLevel produced them")
        }
    }

    /** Bands of 4 and 5 sets exist ONLY on the top rung. v2 had them above
     *  tier 4 regardless, so a band rides along only where the landing rung
     *  is the top — carrying one lower builds an unreachable state. */
    @Test
    fun migration_whenAV2BandLandsBelowTheTopRung_dropsTheBandInsteadOfBuildingAnUnreachableState() {
        for (p in Pattern.allCases) {
            val row = assertNotNull(V2FormatSnapshot.tierToVariation[p], "${p.rawValue} has no row in the snapshot")
            for (level in V2FormatSnapshot.levelTable.indices) {
                val snapshotRow = V2FormatSnapshot.levelTable[level]
                val tier = assertNotNull(snapshotRow.getOrNull(0), "L=$level has no tier column")
                val v2sets = assertNotNull(snapshotRow.getOrNull(1), "L=$level has no sets column")
                val variation = assertNotNull(row.getOrNull(tier - 1), "${p.rawValue} has no tier $tier")
                val migrated = assertNotNull(Engine.migrateFromV2(V2State(counter = 1, hasBar = true, levels = mapOf(p to level))),
                                             "a state carrying one level is still a v2 state")
                val isTop = Library.isTop(p, variation)
                val expected: Int? = if (v2sets > EngineConfig.setsBase && isTop) v2sets else null
                assertEquals(expected, migrated.sets[p],
                             "${p.rawValue} L=$level: v2 planned $v2sets sets and the landing rung $variation is " +
                                 (if (isTop) "the top" else "not the top") + " of its ladder")
            }
        }
    }
}
