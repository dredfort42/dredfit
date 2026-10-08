//
//  The engine's state: a position of five coordinates per pattern, the
//  journal of what was shown, and the global counters.
//
//  A state written before v3 carries `levels` and no `vars`/`doses`, so the
//  decode below FAILS on it — and that failure is the DISPATCH, not the end:
//  the app then reads the v2 shape and carries it over with
//  `Engine.migrateFromV2` (MigrationV2.kt). Only a state that is neither shape
//  starts from `initial`.
//
//  THE WIRE FORMAT IS THE iOS ONE, byte-compatible in both directions: backup
//  export/import is the bridge from iOS to Android. Swift synthesizes a
//  `[Pattern: Int]` as an UNKEYED array alternating [rawValue, count, ...],
//  a `Set<Pattern>` as an array of raw values, and the journal's inner
//  `[Int: Int]` as an object keyed by the integer's decimal string.
//

package com.dredfit.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import kotlin.math.max
import kotlin.math.min

/** A state file that is not a v3 state — Swift's `DecodingError`. */
class EngineStateDecodingException(message: String) : Exception(message)

/**
 * A mutable class with VALUE semantics by convention: Swift's `EngineState` is
 * a struct, so `var next = state` copies. Every such copy here is an explicit
 * [copy] — a deep one — and no engine entry point returns its input instance.
 */
@Suppress("LongParameterList")
class EngineState(
    var counter: Int,
    /** Index along the pattern's ladder, 1…N. Dense: every pattern has one. */
    var vars: MutableMap<Pattern, Int>,
    /** Reps — or seconds — per set. Dense, in the unit of the CURRENT variation. */
    var doses: MutableMap<Pattern, Int>,
    var failStreak: MutableMap<Pattern, Int>,
    var hasBar: Boolean,
    /** Sets. Sparse, and the base of 3 is never stored. */
    var sets: MutableMap<Pattern, Int>,
    /** The sub-step: the first `sub` sets carry one rung more. Sparse. */
    var sub: MutableMap<Pattern, Int>,
    /** Sets taken off. Sparse. */
    var cut: MutableMap<Pattern, Int>,
    /** THE JOURNAL OF WHAT WAS SHOWN: per variation touched, the last dose
     *  actually performed, in that variation's own unit. Doubly sparse. */
    var shown: MutableMap<Pattern, MutableMap<Int, Int>>,
    /** Appearances left before the next set may come back. */
    var setsHold: MutableMap<Pattern, Int>,
    /** The work of the last plan SHOWN, and the position it was shown AT: the
     *  two inputs to the postcondition repair. */
    var shownWork: MutableMap<Pattern, Int>,
    var shownOrd: MutableMap<Pattern, Int>,
    /** The pull-cap memory of a push (pushes only). */
    var shownCap: MutableMap<Pattern, Int>,
    var shownOwn: MutableMap<Pattern, Int>,
    /** Pushes a set was taken off since their last showing. */
    var shownSkip: MutableSet<Pattern>,
    /** Patterns whose last appearance the person called hard. */
    var lastHard: MutableSet<Pattern>,
    /** How many "less" ratings in a row named no movement. */
    var lessRun: Int,
    /** Branches of the pull slot the cross-credit is paused for. */
    var creditPaused: MutableSet<Pattern>,
    /** Comebacks applied in a row with no completed session between them. */
    var returnRun: Int,
    /** The last appearances of each pattern as a bit mask. */
    var lessHist: MutableMap<Pattern, Int>,
    /** Sessions left in the limited-growth window a comeback opens. */
    var rampWindow: Int,
    /** Growth events spent inside the current weekly window, and its age. */
    var weekGain: MutableMap<Pattern, Int>,
    /** FRACTIONAL: rounding would lose the fraction of a day for good. */
    var weekAgeDays: Double,
) {

    /** Swift's `var copy = state`: a deep copy, so no map is shared. */
    fun copy(): EngineState = EngineState(
        counter = counter, vars = vars.toMutableMap(), doses = doses.toMutableMap(),
        failStreak = failStreak.toMutableMap(), hasBar = hasBar, sets = sets.toMutableMap(),
        sub = sub.toMutableMap(), cut = cut.toMutableMap(),
        shown = shown.mapValuesTo(mutableMapOf()) { it.value.toMutableMap() },
        setsHold = setsHold.toMutableMap(), shownWork = shownWork.toMutableMap(),
        shownOrd = shownOrd.toMutableMap(), shownCap = shownCap.toMutableMap(),
        shownOwn = shownOwn.toMutableMap(), shownSkip = shownSkip.toMutableSet(),
        lastHard = lastHard.toMutableSet(), lessRun = lessRun,
        creditPaused = creditPaused.toMutableSet(), returnRun = returnRun,
        lessHist = lessHist.toMutableMap(), rampWindow = rampWindow,
        weekGain = weekGain.toMutableMap(), weekAgeDays = weekAgeDays)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EngineState) return false
        return counter == other.counter && hasBar == other.hasBar &&
            vars == other.vars && doses == other.doses && sets == other.sets &&
            sub == other.sub && cut == other.cut && shown == other.shown &&
            setsHold == other.setsHold && shownWork == other.shownWork &&
            shownOrd == other.shownOrd && shownCap == other.shownCap &&
            shownOwn == other.shownOwn && shownSkip == other.shownSkip &&
            failStreak == other.failStreak && lastHard == other.lastHard &&
            lessRun == other.lessRun && creditPaused == other.creditPaused &&
            returnRun == other.returnRun && lessHist == other.lessHist &&
            rampWindow == other.rampWindow && weekGain == other.weekGain &&
            // Swift's `==` on Double: 0.0 equals -0.0.
            weekAgeDays == other.weekAgeDays
    }

    override fun hashCode(): Int {
        var h = counter
        h = 31 * h + vars.hashCode()
        h = 31 * h + doses.hashCode()
        h = 31 * h + shown.hashCode()
        return h
    }

    override fun toString(): String =
        "EngineState(counter=$counter, hasBar=$hasBar, vars=$vars, doses=$doses, sets=$sets, " +
            "sub=$sub, cut=$cut, shown=$shown, failStreak=$failStreak, setsHold=$setsHold, " +
            "shownWork=$shownWork, shownOrd=$shownOrd, shownCap=$shownCap, shownOwn=$shownOwn, " +
            "shownSkip=$shownSkip, lastHard=$lastHard, lessRun=$lessRun, " +
            "creditPaused=$creditPaused, returnRun=$returnRun, lessHist=$lessHist, " +
            "rampWindow=$rampWindow, weekGain=$weekGain, weekAgeDays=$weekAgeDays)"

    /**
     * The state as the engine is willing to read it. On the valid domain this
     * is the identity, which is what keeps the golden fixture bit-for-bit.
     *
     * The ORDER matters and mirrors `readState`: variations first (they fix
     * the unit and the set ceiling), then sets, then doses, then the cut, then
     * the sub-step, which needs all four. Every map of the result is new.
     */
    fun sanitized(): EngineState {
        val cleanVars = mutableMapOf<Pattern, Int>()
        val cleanStreaks = mutableMapOf<Pattern, Int>()
        for (p in Pattern.allCases) {
            cleanVars[p] = clamped(vars[p] ?: 1, 1, Library.count(p))
            cleanStreaks[p] = clamped(failStreak[p] ?: 0, 0, EngineConfig.countMax)
        }
        val cleanSets = mutableMapOf<Pattern, Int>()
        val cleanDoses = mutableMapOf<Pattern, Int>()
        for (p in Pattern.allCases) {
            val v = cleanVars.getValue(p)
            val raw = sets[p]
            if (raw != null) {
                val value = clamped(raw, EngineConfig.setsBase, Engine.setsCeil(p, v))
                if (value != EngineConfig.setsBase) cleanSets[p] = value
            }
            val unit = Library.unit(p, v)
            cleanDoses[p] = doses[p]?.let { Dose.clamped(unit, Dose.snap(unit, it)) } ?: Dose.grid(unit).min
        }
        val cleanCut = mutableMapOf<Pattern, Int>()
        for ((p, raw) in cut) {
            val value = Engine.effCut(sets = cleanSets[p] ?: EngineConfig.setsBase, cut = raw)
            if (value > 0) cleanCut[p] = value
        }
        val cleanSub = cleanedSub(vars = cleanVars, sets = cleanSets, doses = cleanDoses, cut = cleanCut)
        return EngineState(
            counter = clamped(counter, 0, EngineConfig.countMax),
            vars = cleanVars, doses = cleanDoses, failStreak = cleanStreaks, hasBar = hasBar,
            sets = cleanSets, sub = cleanSub, cut = cleanCut,
            shown = healShown(shown),
            setsHold = setsHold.filterValues { it >= 1 }
                .mapValuesTo(mutableMapOf()) { clamped(it.value, 1, EngineConfig.setsBackHold) },
            shownWork = shownWork.filterValues { it > 0 }.toMutableMap(),
            shownOrd = shownOrd.toMutableMap(),
            shownCap = healPushSets(shownCap), shownOwn = healPushSets(shownOwn),
            shownSkip = shownSkip.intersect(Pattern.pushSide).toMutableSet(),
            lastHard = lastHard.toMutableSet(),
            lessRun = clamped(lessRun, 0, EngineConfig.countMax),
            creditPaused = creditPaused.intersect(Pattern.pullSide).toMutableSet(),
            returnRun = clamped(returnRun, 0, EngineConfig.countMax),
            lessHist = lessHist.filterValues { it >= 1 }
                .mapValuesTo(mutableMapOf()) { clamped(it.value, 1, chronicMaskMax) },
            rampWindow = clamped(rampWindow, 0, EngineConfig.rampWindowSessions),
            weekGain = weekGain.filterValues { it >= 1 }
                .mapValuesTo(mutableMapOf()) { clamped(it.value, 1, EngineConfig.countMax) },
            weekAgeDays = clamped(weekAgeDays, 0.0, EngineConfig.countMax.toDouble()))
    }

    /** The sub-step of `sanitized`, read last because it needs the other four
     *  coordinates already clean. */
    private fun cleanedSub(vars: Map<Pattern, Int>, sets: Map<Pattern, Int>,
                           doses: Map<Pattern, Int>, cut: Map<Pattern, Int>): MutableMap<Pattern, Int> {
        val cleanSub = mutableMapOf<Pattern, Int>()
        for ((p, raw) in sub) {
            val pos = Position(variation = vars[p] ?: 1,
                               sets = sets[p] ?: EngineConfig.setsBase,
                               dose = doses[p] ?: 0, sub = raw,
                               cut = cut[p] ?: 0)
            val value = Engine.effSub(p, pos, sets = null)
            if (value > 0) cleanSub[p] = value
        }
        return cleanSub
    }

    /** The sets taken off a pattern, zero when none are. */
    fun cutOf(pattern: Pattern): Int = cut[pattern] ?: 0

    /** The pattern's place on its ladder — all five coordinates. */
    fun position(pattern: Pattern): Position = Position(
        variation = vars[pattern] ?: 1,
        sets = sets[pattern] ?: EngineConfig.setsBase,
        dose = doses[pattern] ?: 0,
        sub = sub[pattern] ?: 0,
        cut = cut[pattern] ?: 0)

    /** The last dose recorded for a variation, if the trainee has ever been
     *  there. Only tests read it. */
    fun shownDose(pattern: Pattern, variation: Int): Int? = shown[pattern]?.get(variation)

    /** How many of the last appearances fell in a failed session. */
    internal fun chronicHits(pattern: Pattern): Int = (lessHist[pattern] ?: 0).countOneBits()

    /** Does the chronic signal fire for this pattern? */
    internal fun chronicFires(pattern: Pattern): Boolean = chronicHits(pattern) >= EngineConfig.chronicHits

    // MARK: - The wire format

    /** The JSON Swift's synthesized `Encodable` writes for this struct. */
    fun toJson(): JsonObject = JsonObject(linkedMapOf(
        "counter" to JsonPrimitive(counter),
        "hasBar" to JsonPrimitive(hasBar),
        "vars" to encodeMap(vars),
        "doses" to encodeMap(doses),
        "sets" to encodeMap(sets),
        "sub" to encodeMap(sub),
        "cut" to encodeMap(cut),
        "shown" to JsonArray(shown.entries.sortedBy { it.key.ordinal }.flatMap { (p, row) ->
            listOf(JsonPrimitive(p.rawValue),
                   JsonObject(row.entries.sortedBy { it.key }
                       .associate { it.key.toString() to JsonPrimitive(it.value) }))
        }),
        "setsHold" to encodeMap(setsHold),
        "shownWork" to encodeMap(shownWork),
        "shownOrd" to encodeMap(shownOrd),
        "shownCap" to encodeMap(shownCap),
        "shownOwn" to encodeMap(shownOwn),
        "shownSkip" to encodeSet(shownSkip),
        "failStreak" to encodeMap(failStreak),
        "lastHard" to encodeSet(lastHard),
        "lessRun" to JsonPrimitive(lessRun),
        "creditPaused" to encodeSet(creditPaused),
        "returnRun" to JsonPrimitive(returnRun),
        "lessHist" to encodeMap(lessHist),
        "rampWindow" to JsonPrimitive(rampWindow),
        "weekGain" to encodeMap(weekGain),
        "weekAgeDays" to JsonPrimitive(weekAgeDays),
    ))

    fun encode(): String = toJson().toString()

    companion object {

        /** A clean start — every pattern on its first rung, 3×4 (3×15 s).
         *  A NEW instance on every read: the state is mutable here. */
        val initial: EngineState
            get() {
                val vars = mutableMapOf<Pattern, Int>()
                val doses = mutableMapOf<Pattern, Int>()
                val streaks = mutableMapOf<Pattern, Int>()
                for (p in Pattern.allCases) {
                    vars[p] = 1
                    doses[p] = Dose.grid(Library.unit(p, 1)).min
                    streaks[p] = 0
                }
                return EngineState(
                    counter = 0, vars = vars, doses = doses, failStreak = streaks,
                    hasBar = false, sets = mutableMapOf(), sub = mutableMapOf(), cut = mutableMapOf(),
                    shown = mutableMapOf(), setsHold = mutableMapOf(), shownWork = mutableMapOf(),
                    shownOrd = mutableMapOf(), shownCap = mutableMapOf(), shownOwn = mutableMapOf(),
                    shownSkip = mutableSetOf(), lastHard = mutableSetOf(), lessRun = 0,
                    creditPaused = mutableSetOf(), returnRun = 0, lessHist = mutableMapOf(),
                    rampWindow = 0, weekGain = mutableMapOf(), weekAgeDays = 0.0)
            }

        fun clamped(v: Int, lo: Int, hi: Int): Int = min(max(v, lo), hi)

        /** The same clamp for the fractional window age. A NaN is turned into
         *  the floor here rather than smuggled into the arithmetic. */
        fun clamped(v: Double, lo: Double, hi: Double): Double = if (v.isFinite()) min(max(v, lo), hi) else lo

        /** The widest a window mask can be. */
        internal val chronicMaskMax: Int get() = (1 shl EngineConfig.chronicWindow) - 1

        /** The journal, healed: snapped and capped by the SCALE of the variation
         *  it belongs to, NOT clamped from below ("I showed two reps" is a fact). */
        internal fun healShown(src: Map<Pattern, Map<Int, Int>>): MutableMap<Pattern, MutableMap<Int, Int>> {
            val out = mutableMapOf<Pattern, MutableMap<Int, Int>>()
            for (p in Pattern.allCases) {
                val row = src[p] ?: continue
                val dst = mutableMapOf<Int, Int>()
                for (v in 1..Library.count(p)) {
                    val raw = row[v] ?: continue
                    val unit = Library.unit(p, v)
                    val d = min(Dose.snap(unit, raw), Dose.grid(unit).max)
                    if (d > 0) dst[v] = d
                }
                if (dst.isNotEmpty()) out[p] = dst
            }
            return out
        }

        /** The pull-cap memory, healed: push keys only, never below the floor,
         *  never above the scale. */
        internal fun healPushSets(src: Map<Pattern, Int>): MutableMap<Pattern, Int> =
            src.filterKeys { it in Pattern.pushSide }
                .mapValuesTo(mutableMapOf()) { clamped(it.value, EngineConfig.setsFloor, EngineConfig.setsMax) }

        /** Swift's `JSONDecoder().decode(EngineState.self, from:)`. */
        fun decode(text: String): EngineState {
            val root = try {
                Json.parseToJsonElement(text)
            } catch (e: IllegalArgumentException) {
                throw EngineStateDecodingException("not JSON: ${e.message}")
            }
            return fromJson(root)
        }

        /**
         * `counter`, `vars` and `doses` are REQUIRED: a v2 file has `levels`
         * instead and throws here, which is what sends the app to the v2 reader.
         * Every other field is additive and tolerant — absent or unreadable, it
         * opens at its default — so a v3 file from an older or a newer build
         * keeps its positions.
         */
        fun fromJson(element: JsonElement): EngineState {
            val c = element as? JsonObject ?: throw EngineStateDecodingException("not an object")
            val counter = c["counter"]?.let { wireInt(it) }
                ?: throw EngineStateDecodingException("counter: missing or not an integer")
            val vars = decodeLenient(c["vars"]) ?: throw EngineStateDecodingException("vars")
            val doses = decodeLenient(c["doses"]) ?: throw EngineStateDecodingException("doses")
            return EngineState(
                counter = clamped(counter, 0, EngineConfig.countMax),
                vars = vars, doses = doses,
                failStreak = optionalMap(c, "failStreak"),
                hasBar = c["hasBar"]?.let { wireBool(it) } ?: false,
                sets = optionalMap(c, "sets"),
                sub = optionalMap(c, "sub"),
                cut = optionalMap(c, "cut"),
                shown = c["shown"]?.let { decodeShown(it) } ?: mutableMapOf(),
                setsHold = optionalMap(c, "setsHold"),
                shownWork = optionalMap(c, "shownWork"),
                shownOrd = optionalMap(c, "shownOrd"),
                shownCap = optionalMap(c, "shownCap"),
                shownOwn = optionalMap(c, "shownOwn"),
                shownSkip = optionalSet(c, "shownSkip"),
                lastHard = optionalSet(c, "lastHard"),
                lessRun = clamped(c["lessRun"]?.let { wireInt(it) } ?: 0, 0, EngineConfig.countMax),
                creditPaused = optionalSet(c, "creditPaused").intersect(Pattern.pullSide).toMutableSet(),
                returnRun = clamped(c["returnRun"]?.let { wireInt(it) } ?: 0, 0, EngineConfig.countMax),
                lessHist = optionalMap(c, "lessHist"),
                rampWindow = clamped(c["rampWindow"]?.let { wireInt(it) } ?: 0,
                                     0, EngineConfig.rampWindowSessions),
                weekGain = optionalMap(c, "weekGain"),
                weekAgeDays = clamped(c["weekAgeDays"]?.let { wireDouble(it) } ?: 0.0,
                                      0.0, EngineConfig.countMax.toDouble()))
        }

        /** An optional map, absent OR unreadable, opens empty. */
        private fun optionalMap(c: JsonObject, key: String): MutableMap<Pattern, Int> =
            decodeLenient(c[key]) ?: mutableMapOf()

        /** `try? decodeIfPresent([String].self)`: one non-string element fails the
         *  whole array, and unknown raw values are dropped. */
        private fun optionalSet(c: JsonObject, key: String): MutableSet<Pattern> {
            val array = c[key] as? JsonArray ?: return mutableSetOf()
            val raws = array.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
            if (raws.any { it == null }) return mutableSetOf()
            return raws.mapNotNullTo(mutableSetOf()) { Pattern.fromRaw(it!!) }
        }

        /**
         * The exact wire format Swift synthesizes for a `[Pattern: Int]`: an
         * UNKEYED array alternating [rawValue, count, ...]. Entries for unknown
         * patterns (a file written by a future version) are dropped; a
         * malformed pair fails the map. Null means "failed".
         */
        private fun decodeLenient(element: JsonElement?): MutableMap<Pattern, Int>? {
            val array = element as? JsonArray ?: return null
            if (array.size % 2 != 0) return null
            val out = mutableMapOf<Pattern, Int>()
            for (i in array.indices step 2) {
                val raw = (array[i] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
                val value = wireInt(array[i + 1]) ?: return null
                Pattern.fromRaw(raw)?.let { out[it] = value }
            }
            return out
        }

        /** The journal, one level deeper: the inner `[Int: Int]` is a keyed
         *  object because Swift special-cases integer keys. Null on failure,
         *  which opens the whole journal empty, as Swift's `try?` does. */
        private fun decodeShown(element: JsonElement): MutableMap<Pattern, MutableMap<Int, Int>>? {
            val array = element as? JsonArray ?: return null
            if (array.size % 2 != 0) return null
            val out = mutableMapOf<Pattern, MutableMap<Int, Int>>()
            for (i in array.indices step 2) {
                val raw = (array[i] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
                val obj = array[i + 1] as? JsonObject ?: return null
                val row = mutableMapOf<Int, Int>()
                for ((key, value) in obj) {
                    // Swift reads the key with `Int(String)`: a sign is allowed,
                    // a blank is not — the same as `toLongOrNull`.
                    val v = key.toLongOrNull() ?: return null
                    row[saturated(v)] = wireInt(value) ?: return null
                }
                Pattern.fromRaw(raw)?.let { out[it] = row }
            }
            return out
        }

        /**
         * A JSON number as Swift's `JSONDecoder` reads it into `Int`: any
         * integral value that fits 64 bits (`1.0` and `1e2` included), never a
         * string or a bool. Swift's Int is 64-bit; a value past 32 bits is held
         * at the edge of Kotlin's Int — every reader clamps far inside it, so
         * the result is the one Swift computes.
         */
        private fun wireInt(e: JsonElement): Int? {
            val p = e as? JsonPrimitive ?: return null
            if (p is JsonNull || p.isString || p.content == "true" || p.content == "false") return null
            val exact = p.content.toLongOrNull() ?: try {
                BigDecimal(p.content).let { d ->
                    if (d.stripTrailingZeros().scale() > 0) return null
                    d.longValueExact()
                }
            } catch (e: ArithmeticException) {
                return null
            } catch (e: NumberFormatException) {
                return null
            }
            return saturated(exact)
        }

        private fun wireDouble(e: JsonElement): Double? {
            val p = e as? JsonPrimitive ?: return null
            if (p is JsonNull || p.isString || p.content == "true" || p.content == "false") return null
            return p.content.toDoubleOrNull()?.takeIf { it.isFinite() }
        }

        private fun wireBool(e: JsonElement): Boolean? {
            val p = e as? JsonPrimitive ?: return null
            if (p is JsonNull || p.isString) return null
            return when (p.content) {
                "true" -> true
                "false" -> false
                else -> null
            }
        }

        private fun saturated(v: Long): Int = v.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()

        private fun encodeMap(map: Map<Pattern, Int>): JsonArray =
            JsonArray(map.entries.sortedBy { it.key.ordinal }
                .flatMap { listOf(JsonPrimitive(it.key.rawValue), JsonPrimitive(it.value)) })

        private fun encodeSet(set: Set<Pattern>): JsonArray =
            JsonArray(set.sortedBy { it.ordinal }.map { JsonPrimitive(it.rawValue) })
    }
}
