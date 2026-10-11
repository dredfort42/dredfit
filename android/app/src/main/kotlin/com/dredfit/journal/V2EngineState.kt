//
//  The shape of an engine state written before v3, and nothing more — read,
//  never written. Port of ios/Dredfit/V2EngineState.swift. An iOS backup taken
//  by a v2 build is the one place an Android install can meet this shape.
//

package com.dredfit.journal

import com.dredfit.core.Pattern
import com.dredfit.core.SwiftDecodingException
import com.dredfit.core.SwiftJson
import com.dredfit.core.V2State
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

data class V2EngineState(
    val counter: Int = 0,
    val hasBar: Boolean = false,
    val levels: Map<Pattern, Int> = emptyMap(),
    val failStreak: Map<Pattern, Int> = emptyMap(),
) {
    val asEngineInput: V2State
        get() = V2State(counter = counter, hasBar = hasBar, levels = levels, failStreak = failStreak)

    companion object {
        /**
         * `levels` is what makes a state v2: without it (or with none legible)
         * this throws, which is how the caller learns the file is not v2.
         * Every other field falls back to its default under `try?`.
         */
        fun fromJson(e: JsonElement): V2EngineState {
            val c = e as? JsonObject ?: throw SwiftDecodingException("v2 state: not an object")
            val levels = patternMap(c, "levels")
            if (levels.isEmpty()) throw SwiftDecodingException("not a v2 state")
            return V2EngineState(
                counter = SwiftJson.lenient(c, "counter", SwiftJson::int) ?: 0,
                hasBar = SwiftJson.lenient(c, "hasBar", SwiftJson::bool) ?: false,
                levels = levels,
                failStreak = try {
                    patternMap(c, "failStreak")
                } catch (_: SwiftDecodingException) {
                    emptyMap()
                })
        }

        /**
         * v2's own reader, not the standard one: walks the [rawValue, count]
         * pairs and stops at the first that does not read — an odd length is
         * simply the end of what is legible — and skips an unknown pattern.
         * Absent reads empty; present but not an array throws.
         */
        private fun patternMap(c: JsonObject, key: String): Map<Pattern, Int> {
            val e = c[key] ?: return emptyMap()
            val array = e as? JsonArray ?: throw SwiftDecodingException("$key: not an array")
            val out = LinkedHashMap<Pattern, Int>()
            var i = 0
            while (i + 1 < array.size) {
                val raw = SwiftJson.string(array[i]) ?: break
                val value = SwiftJson.int(array[i + 1]) ?: break
                Pattern.fromRaw(raw)?.let { out[it] = value }
                i += 2
            }
            return out
        }
    }
}
