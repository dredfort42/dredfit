//
//  What a finished workout leaves behind, and what an unfinished one holds
//  on to. Both are read back out of one JSON file, so both are inputs.
//
//  Port of ios/Dredfit/Journal.swift; the reasoning behind every field and
//  every clamp is there. THE WIRE FORMAT IS THE iOS ONE: a backup exported on
//  either platform imports on the other, so every reader here throws exactly
//  where Swift's synthesized `Decodable` throws — a record one side drops, the
//  other must drop too.
//

package com.dredfit.journal

import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.SwiftDecodingException
import com.dredfit.core.SwiftJson
import com.dredfit.workout.Countdown
import com.dredfit.workout.SetFacts
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

private fun clamp(v: Int, lo: Int, hi: Int): Int = minOf(maxOf(v, lo), hi)

/** Where a pattern stood, in the terms v3 states a position in. Its
 *  coordinates and no measure: the measure has no inverse. */
data class RecordedPosition(
    val variation: Int,
    val sets: Int,
    val dose: Int,
    /** The two sparse coordinates — nil encodes to nothing, so a position
     *  that never saw a sub-step stays byte-identical on disk. */
    val sub: Int? = null,
    val cut: Int? = null,
) {
    fun toJson(): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "variation" to JsonPrimitive(variation),
            "sets" to JsonPrimitive(sets),
            "dose" to JsonPrimitive(dose),
        )
        sub?.let { out["sub"] = JsonPrimitive(it) }
        cut?.let { out["cut"] = JsonPrimitive(it) }
        return JsonObject(out)
    }

    companion object {
        /** Clamped on the way in: these go straight into `Engine.progress`.
         *  `dose` keeps its sign — a descent legitimately reads below a grid's
         *  floor. */
        fun fromJson(e: JsonElement): RecordedPosition {
            val c = e as? JsonObject ?: throw SwiftDecodingException("position: not an object")
            val max = EngineConfig.countMax
            return RecordedPosition(
                variation = clamp(SwiftJson.required(c, "variation", SwiftJson::int), 1, max),
                sets = clamp(SwiftJson.required(c, "sets", SwiftJson::int), 0, max),
                dose = clamp(SwiftJson.required(c, "dose", SwiftJson::int), -max, max),
                sub = SwiftJson.optional(c, "sub", SwiftJson::int)?.let { clamp(it, 0, max) },
                cut = SwiftJson.optional(c, "cut", SwiftJson::int)?.let { clamp(it, 0, max) })
        }
    }
}

/**
 * One finished workout. Every field after `result` is optional with a nil
 * default — the rule for every field added to a persisted type — so a record
 * written by any older build still reads. Field docs: Journal.swift.
 */
data class WorkoutRecord(
    val sessionNumber: Int,
    val date: Instant,
    val result: FeedbackResult,
    val totalProgressAfter: Int? = null,
    val exercises: List<SessionExercise>? = null,
    val heldBack: Set<Pattern>? = null,
    val actuals: Map<Pattern, Int>? = null,
    val setActuals: Map<Pattern, List<Int>>? = null,
    val probes: Map<Pattern, Int>? = null,
    val setsSkipped: Map<Pattern, Int>? = null,
    val skippedSetIndices: Map<Pattern, List<Int>>? = null,
    val skippedWithNumberIndices: Map<Pattern, List<Int>>? = null,
    val skipped: Set<Pattern>? = null,
    /** LEGACY and read-only: the pain reports of an older build. */
    val discomfort: Set<Pattern>? = null,
    val positionsAfter: Map<Pattern, RecordedPosition>? = null,
    val durationSec: Int? = null,
    val warmupSec: Int? = null,
    val cooldownSec: Int? = null,
    /** Only `true` is ever written; nil means "not exported yet". */
    val healthExported: Boolean? = null,
    val interrupted: Pattern? = null,
    val raisedSteps: Map<Pattern, Int>? = null,
    val raisedLanded: Map<Pattern, Int>? = null,
) {
    /** sessionNumber alone is NOT unique: a reset restarts the counter while
     *  the journal survives, so identity needs the date too. In-process only
     *  — never written — so the exact instant stands in for Swift's Double. */
    val id: String get() = "$sessionNumber-$date"

    /** What the plan after this record may call the person's own addition. */
    fun raisedShare(pattern: Pattern): Int = (raisedLanded ?: raisedSteps)?.get(pattern) ?: 0

    val skippedSets: Map<Pattern, Set<Int>>
        get() = SetFacts.sanitizedSkippedSets(skippedSetIndices ?: emptyMap())

    val skippedWithNumber: Map<Pattern, Set<Int>>
        get() = SetFacts.sanitizedSkippedSets(skippedWithNumberIndices ?: emptyMap())

    val leftOutSets: Map<Pattern, Set<Int>>
        get() = SetFacts.leftOut(skippedSets, keeping = skippedWithNumber)

    /** Swift's synthesized `Encodable`: a nil field is left out. */
    fun toJson(): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "sessionNumber" to JsonPrimitive(sessionNumber),
            "date" to SwiftJson.date(date),
            "result" to JsonPrimitive(result.rawValue),
        )
        totalProgressAfter?.let { out["totalProgressAfter"] = JsonPrimitive(it) }
        exercises?.let { list -> out["exercises"] = JsonArray(list.map { it.toJson() }) }
        heldBack?.let { out["heldBack"] = SwiftJson.encodePatternSet(it) }
        actuals?.let { out["actuals"] = SwiftJson.encodePatternMap(it) }
        setActuals?.let { out["setActuals"] = encodeIntLists(it) }
        probes?.let { out["probes"] = SwiftJson.encodePatternMap(it) }
        setsSkipped?.let { out["setsSkipped"] = SwiftJson.encodePatternMap(it) }
        skippedSetIndices?.let { out["skippedSetIndices"] = encodeIntLists(it) }
        skippedWithNumberIndices?.let { out["skippedWithNumberIndices"] = encodeIntLists(it) }
        skipped?.let { out["skipped"] = SwiftJson.encodePatternSet(it) }
        discomfort?.let { out["discomfort"] = SwiftJson.encodePatternSet(it) }
        positionsAfter?.let { map -> out["positionsAfter"] = SwiftJson.encodePatternMap(map) { it.toJson() } }
        durationSec?.let { out["durationSec"] = JsonPrimitive(it) }
        warmupSec?.let { out["warmupSec"] = JsonPrimitive(it) }
        cooldownSec?.let { out["cooldownSec"] = JsonPrimitive(it) }
        healthExported?.let { out["healthExported"] = JsonPrimitive(it) }
        interrupted?.let { out["interrupted"] = JsonPrimitive(it.rawValue) }
        raisedSteps?.let { out["raisedSteps"] = SwiftJson.encodePatternMap(it) }
        raisedLanded?.let { out["raisedLanded"] = SwiftJson.encodePatternMap(it) }
        return JsonObject(out)
    }

    companion object {
        /**
         * Swift's `init(from:)`: `try c.decodeIfPresent` everywhere, so a
         * field of the wrong shape — an unknown pattern among them — throws
         * and the caller drops THIS record, never the journal. Every number is
         * clamped to the range it can mean: the journal comes back into
         * arithmetic, and a hand-edited `Int.min` must saturate, not trap.
         */
        fun fromJson(e: JsonElement): WorkoutRecord {
            val c = e as? JsonObject ?: throw SwiftDecodingException("record: not an object")
            val max = EngineConfig.countMax
            val setsMax = EngineConfig.setsMax
            val raiseMax = EngineConfig.raiseStepsMax
            fun intMap(key: String) = SwiftJson.optional(c, key) { SwiftJson.patternMap(it, SwiftJson::int) }
            fun listMap(key: String) = SwiftJson.optional(c, key) { SwiftJson.patternMap(it, SwiftJson::intList) }
            fun patternSet(key: String) = SwiftJson.optional(c, key) { SwiftJson.patternList(it)?.toSet() }
            fun count(key: String) = SwiftJson.optional(c, key, SwiftJson::int)?.let { clamp(it, 0, max) }
            // An index is not clamped, it is kept or dropped: clamped, it
            // would name a different set.
            fun indices(key: String) = listMap(key)?.mapValues { (_, v) -> v.filter { it in 0 until setsMax } }
            return WorkoutRecord(
                sessionNumber = clamp(SwiftJson.required(c, "sessionNumber", SwiftJson::int), 0, max),
                date = SwiftJson.required(c, "date", SwiftJson::date),
                result = SwiftJson.required(c, "result") { SwiftJson.string(it)?.let(FeedbackResult::fromRaw) },
                totalProgressAfter = count("totalProgressAfter"),
                exercises = SwiftJson.optional(c, "exercises") { a ->
                    (a as? JsonArray)?.map { SessionExercise.fromJson(it) }
                },
                heldBack = patternSet("heldBack"),
                actuals = intMap("actuals")?.mapValues { clamp(it.value, 0, max) },
                // No exercise has more sets than the scale has bands.
                setActuals = listMap("setActuals")?.mapValues { (_, v) -> v.take(setsMax).map { clamp(it, 0, max) } },
                probes = intMap("probes")?.mapValues { clamp(it.value, 0, max) },
                setsSkipped = intMap("setsSkipped")?.mapValues { clamp(it.value, 0, setsMax) },
                skippedSetIndices = indices("skippedSetIndices"),
                skippedWithNumberIndices = indices("skippedWithNumberIndices"),
                skipped = patternSet("skipped"),
                discomfort = patternSet("discomfort"),
                positionsAfter = SwiftJson.optional(c, "positionsAfter") { a ->
                    SwiftJson.patternMap(a) { RecordedPosition.fromJson(it) }
                },
                durationSec = count("durationSec"),
                warmupSec = count("warmupSec"),
                cooldownSec = count("cooldownSec"),
                healthExported = SwiftJson.optional(c, "healthExported", SwiftJson::bool),
                interrupted = SwiftJson.optional(c, "interrupted", SwiftJson::pattern),
                // The range the engine itself accepts (`raiseStepsMax`).
                raisedSteps = intMap("raisedSteps")?.mapValues { clamp(it.value, 0, raiseMax) },
                raisedLanded = intMap("raisedLanded")?.mapValues { clamp(it.value, 0, raiseMax) })
        }
    }
}

/** How long one guided block ran, resolved once at its ending. No start
 *  means the block was DECLINED: zero, not unknown — unknown falls back to
 *  the planned length, declined bills nothing. */
object BlockRun {
    fun seconds(began: Instant?, ended: Instant): Int {
        if (began == null) return 0
        return maxOf(0, Countdown.seconds(began, ended).toInt())
    }
}

internal fun encodeIntLists(map: Map<Pattern, List<Int>>): JsonArray =
    SwiftJson.encodePatternMap(map) { SwiftJson.encodeInts(it) }

/**
 * The workout in progress, written on every phase transition. Synthesized
 * `Codable` on iOS — so, unlike the record, the non-optional fields are
 * REQUIRED on the wire (Swift ignores a property's default when decoding) and
 * nothing is clamped on the way in: it is sanitized where it is read. The
 * whole snapshot decodes under `try?`, so any failure is "nothing to resume".
 * Field docs: Journal.swift.
 */
data class WorkoutSnapshot(
    val sessionNumber: Int,
    val exIndex: Int,
    val setIndex: Int,
    val restEndDate: Instant? = null,
    val restTotalSec: Int? = null,
    val restPlannedSec: Int? = null,
    val setActuals: Map<Pattern, List<Int>>? = null,
    val setsSkipped: Map<Pattern, Int>? = null,
    val skippedSetIndices: Map<Pattern, List<Int>>? = null,
    val skippedWithNumberIndices: Map<Pattern, List<Int>>? = null,
    val probes: Map<Pattern, Int>? = null,
    /** The shape that came before — one number per exercise. Only decoded. */
    val actuals: Map<Pattern, Int> = emptyMap(),
    val skipped: Set<Pattern> = emptySet(),
    val discomfort: Set<Pattern>? = null,
    val workoutStart: Instant,
    val savedAt: Instant,
    val fingerprint: String? = null,
    val atFeedback: Boolean? = null,
    val atExerciseSummary: Boolean? = null,
    val holdDeclaredSec: Int? = null,
    val approxSets: List<Int>? = null,
    val tapEndedSets: List<Int>? = null,
    val holdMeasuredSec: Map<Int, Int>? = null,
    val interrupted: Pattern? = null,
    val warmupSec: Int? = null,
    val cooldownSec: Int? = null,
    val awaySec: Int? = null,
    val raisedSteps: Map<Pattern, Int>? = null,
) {
    /** What the flow restores into; an older snapshot's one number per
     *  exercise is a one-element array. Sanitized: this came off disk. */
    val facts: Map<Pattern, List<Int>>
        get() = SetFacts.sanitized(setActuals ?: actuals.mapValues { listOf(it.value) })

    /** The probe's own channel, clamped like every count off disk. */
    val probeFacts: Map<Pattern, Int>
        get() = (probes ?: emptyMap()).mapValues { clamp(it.value, 0, EngineConfig.countMax) }

    val skips: Map<Pattern, Int> get() = SetFacts.sanitizedSkips(setsSkipped ?: emptyMap())

    val skippedSets: Map<Pattern, Set<Int>> get() = SetFacts.sanitizedSkippedSets(skippedSetIndices ?: emptyMap())

    val skippedWithNumber: Map<Pattern, Set<Int>>
        get() = SetFacts.sanitizedSkippedSets(skippedWithNumberIndices ?: emptyMap())

    /** The additions "for next time", in the range the engine takes. */
    val raises: Map<Pattern, Int>
        get() = (raisedSteps ?: emptyMap()).mapValues { clamp(it.value, 0, EngineConfig.raiseStepsMax) }
            .filterValues { it > 0 }

    /** What the clock wrote per set: indices an exercise can have, seconds a
     *  hold can be stored as. */
    val measuredHold: Map<Int, Int>
        get() {
            val corridor = SetFacts.corridor(LoadUnit.hold)
            return (holdMeasuredSec ?: emptyMap())
                .filter { (index, seconds) -> index in 0 until EngineConfig.setsMax && seconds in corridor }
        }

    val approximateSets: Set<Int>
        get() = (approxSets ?: emptyList()).filter { it in 0 until EngineConfig.setsMax }.toSet()

    val endedByTapSets: Set<Int>
        get() = (tapEndedSets ?: emptyList()).filter { it in 0 until EngineConfig.setsMax }.toSet()

    /** Whether anything happened worth keeping — the one answer to both
     *  "offer it back?" and "record it when the occasion has passed?". */
    val hasProgress: Boolean
        get() = atFeedback == true || atExerciseSummary == true || restEndDate != null ||
            exIndex > 0 || setIndex > 0 || facts.isNotEmpty() || skipped.isNotEmpty() ||
            !discomfort.isNullOrEmpty()

    fun toJson(): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "sessionNumber" to JsonPrimitive(sessionNumber),
            "exIndex" to JsonPrimitive(exIndex),
            "setIndex" to JsonPrimitive(setIndex),
        )
        restEndDate?.let { out["restEndDate"] = SwiftJson.date(it) }
        restTotalSec?.let { out["restTotalSec"] = JsonPrimitive(it) }
        restPlannedSec?.let { out["restPlannedSec"] = JsonPrimitive(it) }
        setActuals?.let { out["setActuals"] = encodeIntLists(it) }
        setsSkipped?.let { out["setsSkipped"] = SwiftJson.encodePatternMap(it) }
        skippedSetIndices?.let { out["skippedSetIndices"] = encodeIntLists(it) }
        skippedWithNumberIndices?.let { out["skippedWithNumberIndices"] = encodeIntLists(it) }
        probes?.let { out["probes"] = SwiftJson.encodePatternMap(it) }
        out["actuals"] = SwiftJson.encodePatternMap(actuals)
        out["skipped"] = SwiftJson.encodePatternSet(skipped)
        discomfort?.let { out["discomfort"] = SwiftJson.encodePatternSet(it) }
        out["workoutStart"] = SwiftJson.date(workoutStart)
        out["savedAt"] = SwiftJson.date(savedAt)
        fingerprint?.let { out["fingerprint"] = JsonPrimitive(it) }
        atFeedback?.let { out["atFeedback"] = JsonPrimitive(it) }
        atExerciseSummary?.let { out["atExerciseSummary"] = JsonPrimitive(it) }
        holdDeclaredSec?.let { out["holdDeclaredSec"] = JsonPrimitive(it) }
        approxSets?.let { out["approxSets"] = SwiftJson.encodeInts(it) }
        tapEndedSets?.let { out["tapEndedSets"] = SwiftJson.encodeInts(it) }
        holdMeasuredSec?.let { map -> out["holdMeasuredSec"] = SwiftJson.encodeIntKeyedMap(map) { JsonPrimitive(it) } }
        interrupted?.let { out["interrupted"] = JsonPrimitive(it.rawValue) }
        warmupSec?.let { out["warmupSec"] = JsonPrimitive(it) }
        cooldownSec?.let { out["cooldownSec"] = JsonPrimitive(it) }
        awaySec?.let { out["awaySec"] = JsonPrimitive(it) }
        raisedSteps?.let { out["raisedSteps"] = SwiftJson.encodePatternMap(it) }
        return JsonObject(out)
    }

    companion object {
        fun fromJson(e: JsonElement): WorkoutSnapshot {
            val c = e as? JsonObject ?: throw SwiftDecodingException("snapshot: not an object")
            fun intMap(key: String) = SwiftJson.optional(c, key) { SwiftJson.patternMap(it, SwiftJson::int) }
            fun listMap(key: String) = SwiftJson.optional(c, key) { SwiftJson.patternMap(it, SwiftJson::intList) }
            fun int(key: String) = SwiftJson.optional(c, key, SwiftJson::int)
            return WorkoutSnapshot(
                sessionNumber = SwiftJson.required(c, "sessionNumber", SwiftJson::int),
                exIndex = SwiftJson.required(c, "exIndex", SwiftJson::int),
                setIndex = SwiftJson.required(c, "setIndex", SwiftJson::int),
                restEndDate = SwiftJson.optional(c, "restEndDate", SwiftJson::date),
                restTotalSec = int("restTotalSec"),
                restPlannedSec = int("restPlannedSec"),
                setActuals = listMap("setActuals"),
                setsSkipped = intMap("setsSkipped"),
                skippedSetIndices = listMap("skippedSetIndices"),
                skippedWithNumberIndices = listMap("skippedWithNumberIndices"),
                probes = intMap("probes"),
                actuals = SwiftJson.required(c, "actuals") { SwiftJson.patternMap(it, SwiftJson::int) },
                skipped = SwiftJson.required(c, "skipped") { SwiftJson.patternList(it)?.toSet() },
                discomfort = SwiftJson.optional(c, "discomfort") { SwiftJson.patternList(it)?.toSet() },
                workoutStart = SwiftJson.required(c, "workoutStart", SwiftJson::date),
                savedAt = SwiftJson.required(c, "savedAt", SwiftJson::date),
                fingerprint = SwiftJson.optional(c, "fingerprint", SwiftJson::string),
                atFeedback = SwiftJson.optional(c, "atFeedback", SwiftJson::bool),
                atExerciseSummary = SwiftJson.optional(c, "atExerciseSummary", SwiftJson::bool),
                holdDeclaredSec = int("holdDeclaredSec"),
                approxSets = SwiftJson.optional(c, "approxSets", SwiftJson::intList),
                tapEndedSets = SwiftJson.optional(c, "tapEndedSets", SwiftJson::intList),
                holdMeasuredSec = SwiftJson.optional(c, "holdMeasuredSec") { SwiftJson.intKeyedMap(it, SwiftJson::int) },
                interrupted = SwiftJson.optional(c, "interrupted", SwiftJson::pattern),
                warmupSec = int("warmupSec"),
                cooldownSec = int("cooldownSec"),
                awaySec = int("awaySec"),
                raisedSteps = intMap("raisedSteps"))
        }

        /** The identity of the plan a snapshot was taken from — see
         *  Journal.swift for why the probe and the per-set doses are in it. */
        fun fingerprint(of: Session): String =
            of.exercises.joinToString("|") { ex ->
                var head = "${ex.pattern.rawValue}:${ex.variation}:${ex.load}:${ex.sets}"
                ex.probe?.let { head += ":p${it.variation}-${it.load}" }
                val loads = ex.loads ?: return@joinToString head
                head + ":" + loads.joinToString("-")
            }
    }
}
