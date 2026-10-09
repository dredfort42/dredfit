//
//  What Swift's synthesized `Codable` and its `JSONDecoder`/`JSONEncoder` do
//  with the primitive types, stated once for every persisted type on this
//  side. There is no Swift file of this name: on iOS the rules are the
//  standard library's, and here they have to be written down — the backup is
//  the bridge between the two ports, and a reader more lenient or more strict
//  than Swift's would turn the same file into a different history.
//
//  Three readings of a keyed field, after Swift's three spellings:
//  `required` is `c.decode` (absent, null or a wrong type throws),
//  `optional` is `c.decodeIfPresent` (absent or null is nil, a wrong type
//  throws), `lenient` is `try? c.decodeIfPresent` (anything wrong is nil).
//

package com.dredfit.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.time.Instant
import kotlin.math.floor

/** Swift's `DecodingError`: a value of a shape the type cannot be read from. */
class SwiftDecodingException(message: String) : Exception(message)

object SwiftJson {

    // MARK: - Primitives

    /**
     * A JSON number as Swift's `JSONDecoder` reads it into `Int`: any
     * integral value that fits 64 bits (`1.0` and `1e2` included), never a
     * string or a bool. Swift's Int is 64-bit; a value past 32 bits is held
     * at the edge of Kotlin's Int — every reader clamps far inside it, so the
     * result is the one Swift computes.
     */
    fun int(e: JsonElement?): Int? {
        val p = number(e) ?: return null
        val exact = p.content.toLongOrNull() ?: try {
            BigDecimal(p.content).let { d ->
                if (d.stripTrailingZeros().scale() > 0) return null
                d.longValueExact()
            }
        } catch (_: ArithmeticException) {
            return null
        } catch (_: NumberFormatException) {
            return null
        }
        return saturated(exact)
    }

    /** Swift's `Double`: any finite JSON number, an integer included. */
    fun double(e: JsonElement?): Double? =
        number(e)?.content?.toDoubleOrNull()?.takeIf { it.isFinite() }

    fun bool(e: JsonElement?): Boolean? {
        val p = e as? JsonPrimitive ?: return null
        if (p is JsonNull || p.isString) return null
        return when (p.content) {
            "true" -> true
            "false" -> false
            else -> null
        }
    }

    fun string(e: JsonElement?): String? =
        (e as? JsonPrimitive)?.takeIf { it.isString }?.content

    fun saturated(v: Long): Int = v.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()

    private fun number(e: JsonElement?): JsonPrimitive? {
        val p = e as? JsonPrimitive ?: return null
        if (p is JsonNull || p.isString || p.content == "true" || p.content == "false") return null
        return p
    }

    // MARK: - Date

    /** Swift's reference date, 2001-01-01T00:00:00Z, in Unix seconds. */
    private const val REFERENCE_EPOCH_SECOND = 978_307_200L

    /** 0001-01-01T00:00:00Z and 9999-12-31T23:59:59Z, since the reference date. */
    private const val DATE_MIN = -62_135_596_800.0 - REFERENCE_EPOCH_SECOND
    private const val DATE_MAX = 253_402_300_799.0 - REFERENCE_EPOCH_SECOND

    /**
     * Swift's default date strategy (`.deferredToDate`): a `Date` is its
     * `timeIntervalSinceReferenceDate`, a Double. Every date in an iOS file
     * is one, so this side writes the same — an ISO string would be a file
     * iOS refuses. Nanoseconds are finer than a Double's step at today's
     * magnitude, so a date read here and written back is the same Double.
     */
    fun date(e: JsonElement?): Instant? {
        // Swift's Date takes any Double; java.time throws past its range, and
        // a calendar throws well inside it. A hand-edited date is held to
        // the years 1…9999, which no real record leaves.
        val seconds = (double(e) ?: return null).coerceIn(DATE_MIN, DATE_MAX)
        val whole = floor(seconds)
        // `ofEpochSecond` carries a rounded-up 1e9 into the seconds itself.
        val nanos = Math.round((seconds - whole) * 1e9)
        return Instant.ofEpochSecond(REFERENCE_EPOCH_SECOND + whole.toLong(), nanos)
    }

    fun date(instant: Instant): JsonPrimitive = JsonPrimitive(sinceReference(instant))

    /**
     * The instant a Swift `Date` can hold — a Double of seconds, coarser than
     * a nanosecond at today's magnitude. Every date the app STORES goes
     * through this when it is made, so a record in memory and the same record
     * read back from a file are equal: identity (`WorkoutRecord.id`) and an
     * import's lineage check compare them.
     */
    fun swiftDate(instant: Instant): Instant = date(date(instant)) ?: instant

    /** `timeIntervalSinceReferenceDate`. */
    fun sinceReference(instant: Instant): Double =
        (instant.epochSecond - REFERENCE_EPOCH_SECOND).toDouble() + instant.nano / 1e9

    // MARK: - Keyed fields

    /** `c.decode(T.self, forKey:)`. */
    fun <T> required(c: JsonObject, key: String, read: (JsonElement) -> T?): T {
        val e = c[key]
        if (e == null || e is JsonNull) throw SwiftDecodingException("$key: missing")
        return read(e) ?: throw SwiftDecodingException("$key: wrong type")
    }

    /** `c.decodeIfPresent(T.self, forKey:)`. */
    fun <T> optional(c: JsonObject, key: String, read: (JsonElement) -> T?): T? {
        val e = c[key]
        if (e == null || e is JsonNull) return null
        return read(e) ?: throw SwiftDecodingException("$key: wrong type")
    }

    /** `try? c.decodeIfPresent(T.self, forKey:)`. */
    fun <T> lenient(c: JsonObject, key: String, read: (JsonElement) -> T?): T? =
        try {
            optional(c, key, read)
        } catch (_: SwiftDecodingException) {
            null
        }

    // MARK: - Collections, the way Swift synthesizes them

    /**
     * A `[Pattern: V]` with Swift's own decoding: an UNKEYED array alternating
     * [rawValue, value, ...] (`Pattern` is not `CodingKeyRepresentable`). An
     * unknown raw value, an odd length or a malformed value THROWS, as the
     * standard library does — the engine state reads its maps more leniently
     * on purpose (EngineState.kt); a journal record does not.
     */
    fun <V> patternMap(e: JsonElement, value: (JsonElement) -> V?): Map<Pattern, V> {
        val array = e as? JsonArray ?: throw SwiftDecodingException("not an array")
        if (array.size % 2 != 0) throw SwiftDecodingException("odd-length map")
        val out = LinkedHashMap<Pattern, V>()
        for (i in array.indices step 2) {
            val key = pattern(array[i]) ?: throw SwiftDecodingException("unknown pattern ${array[i]}")
            out[key] = value(array[i + 1]) ?: throw SwiftDecodingException("malformed value for $key")
        }
        return out
    }

    /** `Pattern(rawValue:)` through its `Decodable`: null for anything unknown. */
    fun pattern(e: JsonElement): Pattern? = string(e)?.let { Pattern.fromRaw(it) }

    /** A `Set<Pattern>` or `[Pattern]`: an array of raw values, every one known. */
    fun patternList(e: JsonElement): List<Pattern>? {
        val array = e as? JsonArray ?: return null
        return array.map { pattern(it) ?: return null }
    }

    fun intList(e: JsonElement): List<Int>? {
        val array = e as? JsonArray ?: return null
        return array.map { int(it) ?: return null }
    }

    fun stringList(e: JsonElement): List<String>? {
        val array = e as? JsonArray ?: return null
        return array.map { string(it) ?: return null }
    }

    /** A `[Int: V]`: Swift special-cases integer keys into a keyed object whose
     *  keys are the decimal strings, read back with `Int(String)`. */
    fun <V> intKeyedMap(e: JsonElement, value: (JsonElement) -> V?): Map<Int, V>? {
        val obj = e as? JsonObject ?: return null
        val out = LinkedHashMap<Int, V>()
        for ((key, v) in obj) {
            val k = key.toLongOrNull() ?: return null
            out[saturated(k)] = value(v) ?: return null
        }
        return out
    }

    /** Encoded in `Pattern.allCases` order: Swift's order is a hash order, so
     *  any order reads back the same — this one keeps a file stable. */
    fun <V> encodePatternMap(map: Map<Pattern, V>, value: (V) -> JsonElement): JsonArray =
        JsonArray(map.entries.sortedBy { it.key.ordinal }
            .flatMap { listOf(JsonPrimitive(it.key.rawValue), value(it.value)) })

    fun encodePatternMap(map: Map<Pattern, Int>): JsonArray = encodePatternMap(map) { JsonPrimitive(it) }

    fun encodePatterns(patterns: Collection<Pattern>): JsonArray =
        JsonArray(patterns.map { JsonPrimitive(it.rawValue) })

    fun encodePatternSet(set: Set<Pattern>): JsonArray = encodePatterns(set.sortedBy { it.ordinal })

    fun encodeInts(values: Collection<Int>): JsonArray = JsonArray(values.map { JsonPrimitive(it) })

    fun <V> encodeIntKeyedMap(map: Map<Int, V>, value: (V) -> JsonElement): JsonObject =
        JsonObject(map.entries.sortedBy { it.key }.associateTo(LinkedHashMap()) { it.key.toString() to value(it.value) })
}
