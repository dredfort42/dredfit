//
//  Reading a state written by an engine before v3.
//
//  It must never start anyone over: a reset would throw away the rung and the
//  dose every upgrading trainee had earned on every movement. A v2 state is
//  read and carried over instead.
//
//  Mirrors `migrateFromV2` in the reference engine. The golden fixture does NOT
//  pin it (see MigrationV2.swift); on iOS the two tables are pinned by the
//  app's MigrationV2Tests, which arrive on Android with the app phase.
//

package com.dredfit.core

/** v2 tier → v3 variation. Baked as data, not derived: the v2 library does not
 *  exist at runtime. Order is preserved by cascade. */
val Engine.v2TierToVariation: Map<Pattern, List<Int>>
    get() = V2_TIER_TO_VARIATION

private val V2_TIER_TO_VARIATION: Map<Pattern, List<Int>> = mapOf(
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

/** A SNAPSHOT of a removed format: v2's `decodeLevel` was a pure function of
 *  L ∈ [0, 47]. A row is [tier, sets, reps, seconds], kept in the baseline's
 *  own spelling so the 48 values compare with the JS by eye. */
val Engine.v2LevelTable: List<List<Int>>
    get() = V2_LEVEL_TABLE

private val V2_LEVEL_TABLE: List<List<Int>> = listOf(
    listOf(1,3,8,20), listOf(1,3,9,22), listOf(1,3,10,24), listOf(1,3,11,26), listOf(1,3,12,29), listOf(1,3,13,32),
    listOf(1,3,14,35), listOf(1,3,15,39), listOf(2,3,6,15), listOf(2,3,7,17), listOf(2,3,8,19), listOf(2,3,9,21),
    listOf(2,3,10,23), listOf(2,3,11,25), listOf(2,3,12,28), listOf(2,3,13,31), listOf(3,3,5,15), listOf(3,3,6,17),
    listOf(3,3,7,19), listOf(3,3,8,21), listOf(3,3,9,23), listOf(3,3,10,25), listOf(3,3,11,28), listOf(3,3,12,31),
    listOf(4,3,4,10), listOf(4,3,5,11), listOf(4,3,6,12), listOf(4,3,7,13), listOf(4,3,8,14), listOf(4,3,9,15),
    listOf(4,3,10,17), listOf(4,3,11,19), listOf(4,4,6,20), listOf(4,4,7,23), listOf(4,4,8,26), listOf(4,4,9,29),
    listOf(4,4,10,32), listOf(4,4,11,35), listOf(4,4,12,38), listOf(4,4,13,41), listOf(4,5,8,24), listOf(4,5,9,27),
    listOf(4,5,10,30), listOf(4,5,11,33), listOf(4,5,12,36), listOf(4,5,13,39), listOf(4,5,14,42), listOf(4,5,15,45),
)

/** What a v2 state carries, as far as v3 needs to read it — Swift's
 *  `Engine.V2State`; a Kotlin object cannot be extended with a nested type. */
data class V2State(
    val counter: Int,
    val hasBar: Boolean,
    val levels: Map<Pattern, Int>,
    val failStreak: Map<Pattern, Int> = emptyMap(),
)

/** Returns a v3 state, or null when the input does not look like v2 — null
 *  means "this is not v2", never "migrate into nothing". */
fun Engine.migrateFromV2(old: V2State): EngineState? {
    if (old.levels.isEmpty()) return null
    val next = EngineState.initial
    // Neither is progress, but both are the person's.
    next.counter = EngineState.clamped(old.counter, 0, EngineConfig.countMax)
    next.hasBar = old.hasBar
    for (p in Pattern.allCases) {
        val row = v2TierToVariation[p] ?: continue
        val level = old.levels[p] ?: continue
        val entry = v2LevelTable[EngineState.clamped(level, 0, v2LevelTable.size - 1)]
        val tier = entry[0]
        val v2sets = entry[1]
        val v2reps = entry[2]
        val v2hold = entry[3]
        val v = Library.index(pattern = p, variation = row[EngineState.clamped(tier, 1, row.size) - 1])
        val unit = Library.unit(p, v)
        // The grid is the same, so the dose carries over with a snap down and
        // a clamp; a v2 dose below v3's floor comes UP to it (an accepted gap).
        val dose = Dose.clamped(unit, Dose.snap(unit, if (unit == LoadUnit.hold) v2hold else v2reps))
        next.vars[p] = v
        next.doses[p] = dose
        // Sets bands live only on the top variation.
        if (v2sets > EngineConfig.setsBase && Library.isTop(p, v)) {
            next.sets[p] = EngineState.clamped(v2sets, EngineConfig.setsBase, setsCeil(p, v))
        }
        // The journal: they really did do this dose in this variation.
        next.shown.getOrPut(p) { mutableMapOf() }[v] = dose
        next.failStreak[p] = EngineState.clamped(old.failStreak[p] ?: 0, 0, EngineConfig.failsToDeload - 1)
    }
    return next
}
