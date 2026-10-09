//
//  The user's own choices, stored beside the engine state and the journal
//  in the same file. Port of ios/Dredfit/AppSettings.swift — the field docs
//  and the reasons for every default are there.
//
//  Decoding is field-by-field tolerant: every key is read under `try?`, so a
//  value of a shape this build does not know costs THAT field its default,
//  never the settings block — and never makes an import refuse the file.
//

package com.dredfit.store

import com.dredfit.core.EngineState
import com.dredfit.core.EngineStateDecodingException
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SwiftDecodingException
import com.dredfit.core.SwiftJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

data class AppSettings(
    /**
     * Calendar weekday numbers as iOS stores them — 1 = Sunday … 7 = Saturday
     * (`Calendar.component(.weekday)`), NOT java.time's 1 = Monday: the file
     * crosses platforms, and a Monday read as Sunday would move every rest
     * day. `AppStore.swiftWeekday` is the one conversion. Mon/Wed/Fri — four
     * workouts a week, spread 1-2-2-2 — on a fresh install only.
     */
    val restWeekdays: Set<Int> = setOf(2, 4, 6),
    val soundsEnabled: Boolean = true,
    val reminderEnabled: Boolean = false,
    val reminderHour: Int = 9,
    val reminderMinute: Int = 0,
    val healthEnabled: Boolean = false,
    /** High-water sessionNumber already in Health — legacy, kept written. */
    val healthExportedThrough: Int = 0,
    /** Always kilograms; absent means absent, no default stands in. */
    val bodyMassKg: Double? = null,
    val bodyMassFromHealth: Boolean = false,
    val bodyMassDate: Instant? = null,
    /** The wire key in every saved file; the label on screen names the effect. */
    val watchRecordsWorkouts: Boolean = false,
    val onboardingCompleted: Boolean = false,
    val careAcknowledgedAt: Instant? = null,
    val lastReviewRequestAt: Instant? = null,
    /** A date rather than a bool so it expires by itself after the next workout. */
    val comebackDecidedFor: Instant? = null,
    val weakLinkPromptAnsweredFor: Int? = null,
    val silentDecayAppliedFor: Instant? = null,
    val migrationNoticePending: Boolean? = null,
    val hasOpenedTechnique: Boolean = false,
    val hasReportedOwnNumber: Boolean = false,
    val hiddenBlockMoveIDs: Set<String> = emptySet(),
    val playsTonesInSilentMode: Boolean = false,
    val appearance: AppearanceChoice = AppearanceChoice.system,
    val comebackDecidedAtGap: Int? = null,
    val planMoves: PlanMoves? = null,
    val ratingMoves: PlanMoves? = null,
    val lastRatingUndo: RatingUndo? = null,
) {
    /** Swift's synthesized `Encodable` over its `CodingKeys`: every
     *  non-optional field, and the optional ones only when set. */
    fun toJson(): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "restWeekdays" to SwiftJson.encodeInts(restWeekdays.sorted()),
            "soundsEnabled" to JsonPrimitive(soundsEnabled),
            "reminderEnabled" to JsonPrimitive(reminderEnabled),
            "reminderHour" to JsonPrimitive(reminderHour),
            "reminderMinute" to JsonPrimitive(reminderMinute),
            "healthEnabled" to JsonPrimitive(healthEnabled),
            "healthExportedThrough" to JsonPrimitive(healthExportedThrough),
        )
        bodyMassKg?.let { out["bodyMassKg"] = JsonPrimitive(it) }
        out["watchRecordsWorkouts"] = JsonPrimitive(watchRecordsWorkouts)
        out["bodyMassFromHealth"] = JsonPrimitive(bodyMassFromHealth)
        bodyMassDate?.let { out["bodyMassDate"] = SwiftJson.date(it) }
        out["onboardingCompleted"] = JsonPrimitive(onboardingCompleted)
        careAcknowledgedAt?.let { out["careAcknowledgedAt"] = SwiftJson.date(it) }
        lastReviewRequestAt?.let { out["lastReviewRequestAt"] = SwiftJson.date(it) }
        comebackDecidedFor?.let { out["comebackDecidedFor"] = SwiftJson.date(it) }
        weakLinkPromptAnsweredFor?.let { out["weakLinkPromptAnsweredFor"] = JsonPrimitive(it) }
        silentDecayAppliedFor?.let { out["silentDecayAppliedFor"] = SwiftJson.date(it) }
        migrationNoticePending?.let { out["migrationNoticePending"] = JsonPrimitive(it) }
        out["hasOpenedTechnique"] = JsonPrimitive(hasOpenedTechnique)
        out["hasReportedOwnNumber"] = JsonPrimitive(hasReportedOwnNumber)
        out["hiddenBlockMoveIDs"] = JsonArray(hiddenBlockMoveIDs.sorted().map { JsonPrimitive(it) })
        out["playsTonesInSilentMode"] = JsonPrimitive(playsTonesInSilentMode)
        out["appearance"] = JsonPrimitive(appearance.name)
        comebackDecidedAtGap?.let { out["comebackDecidedAtGap"] = JsonPrimitive(it) }
        planMoves?.let { out["planMoves"] = it.toJson() }
        ratingMoves?.let { out["ratingMoves"] = it.toJson() }
        lastRatingUndo?.let { out["lastRatingUndo"] = it.toJson() }
        return JsonObject(out)
    }

    companion object {
        /** Throws only when the block is not an object at all — the one case
         *  that costs the whole block its defaults (and refuses an import). */
        fun fromJson(e: JsonElement): AppSettings {
            val c = e as? JsonObject ?: throw SwiftDecodingException("settings: not an object")
            fun bool(key: String, default: Boolean) = SwiftJson.lenient(c, key, SwiftJson::bool) ?: default
            fun date(key: String) = SwiftJson.lenient(c, key, SwiftJson::date)
            val bodyMassKg = SwiftJson.lenient(c, "bodyMassKg", SwiftJson::double)
            return AppSettings(
                // [1], not the fresh-install default: an upgrade must not add
                // a rest day the person never chose (issue #36).
                restWeekdays = (SwiftJson.lenient(c, "restWeekdays", SwiftJson::intList)?.toSet() ?: setOf(1))
                    .filter { it in 1..7 }.toSet(),
                soundsEnabled = bool("soundsEnabled", true),
                reminderEnabled = bool("reminderEnabled", false),
                // Held to the clock: a backup is a JSON a person can edit.
                reminderHour = (SwiftJson.lenient(c, "reminderHour", SwiftJson::int) ?: 9).coerceIn(0, 23),
                reminderMinute = (SwiftJson.lenient(c, "reminderMinute", SwiftJson::int) ?: 0).coerceIn(0, 59),
                healthEnabled = bool("healthEnabled", false),
                healthExportedThrough = SwiftJson.lenient(c, "healthExportedThrough", SwiftJson::int) ?: 0,
                bodyMassKg = bodyMassKg,
                // Never true, and never dated, without a weight to be true about.
                bodyMassFromHealth = bool("bodyMassFromHealth", false) && bodyMassKg != null,
                bodyMassDate = if (bodyMassKg == null) null else date("bodyMassDate"),
                watchRecordsWorkouts = bool("watchRecordsWorkouts", false),
                onboardingCompleted = bool("onboardingCompleted", false),
                careAcknowledgedAt = date("careAcknowledgedAt"),
                lastReviewRequestAt = date("lastReviewRequestAt"),
                comebackDecidedFor = date("comebackDecidedFor"),
                weakLinkPromptAnsweredFor = SwiftJson.lenient(c, "weakLinkPromptAnsweredFor", SwiftJson::int),
                silentDecayAppliedFor = date("silentDecayAppliedFor"),
                migrationNoticePending = SwiftJson.lenient(c, "migrationNoticePending", SwiftJson::bool),
                hasOpenedTechnique = bool("hasOpenedTechnique", false),
                hasReportedOwnNumber = bool("hasReportedOwnNumber", false),
                hiddenBlockMoveIDs = SwiftJson.lenient(c, "hiddenBlockMoveIDs", SwiftJson::stringList)?.toSet()
                    ?: emptySet(),
                playsTonesInSilentMode = bool("playsTonesInSilentMode", false),
                // A fourth appearance choice from a newer build opens on the
                // system theme rather than costing the block.
                appearance = SwiftJson.lenient(c, "appearance") { j ->
                    SwiftJson.string(j)?.let { raw -> AppearanceChoice.entries.firstOrNull { it.name == raw } }
                } ?: AppearanceChoice.system,
                comebackDecidedAtGap = SwiftJson.lenient(c, "comebackDecidedAtGap", SwiftJson::int),
                planMoves = lenientObject(c, "planMoves", PlanMoves::fromJson),
                ratingMoves = lenientObject(c, "ratingMoves", PlanMoves::fromJson),
                lastRatingUndo = lenientObject(c, "lastRatingUndo", RatingUndo::fromJson))
        }

        /** `try? decodeIfPresent` of a nested type whose reader throws. */
        private fun <T> lenientObject(c: JsonObject, key: String, read: (JsonElement) -> T): T? =
            try {
                SwiftJson.optional(c, key, read)
            } catch (_: SwiftDecodingException) {
                null
            }
    }
}

/** The theme the app runs in. The raw value is the case name, as on iOS. */
@Suppress("EnumEntryName")
enum class AppearanceChoice { system, light, dark }

/**
 * Why the plan stands where it does, remembered at the moment it moved —
 * the journal cannot be asked afterwards. TWO slots hold this shape, one
 * session apart: `planMoves` for the plan ahead, `ratingMoves` for the
 * workout just rated.
 */
data class PlanMoves(
    val session: Int,
    val byHand: List<Pattern> = emptyList(),
    val byRating: List<Pattern> = emptyList(),
) {
    fun toJson(): JsonObject = JsonObject(linkedMapOf(
        "session" to JsonPrimitive(session),
        "byHand" to SwiftJson.encodePatterns(byHand),
        "byRating" to SwiftJson.encodePatterns(byRating),
    ))

    companion object {
        /** Synthesized: all three keys required — Swift ignores the defaults
         *  when it decodes. */
        fun fromJson(e: JsonElement): PlanMoves {
            val c = e as? JsonObject ?: throw SwiftDecodingException("planMoves: not an object")
            return PlanMoves(
                session = SwiftJson.required(c, "session", SwiftJson::int),
                byHand = SwiftJson.required(c, "byHand", SwiftJson::patternList),
                byRating = SwiftJson.required(c, "byRating", SwiftJson::patternList))
        }
    }
}

/** What it takes to un-apply the last rating and apply another one. */
data class RatingUndo(val state: EngineState, val session: Session) {
    fun toJson(): JsonObject = JsonObject(linkedMapOf(
        "state" to state.toJson(),
        "session" to session.toJson(),
    ))

    companion object {
        fun fromJson(e: JsonElement): RatingUndo {
            val c = e as? JsonObject ?: throw SwiftDecodingException("lastRatingUndo: not an object")
            val state = c["state"] ?: throw SwiftDecodingException("state: missing")
            return RatingUndo(
                state = try {
                    EngineState.fromJson(state)
                } catch (err: EngineStateDecodingException) {
                    throw SwiftDecodingException("state: ${err.message}")
                },
                session = SwiftJson.required(c, "session", Session::fromJson))
        }
    }
}
