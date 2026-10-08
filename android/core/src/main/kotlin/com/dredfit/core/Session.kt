//
//  What a workout looks like on the day: the session value types, the
//  rotation, the probe, and the duration estimate.
//

package com.dredfit.core

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

// MARK: - Session

@Suppress("EnumEntryName")
enum class LoadUnit(val rawValue: String) {
    reps("reps"), hold("hold");

    companion object {
        fun fromRaw(raw: String): LoadUnit? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** The last set of an exercise, swapped for one set of the NEXT variation. */
data class SessionProbe(
    val variation: Int,
    val name: String,
    val unit: LoadUnit,
    val load: Int,
    val perSide: Boolean,
) {
    /** "4" / "15 sec" / "4 per side" — one set, so no "N×". English base
     *  strings; the app localizes through the catalog. */
    val display: String
        get() {
            val side = if (perSide) " per side" else ""
            return when (unit) {
                LoadUnit.reps -> "$load$side"
                LoadUnit.hold -> "$load sec$side"
            }
        }
}

/**
 * One exercise of a plan. `setsFloor` is service state: it never leaves the
 * process, so it is out of the primary constructor — and therefore out of
 * `equals` and of any journal — exactly as it is out of Swift's `CodingKeys`
 * and `==`. Inside the engine every call passes it explicitly.
 */
data class SessionExercise(
    val pattern: Pattern,
    val name: String,
    /** 1-based index along the pattern's ladder. */
    val variation: Int,
    val unit: LoadUnit,
    /** The BASE dose: reps or seconds, per side if perSide. */
    val load: Int,
    val perSide: Boolean,
    val sets: Int,
    val restSetSec: Int,
    val restExerciseSec: Int,
    /** Per-set doses, descending — `9-8-8`. Null means a uniform plan. */
    val loads: List<Int>?,
    /** Present only where the probe condition (`probeAllowed`) holds. */
    val probe: SessionProbe?,
) {
    var setsFloor: Int = EngineConfig.setsFloor
        internal set

    constructor(
        pattern: Pattern, name: String, variation: Int, unit: LoadUnit, load: Int,
        perSide: Boolean, sets: Int, restSetSec: Int, restExerciseSec: Int,
        loads: List<Int>?, probe: SessionProbe?, setsFloor: Int,
    ) : this(pattern, name, variation, unit, load, perSide, sets, restSetSec,
             restExerciseSec, loads, probe) {
        this.setsFloor = setsFloor
    }

    val id: Pattern get() = pattern

    /** Every set's planned dose, uniform plan included — bounded by the SCALE,
     *  not by the record: `sets` can come back out of a journal unclamped. */
    internal val perSetLoads: List<Int>
        get() {
            val count = min(max(sets, 0), EngineConfig.setsMax)
            if (loads.isNullOrEmpty()) return List(count) { load }
            return loads.take(count)
        }

    /** What set `index` is planned to run at — the plan's own answer. */
    fun plannedLoad(set: Int): Int {
        if (loads.isNullOrEmpty()) return load
        return loads[min(max(set, 0), loads.size - 1)]
    }

    /** The volume the plan asks for across all WORKING sets; the probe is not in it. */
    val plannedVolume: Int get() = perSetLoads.sum()

    /** "3×12", "3×10 per side", "3×40 sec" — "9-8-8" when the sets differ. */
    val display: String
        get() {
            val side = if (perSide) " per side" else ""
            val head = loads?.joinToString("-") ?: "$sets×$load"
            return when (unit) {
                LoadUnit.reps -> "$head$side"
                LoadUnit.hold -> "$head sec$side"
            }
        }
}

data class Session(
    /** counter + 1 */
    val sessionNumber: Int,
    val warmupMin: Int,
    val cooldownMin: Int,
    val exercises: List<SessionExercise>,
    val estimatedTotalMin: Double,
)

// MARK: - Building the session

fun Engine.estimatedMin(
    exercises: List<SessionExercise>,
    ends: Int = EngineConfig.warmupMin + EngineConfig.cooldownMin,
): Double {
    var workSec = 0.0
    for (ex in exercises) {
        val sides = if (ex.perSide) 2 else 1
        workSec += if (ex.unit == LoadUnit.reps) {
            (ex.plannedVolume * sides).toDouble() * EngineConfig.tempoSecPerRep
        } else {
            (ex.plannedVolume * sides).toDouble()
        }
        // The probe counts as its own set: the session's volume does not
        // grow, and it does not shrink either.
        var sets = ex.sets
        val probe = ex.probe
        if (probe != null) {
            val pSides = if (probe.perSide) 2 else 1
            workSec += if (probe.unit == LoadUnit.reps) {
                (probe.load * pSides).toDouble() * EngineConfig.tempoSecPerRep
            } else {
                (probe.load * pSides).toDouble()
            }
            sets += 1
        }
        workSec += ((sets - 1) * ex.restSetSec).toDouble() + ex.restExerciseSec.toDouble()
    }
    return roundedToTenths((workSec + (ends * 60).toDouble()) / 60)
}

/**
 * Rounded to 0.1 min the way the reference does it — `toFixed(1)`: the nearest
 * tenth to the EXACT value of the double, a tie taken to the larger number.
 * A tie is exactly an odd number of quarters (see Session.swift); everything
 * else is rounded from the exact binary value, which `BigDecimal(Double)` is —
 * Swift's `String(format: "%.1f")` does the same.
 */
internal fun Engine.roundedToTenths(value: Double): Double {
    if (!value.isFinite()) return value
    val quarters = value * 4
    if (quarters == roundedAwayFromZero(quarters) && quarters % 2.0 != 0.0) {
        return ceil(value * 10) / 10
    }
    return BigDecimal(value).setScale(1, RoundingMode.HALF_EVEN).toDouble()
}

/** The probe condition: the dose on its variation's ceiling, the variation not
 *  the top one, the JOURNAL on that ceiling too, and the last answer for the
 *  pattern not "hard". */
internal fun Engine.probeAllowed(p: Pattern, pos: Position, lastHard: Set<Pattern>,
                                 shown: Map<Pattern, Map<Int, Int>>): Boolean {
    val ceiling = Dose.grid(Library.unit(p, pos.variation)).max
    return !Library.isTop(p, pos.variation) &&
        pos.dose >= ceiling &&
        (shown[p]?.get(pos.variation) ?: 0) >= ceiling &&
        p !in lastHard
}

/** The probe a session hands `p` at `pos` — one set of the next variation at
 *  its grid's floor — or null where `probeAllowed` says no. */
fun Engine.probe(p: Pattern, at: Position, lastHard: Set<Pattern>,
                 shown: Map<Pattern, Map<Int, Int>>): SessionProbe? {
    if (!probeAllowed(p, at, lastHard = lastHard, shown = shown)) return null
    val nv = at.variation + 1
    val nUnit = Library.unit(p, nv)
    return SessionProbe(variation = nv, name = Library.name(p, nv), unit = nUnit,
                        load = Dose.grid(nUnit).min, perSide = Library.sides(p, nv) == 2)
}

/** A pure function: the only input is the state. */
fun Engine.generateSession(state: EngineState): Session {
    // Every public entry heals its input first. Identity on the valid domain.
    val clean = state.sanitized()
    val n = rotating.size
    // Nonnegative modulo: `%` is a remainder and goes negative with a
    // negative counter.
    val start = (((clean.counter * EngineConfig.rotationStep) % n) + n) % n
    val five = (0 until EngineConfig.patternsPerSession - 1).map { rotating[(start + it) % n] }
    val chosen = (listOf(Pattern.pull) + five).toSet()
    val useBar = clean.hasBar && clean.counter % 2 == 1
    val patterns = Pattern.ordered.filter { it in chosen }
        .map { if (it == Pattern.pull && useBar) Pattern.pullBar else it }

    val pullSets = if (patterns.any { it in Pattern.pullSide }) pullSlotSets(clean) else EngineConfig.setsMax

    val exercises = patterns.map { p ->
        val pos = clean.position(p)
        val unit = Library.unit(p, pos.variation)
        val sides = Library.sides(p, pos.variation)
        // ONE order of cuts: the sets band, the sets handle, the
        // pull-caps-push gate — each may only lower — and `clampSets` keeps
        // the result at or above the floor.
        val ownSets = setsAfterCut(sets = pos.sets, cut = pos.cut)
        val floor = min(EngineConfig.setsFloor, ownSets)
        val slotSets = clampSets(
            if (p in Pattern.pushSide) min(ownSets, pullSets) else ownSets, floor = floor)
        // The pause is a property of the BAND, not of the number shown.
        val restSet = if (Library.isTop(p, pos.variation) && pos.sets <= EngineConfig.setsBase) {
            EngineConfig.restSetTopVarSec
        } else {
            EngineConfig.restSetByBand[pos.sets] ?: EngineConfig.restSetSec
        }

        // The probe replaces the LAST of the remaining sets.
        val probe = probe(p, at = pos, lastHard = clean.lastHard, shown = clean.shown)
        val probing = probe != null
        val sets = if (probing) slotSets - 1 else slotSets
        SessionExercise(
            pattern = p, name = Library.name(p, pos.variation), variation = pos.variation,
            unit = unit, load = pos.dose, perSide = sides == 2, sets = sets,
            restSetSec = restSet, restExerciseSec = EngineConfig.restExerciseSec,
            loads = planLoads(p, pos, sets = sets), probe = probe,
            // With a probe the floor drops to one working set: the slot's
            // second set is taken by the probe.
            setsFloor = if (probing) max(1, floor - 1) else floor)
    }

    // The postcondition "a descent never adds load" is checked ON THE RESULT.
    val ordNow = mutableMapOf<Pattern, Int>()
    for (ex in exercises) ordNow[ex.pattern] = posOrd(ex.pattern, clean.position(ex.pattern))
    val trimmed = repairDescent(exercises, shownWork = clean.shownWork,
                                shownOrd = clean.shownOrd, ordNow = ordNow,
                                gateLift = gateLift(patterns, state = clean, pullSets = pullSets))

    return Session(
        sessionNumber = clean.counter + 1,
        warmupMin = EngineConfig.warmupMin,
        cooldownMin = EngineConfig.cooldownMin,
        exercises = trimmed,
        estimatedTotalMin = estimatedMin(
            exercises = trimmed, ends = EngineConfig.warmupMin + EngineConfig.cooldownMin))
}

/** How many sets each push's pull cap has given back since the push was last
 *  shown — the rise of the push's OWN cap. None after a set was taken off the
 *  push since, nor when its own sets are fewer than then. */
internal fun Engine.gateLift(patterns: List<Pattern>, state: EngineState, pullSets: Int): Map<Pattern, Int> {
    val lift = mutableMapOf<Pattern, Int>()
    for (p in patterns) {
        if (p !in Pattern.pushSide || p in state.shownSkip) continue
        val capThen = state.shownCap[p]
        if (capThen == null) {
            lift[p] = EngineConfig.setsMax
            continue
        }
        val pos = state.position(p)
        val own = setsAfterCut(sets = pos.sets, cut = pos.cut)
        val ownThen = state.shownOwn[p] ?: continue
        if (own < ownThen) continue
        val rise = min(own, pullSets) - min(ownThen, capThen)
        if (rise > 0) lift[p] = rise
    }
    return lift
}

/** The plan a build without the pull-cap memory drew from this state — for a
 *  workout in progress across an update. See Session.swift. */
fun Engine.sessionWithoutTheOneTimeRelease(state: EngineState): Session {
    val clean = state.sanitized()
    val cap = pullSlotSets(clean)
    // A showing remembered under the cap the plan is drawn under: the cap
    // has risen by nothing since, so the repair lifts nothing.
    for (p in Pattern.pushSide.sortedBy { it.ordinal }) {
        if (clean.shownCap[p] == null) rememberCap(clean, p, clean.position(p), cap = cap)
    }
    return generateSession(clean)
}

/** The pull slot's set count caps the push of the same session, and it reads
 *  the WEAKER of the slot's two branches. `state` is already sanitized. */
internal fun Engine.pullSlotSets(state: EngineState): Int {
    fun own(p: Pattern): Int {
        val q = state.position(p)
        return setsAfterCut(sets = q.sets, cut = q.cut)
    }
    return if (state.hasBar) min(own(Pattern.pull), own(Pattern.pullBar)) else own(Pattern.pull)
}

/** Swift's `(own: Int, cap: Int)` tuple. */
data class PullCap(val own: Int, val cap: Int)

/** The two numbers the pull-caps-push gate weighs for one push. Null for
 *  anything but a push — the cap reaches nothing else. */
fun Engine.pullCap(on: Pattern, state: EngineState): PullCap? {
    if (on !in Pattern.pushSide) return null
    val clean = state.sanitized()
    val pos = clean.position(on)
    return PullCap(own = setsAfterCut(sets = pos.sets, cut = pos.cut), cap = pullSlotSets(clean))
}

/** The work of an exercise in the units of the measure; the probe is NOT in it. */
internal fun Engine.exerciseWork(ex: SessionExercise): Int = ex.plannedVolume * (if (ex.perSide) 2 else 1)

/** The work a SHOWING remembers: with a probe, the set the probe OCCUPIED is
 *  counted in — the repair can only take sets off, so its base is slots. */
internal fun Engine.shownWorkOf(ex: SessionExercise): Int {
    if (ex.probe == null) return exerciseWork(ex)
    return exerciseWork(ex) + ex.load * (if (ex.perSide) 2 else 1)
}

/**
 * THE POSTCONDITION REPAIR: a movement whose position has not risen since it
 * was last shown, and whose shown work has grown, loses sets until it stops.
 * A probing exercise is left alone. A push whose position STANDS gets back
 * what its pull cap has given back since (`gateLift`).
 */
private fun Engine.repairDescent(exercises: List<SessionExercise>,
                                 shownWork: Map<Pattern, Int>, shownOrd: Map<Pattern, Int>,
                                 ordNow: Map<Pattern, Int>,
                                 gateLift: Map<Pattern, Int>): List<SessionExercise> =
    exercises.map { ex ->
        val p = ex.pattern
        if (ex.probe != null) return@map ex
        val work = shownWork[p] ?: return@map ex
        val ord = shownOrd[p] ?: return@map ex
        if ((ordNow[p] ?: 0) > ord) return@map ex
        var cur = ex
        while (cur.sets > cur.setsFloor && exerciseWork(cur) > work) {
            cur = withSets(cur, cur.sets - 1, floor = cur.setsFloor)
        }
        val lift = if ((ordNow[p] ?: 0) == ord) (gateLift[p] ?: 0) else 0
        if (lift > 0 && cur.sets < ex.sets) {
            cur = withSets(ex, min(ex.sets, cur.sets + lift), floor = ex.setsFloor)
        }
        cur
    }

/** Rebuild an exercise on a different set count. The pause is NOT recomputed;
 *  the sub-step is rebuilt for the new count. */
private fun Engine.withSets(ex: SessionExercise, requested: Int, floor: Int): SessionExercise {
    val sets = clampSets(requested, floor = floor)
    val high = ex.loads?.firstOrNull() ?: ex.load
    val carried = ex.loads?.count { it > ex.load } ?: 0
    val sub = min(carried, max(sets - 1, 0))
    val loads: List<Int>? = if (sub > 0) (0 until sets).map { if (it < sub) high else ex.load } else null
    return SessionExercise(
        pattern = ex.pattern, name = ex.name, variation = ex.variation, unit = ex.unit,
        load = ex.load, perSide = ex.perSide, sets = sets,
        restSetSec = ex.restSetSec, restExerciseSec = ex.restExerciseSec,
        loads = loads, probe = ex.probe, setsFloor = ex.setsFloor)
}
