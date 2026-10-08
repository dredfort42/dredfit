//
//  Port of the reference adaptive_engine.js ("the measured ladder").
//  Behavior is verified by the golden tests (Fixtures/golden.json) generated
//  from that reference — any divergence is a port bug.
//
//  Kotlin port of ios/DredfitCore/Sources/DredfitCore/Engine.swift. The judge
//  is golden.json, not the Swift file: where they disagree, the fixture wins.
//
//  THE PRINCIPLE. The engine does not predict — it measures.
//  Everything assigned was either already shown by the trainee (assignment =
//  what was shown + 1 rep in one set) or is being shown right now by a probe.
//  There are no rep-prediction formulas (Epley or any other). The difficulty
//  measure `w` lives in the library and has exactly two jobs: the order of the
//  rungs and the density invariant (a step of at most ×1.50). No dose is
//  computed from it.
//

package com.dredfit.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlin.math.truncate

// MARK: - Movement patterns

/**
 * The entry names mirror the Swift cases one to one (`pushH`, not `PUSH_H`):
 * a diff on the Swift side has to point at the Kotlin line without a search.
 * The wire name is [rawValue]; a `[Pattern: Int]` travels as an UNKEYED array
 * `[rawValue, count, rawValue, count, ...]` — the shape Swift synthesizes, and
 * the one `EngineState.decode` reads. Never key a map by anything else on the
 * wire: it would break the saved state of every iOS install a backup carries.
 */
@Suppress("EnumEntryName")
enum class Pattern(val rawValue: String) {
    squat("squat"), pushH("push_h"), hinge("hinge"), pull("pull"), pushV("push_v"),
    lunge("lunge"), coreAntiExt("core_anti_ext"), coreRot("core_rot"), calf("calf"),
    pullBar("pull_bar");

    /** The English base string; translations live in the String Catalog. */
    val displayName: String
        get() = when (this) {
            squat -> "Squat"
            pushH -> "Horizontal push"
            hinge -> "Hinge"
            pull -> "Pull"
            pushV -> "Vertical push"
            lunge -> "Lunges"
            coreAntiExt -> "Core · plank"
            coreRot -> "Core · rotation"
            calf -> "Calves"
            pullBar -> "Vertical pull"
        }

    companion object {
        /** Swift's `allCases` — the reference's `ALL_PATTERNS`, in the same order. */
        val allCases: List<Pattern> = entries.toList()

        /** The two branches of the pull slot and the two push patterns — the
         *  sides the balance principle weighs against each other. */
        val pullSide: Set<Pattern> = setOf(pull, pullBar)
        internal val pushSide: Set<Pattern> = setOf(pushH, pushV)

        /** Fixed order — defines the rotation. The vertical branch is NOT in it:
         *  it never rotates, it stands in for `pull` in the fixed slot. */
        val ordered: List<Pattern> = listOf(
            squat, pushH, hinge, pull, pushV, lunge, coreAntiExt, coreRot, calf,
        )

        /** Swift's `Pattern(rawValue:)`. */
        fun fromRaw(raw: String): Pattern? = entries.firstOrNull { it.rawValue == raw }
    }
}

// MARK: - Configuration (all model constants)

object EngineConfig {
    /** Sets on any variation but the bands of the top one. */
    const val setsBase = 3
    /** The ceiling on sets (bands 4 and 5 exist only on the top variation). */
    const val setsMax = 5
    const val restSetSec = 60
    const val restExerciseSec = 60
    internal const val tempoSecPerRep = 2.5
    internal const val patternsPerSession = 6
    /** Over eight sessions each rotating pattern comes up exactly five times. */
    internal const val rotationStep = 3
    /** "less" is counted in growth events — one position back along the very
     *  path growth took. */
    internal const val deltaLess = -1
    internal const val deltaPlan = 1
    const val deltaMore = 2
    /** Default cell of the growth ceiling below. */
    internal const val maxUpPerSession = 2
    const val failsToDeload = 3
    /** How many "less" ratings in a row that named nothing before the delta
     *  goes back to the whole session. */
    internal const val lessRunToGlobal = 2
    /** The deload: the sub-step comes off and the base dose drops three whole
     *  rungs. On the dose floor `fallDoses` takes it from the sets or the
     *  variation below instead, while there is one. */
    internal const val deloadDrop = 3
    /** The two blocks are budgeted in whole minutes — see Engine.swift for the
     *  arithmetic behind six and four. */
    const val warmupMin = 6
    const val cooldownMin = 4
    /** Rest between sets by BAND (the sets in the state, not the sets on
     *  screen): a cut takes volume off, not recovery. */
    internal val restSetByBand: Map<Int, Int> = mapOf(1 to 60, 2 to 60, 3 to 60, 4 to 90, 5 to 120)
    /** (#144) On bands 1–3 the TOP VARIATION of a ladder gets 90 s instead of 60. */
    internal const val restSetTopVarSec = 90
    const val comebackMinGapDays = 14
    internal const val comebackBase = 2
    internal const val comebackStepDays = 21
    internal const val comebackMax = 8
    const val silentDecayGapDays = 7
    /** The technical ceiling of every counter and of the gap in days. The clamp
     *  is identity on the valid domain; it is also what keeps every product in
     *  this port inside a 32-bit Int, where Swift has 64 bits. */
    const val countMax = 1_000_000
    /** The window of limited growth a comeback opens. */
    const val rampWindowSessions = 10
    /** The weekly growth budget, in growth events. Slow tissues — the pull
     *  slot and the calves. */
    internal const val weeklyRiseSlow = 3
    internal const val weeklyRiseFast = 6
    internal const val weeklyWindowDays = 7
    /** The floor on how much a session ages the weekly window. A zero gap is
     *  always a source error; without the floor the engine freezes for good. */
    internal const val minSessionAgeDays = 1.0 / 24.0
    /** The SHARED floor on sets. It goes through `clampSets`. */
    const val setsFloor = 2
    internal const val setsBackPerSession = 1
    /** How many steps a person may add to ONE movement for next time, per session. */
    const val raiseStepsMax = 2
    /** How many APPEARANCES a returned set is held before the next one may come back. */
    const val setsBackHold = 2
    /** The chronic signal (#137): a window of recent appearances. */
    const val chronicWindow = 4
    const val chronicHits = 3
    internal const val chronicStep = -2
    /** Ceilings on where a comeback may land. Rows are [minimum gap, ceiling
     *  "floor" 1…4 (see `ceilVar`)], by descending gap; the first match wins. */
    internal val comebackLandingCeil: List<Pair<Int, Int>> =
        listOf(365 to 1, 119 to 2, 77 to 3, 56 to 4)
    internal const val comebackCeilFloors = 4

    /** (#64) The growth ceiling is a table, not a scalar: how many of a
     *  ladder's TOP variations carry a ceiling of 1. */
    internal val maxUpTopVars: Map<Pattern, Int> = mapOf(
        Pattern.squat to 1, Pattern.pushH to 1, Pattern.hinge to 1, Pattern.pull to 3,
        Pattern.pushV to 2, Pattern.lunge to 1, Pattern.coreAntiExt to 1,
        Pattern.coreRot to 1, Pattern.calf to 5, Pattern.pullBar to 3,
    )

    /** The growth ceiling for a (pattern, variation) cell. */
    internal fun maxUp(pattern: Pattern, variation: Int): Int {
        val v = Library.index(pattern = pattern, variation = variation)
        return if (Library.count(pattern) - v < (maxUpTopVars[pattern] ?: 0)) 1 else maxUpPerSession
    }

    /** A "slow tissue" pattern — a ceiling of 1 on EVERY variation. */
    internal fun isSlowTissue(pattern: Pattern): Boolean =
        (maxUpTopVars[pattern] ?: 0) >= Library.count(pattern)
}

@Suppress("EnumEntryName")
enum class FeedbackResult(val rawValue: String) {
    less("less"), plan("plan"), more("more");

    internal val delta: Int
        get() = when (this) {
            less -> EngineConfig.deltaLess
            plan -> EngineConfig.deltaPlan
            more -> EngineConfig.deltaMore
        }

    companion object {
        fun fromRaw(raw: String): FeedbackResult? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * Swift's `x.rounded()`: to the nearest integer, a tie taken AWAY from zero.
 * `kotlin.math.round` takes ties to even and `Math.round` takes them up, so
 * neither is the same function — and a port that used one would differ from
 * the reference on every half.
 */
internal fun roundedAwayFromZero(x: Double): Double {
    if (!x.isFinite()) return x
    val t = truncate(x)
    return if (abs(x - t) >= 0.5) t + sign(x) else t
}

/**
 * The engine: pure functions. The Swift `extension Engine` files become
 * extension functions on this object in the file of the same name.
 */
object Engine {

    /** Rotating patterns (all except pull — it appears in every session). */
    internal val rotating: List<Pattern> = Pattern.ordered.filter { it != Pattern.pull }

    /** A probe's number is one set of one movement — an integer by nature —
     *  clamped to the technical range. */
    internal fun sanitizeProbe(raw: Int): Int =
        EngineState.clamped(raw, -EngineConfig.countMax, EngineConfig.countMax)

    /** A reported number, clamped to the technical range. A fact is NOT
     *  rounded on the way in: the fraction answers "did they take the top set". */
    internal fun sanitizeActual(raw: Double): Double {
        if (!raw.isFinite()) return 0.0
        return min(max(raw, -EngineConfig.countMax.toDouble()), EngineConfig.countMax.toDouble())
    }

    // MARK: - Writing a position back

    /** Sparseness is part of the contract: the base set count, a zero sub-step
     *  and an empty cut are not stored. */
    internal fun setPosition(next: EngineState, p: Pattern, raw: Position) {
        val pos = fit(p, raw)
        next.vars[p] = pos.variation
        next.doses[p] = pos.dose
        if (pos.sets != EngineConfig.setsBase) next.sets[p] = pos.sets else next.sets.remove(p)
        if (pos.sub > 0) next.sub[p] = pos.sub else next.sub.remove(p)
        if (pos.cut > 0) next.cut[p] = pos.cut else next.cut.remove(p)
    }

    /** The pull cap a push was shown under, with the trace of a cut closed. */
    internal fun rememberCap(next: EngineState, p: Pattern, pos: Position, cap: Int) {
        if (p !in Pattern.pushSide) return
        next.shownCap[p] = cap
        next.shownOwn[p] = setsAfterCut(sets = pos.sets, cut = pos.cut)
        next.shownSkip.remove(p)
    }

    /** The journal of what was shown: ONE point of writing in the whole engine. */
    internal fun setShown(next: EngineState, p: Pattern, v: Int, dose: Int) {
        val unit = Library.unit(p, v)
        val d = min(Dose.snap(unit, dose), Dose.grid(unit).max)
        if (d <= 0) return
        next.shown.getOrPut(p) { mutableMapOf() }[Library.index(pattern = p, variation = v)] = d
    }

    /** The whole ladder of a pattern as a measure — what the progress scale reads. */
    fun ladderSpan(p: Pattern): Int {
        val unit = Library.unit(p, Library.count(p))
        return posOrd(p, Position(variation = Library.count(p), sets = EngineConfig.setsMax,
                                  dose = Dose.grid(unit).max, sub = 0, cut = 0))
    }

    /** How far along its ladder a pattern stands. */
    fun progress(state: EngineState, p: Pattern): Int = posOrd(p, state.sanitized().position(p))

    /** The same measure for a position the app recorded earlier — all five coordinates. */
    fun progress(p: Pattern, position: Position): Int = posOrd(p, fit(p, position))

    fun progress(p: Pattern, variation: Int, sets: Int, dose: Int): Int =
        progress(p, Position(variation = variation, sets = sets, dose = dose, sub = 0, cut = 0))

    /** The sum of those ordinals — the total progress across all patterns. */
    fun totalProgress(state: EngineState): Int {
        val clean = state.sanitized()
        return Pattern.allCases.fold(0) { acc, p -> acc + posOrd(p, clean.position(p)) }
    }

    /** Where each variation begins on that ordinal — the ticks of the progress
     *  bar. The first is always 0 and is left out. */
    fun variationBoundaries(p: Pattern): List<Int> = (2..Library.count(p)).map { varBase(p, it) }

    /** How many growth events still separate a pattern from the dose ceiling
     *  of its CURRENT variation; sets taken off are not counted. */
    fun stepsToVariationCeiling(state: EngineState, p: Pattern): Int {
        val pos = state.sanitized().position(p)
        val ceiling = pos.copy(dose = Dose.grid(Library.unit(p, pos.variation)).max, sub = 0)
        return max(0, posOrd(p, fit(p, ceiling)) - posOrd(p, pos))
    }

    /** Record the plan the person SAW, with no feedback. See Engine.swift. */
    fun recordShown(state: EngineState, session: Session): EngineState {
        val clean = state.sanitized()
        val next = clean.copy()
        val cap = pullSlotSets(clean)
        for (ex in session.exercises) {
            next.shownWork[ex.pattern] = shownWorkOf(ex)
            next.shownOrd[ex.pattern] = posOrd(ex.pattern, clean.position(ex.pattern))
            rememberCap(next, ex.pattern, clean.position(ex.pattern), cap = cap)
        }
        return next
    }
}
