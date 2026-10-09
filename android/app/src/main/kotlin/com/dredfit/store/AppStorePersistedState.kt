//
//  What the store reads from and writes to its one JSON file, and the four
//  persisted fields as the one value `update` hands a change.
//  Port of ios/Dredfit/AppStore+PersistedState.swift.
//

package com.dredfit.store

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.EngineStateDecodingException
import com.dredfit.core.SwiftDecodingException
import com.dredfit.core.SwiftJson
import com.dredfit.core.migrateFromV2
import com.dredfit.journal.V2EngineState
import com.dredfit.journal.WorkoutRecord
import com.dredfit.journal.WorkoutSnapshot
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/**
 * The file's four fields plus what THIS decode found — the flags are never
 * written: the loader turns them into a quarantine or a notice, and an import
 * into a refusal.
 */
class AppData(
    val engineState: EngineState,
    val records: List<WorkoutRecord>,
    val settings: AppSettings?,
    val pendingWorkout: WorkoutSnapshot? = null,
) {
    /** How many journal entries failed to decode. */
    var droppedRecordCount: Int = 0
        private set

    /** The engine state on disk was neither v3 nor v2, and the engine started clean. */
    var engineStateReset: Boolean = false
        private set

    /** A settings block was present but not an object this build can read. */
    var settingsUnreadable: Boolean = false
        private set

    /** A state written before v3 was read and carried over. */
    var engineStateMigrated: Boolean = false
        private set

    /** Swift's synthesized `Encodable` over the four `CodingKeys`. */
    fun toJson(): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "engineState" to engineState.toJson(),
            "records" to JsonArray(records.map { it.toJson() }),
        )
        settings?.let { out["settings"] = it.toJson() }
        pendingWorkout?.let { out["pendingWorkout"] = it.toJson() }
        return JsonObject(out)
    }

    fun encode(): String = toJson().toString()

    companion object {
        /**
         * Swift's `init(from:)`. Throws — the whole file is undecodable — only
         * when the text is not JSON, the root is not an object, or `records`
         * is not an array. Everything else degrades one piece at a time: the
         * journal record by record, the engine state through the v2 reader to
         * a clean start, the settings to their defaults, the snapshot to
         * "nothing to resume".
         */
        fun decode(text: String): AppData {
            val root = SwiftJson.parse(text)
            val c = root as? JsonObject ?: throw SwiftDecodingException("root: not an object")
            val records = c["records"] as? JsonArray ?: throw SwiftDecodingException("records: not an array")

            var migrated = false
            var reset = false
            val state = c["engineState"]?.let { readV3(it) } ?: run {
                // A state written before v3 is READ and carried over, never
                // thrown away: an upgrade must not start anyone over.
                val carried = c["engineState"]?.let { readV2(it) }?.let { Engine.migrateFromV2(it.asEngineInput) }
                if (carried != null) migrated = true else reset = true
                carried ?: EngineState.initial
            }

            val settingsElement = c["settings"]
            val settings = if (settingsElement == null || settingsElement is JsonNull) null else try {
                AppSettings.fromJson(settingsElement)
            } catch (_: SwiftDecodingException) {
                null
            }

            val pending = c["pendingWorkout"]?.takeIf { it !is JsonNull }?.let {
                try {
                    WorkoutSnapshot.fromJson(it)
                } catch (_: SwiftDecodingException) {
                    null
                }
            }

            var dropped = 0
            val decoded = records.mapNotNull {
                try {
                    WorkoutRecord.fromJson(it)
                } catch (_: SwiftDecodingException) {
                    dropped += 1
                    null
                }
            }

            return AppData(state, decoded, settings, pending).also {
                it.droppedRecordCount = dropped
                it.engineStateReset = reset
                it.engineStateMigrated = migrated
                it.settingsUnreadable = settings == null && settingsElement != null && settingsElement !is JsonNull
            }
        }

        private fun readV3(e: JsonElement): EngineState? =
            try {
                EngineState.fromJson(e)
            } catch (_: EngineStateDecodingException) {
                null
            }

        private fun readV2(e: JsonElement): V2EngineState? =
            try {
                V2EngineState.fromJson(e)
            } catch (_: SwiftDecodingException) {
                null
            }
    }
}

/** The four things the store persists, as one value a change is made to —
 *  see `AppStore.update`. */
data class PersistedState(
    val engineState: EngineState,
    val records: List<WorkoutRecord>,
    val settings: AppSettings,
    val pendingWorkout: WorkoutSnapshot?,
) {
    /**
     * Legacy high-water mark → per-record flags, only on a journal that
     * carries no flags at all: once any record is flagged, the flags are the
     * source of truth, and re-applying the mark could stamp workouts it was
     * never about (issue #103).
     */
    fun migratingHealthMarkToFlags(): PersistedState {
        val mark = settings.healthExportedThrough
        if (mark <= 0 || records.any { it.healthExported != null }) return this
        return copy(records = records.map {
            if (it.sessionNumber <= mark) it.copy(healthExported = true) else it
        })
    }
}
