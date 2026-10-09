//
//  The bridge between the two ports: a backup exported on iOS imports here
//  with the same state, and one exported here reads on iOS. No Swift file of
//  this name — on iOS the one format is the only format.
//
//  The fixtures were written by Swift itself — android/tools/swift-backup-probe,
//  which compiles the app's own Journal.swift, AppSettings.swift,
//  AppStore+PersistedState.swift and V2EngineState.swift (linked, not copied)
//  over DredfitCore; its regenerate.sh rewrites every file below:
//  - ios/ios-backup.json: `JSONEncoder().encode(AppData(engineState:records:
//    settings:))` exactly as `exportURL` writes it — six workouts run through
//    the engine, every optional record field and every settings key set at
//    least once;
//  - ios/ios-backup.swift-decoded.json: what Swift reads back out of it,
//    re-encoded with sorted keys, plus its decode flags;
//  - ios/ios-state-pending.json: the same with a `pendingWorkout` carrying
//    every snapshot field — the state file's shape — and
//    ios-state-pending.swift-roundtrip.json, Swift's decode → encode of it.
//
//  The reverse direction is checked against the same probe: the Android
//  export this suite writes to build/cross-platform/android-backup.json
//  decodes there with no flag raised (the probe's README has the command).
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.Pattern
import com.dredfit.store.AppData
import com.dredfit.store.StateFile
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import com.dredfit.store.totalProgress
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.nio.file.Files
import java.nio.file.Paths
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CrossPlatformBackupTest : AppStoreTestCase() {

    private fun resource(name: String): String =
        assertNotNull(javaClass.getResource("/ios/$name"), name).readText()

    @Test
    fun anIosBackupDecodesHereExactlyAsSwiftReadsIt() {
        val data = AppData.decode(resource("ios-backup.json"))
        val swift = Json.parseToJsonElement(resource("ios-backup.swift-decoded.json")) as JsonObject

        assertFalse(data.engineStateReset)
        assertFalse(data.settingsUnreadable)
        assertFalse(data.engineStateMigrated)
        assertEquals(0, data.droppedRecordCount)
        assertEquals(6, data.records.size)
        assertEquals(6, data.engineState.counter)
        assertEquals(swift["totalProgress"].toString().toInt(), Engine.totalProgress(data.engineState))

        assertEquals(normal(swift.getValue("engineState")), normal(data.engineState.toJson()))
        assertEquals(normal(swift.getValue("settings")), normal(assertNotNull(data.settings).toJson()))
        assertEquals(normal(swift.getValue("records")), normal(JsonArray(data.records.map { it.toJson() })))
    }

    /** The fixture is only worth its claim if it carries every field. */
    @Test
    fun theIosBackupExercisesEveryOptionalField() {
        val data = AppData.decode(resource("ios-backup.json"))
        val keys = data.records.flatMap { it.toJson().keys }.toSet()
        for (key in listOf("totalProgressAfter", "exercises", "heldBack", "actuals", "setActuals", "probes",
                           "setsSkipped", "skippedSetIndices", "skippedWithNumberIndices", "skipped",
                           "discomfort", "positionsAfter", "durationSec", "warmupSec", "cooldownSec",
                           "healthExported", "interrupted", "raisedSteps", "raisedLanded")) {
            assertTrue(key in keys, key)
        }
        val settings = assertNotNull(data.settings)
        assertNotNull(settings.lastRatingUndo)
        assertNotNull(settings.planMoves)
        assertNotNull(settings.ratingMoves)
        assertNotNull(settings.bodyMassDate)
    }

    @Test
    fun anIosStateFileWithAWorkoutInProgressRoundTripsAsSwiftDoes() {
        val data = AppData.decode(resource("ios-state-pending.json"))
        val pending = assertNotNull(data.pendingWorkout, "the snapshot must survive the decode")
        assertNotNull(pending.holdMeasuredSec)
        assertNotNull(pending.restEndDate)
        val swiftRoundTrip = Json.parseToJsonElement(resource("ios-state-pending.swift-roundtrip.json"))
        assertEquals(normal(swiftRoundTrip), normal(data.toJson()))
    }

    /** Import on Android lands on exactly the state iOS exported, and the
     *  device-local facts are reset the way an iOS restore resets them. */
    @Test
    fun anIosBackupImportsWithTheSameState() {
        val bytes = resource("ios-backup.json").toByteArray()
        val expected = AppData.decode(String(bytes))
        val store = makeStore()
        store.importBackup(bytes)

        assertEquals(expected.engineState, store.engineState)
        assertEquals(expected.records, store.records)
        assertNull(store.pendingWorkout)
        val settings = assertNotNull(expected.settings)
        // Whose weight it is, is a fact about THIS device.
        assertEquals(settings.copy(bodyMassFromHealth = false), store.settings)
        assertEquals(38, store.totalProgress)

        // And it is what the next launch reads.
        val reloaded = makeStore()
        assertEquals(store.engineState, reloaded.engineState)
        assertEquals(store.records, reloaded.records)
        assertEquals(store.settings, reloaded.settings)
    }

    /** What Android exports reads back here in full; the same file is the
     *  one the Swift probe decodes (written to build/ for it). */
    @Test
    fun anAndroidExportReadsBackInFull() {
        val store = makeStore()
        store.importBackup(resource("ios-backup.json").toByteArray())
        val exported = store.exportBackup()

        val out = Paths.get("build", "cross-platform", "android-backup.json")
        Files.createDirectories(out.parent)
        Files.write(out, exported)

        val back = AppData.decode(String(exported))
        assertFalse(back.engineStateReset || back.settingsUnreadable || back.engineStateMigrated)
        assertEquals(0, back.droppedRecordCount)
        assertNull(back.pendingWorkout, "a backup never carries the workout in progress")
        assertEquals(store.engineState, back.engineState)
        assertEquals(store.records, back.records)
        assertEquals(store.settings, back.settings)
    }

    /** The state file this side writes is the iOS shape too: a store that
     *  read an iOS file writes one that reads back the same. */
    @Test
    fun theStateFileWrittenHereReadsBackTheSame() {
        Files.writeString(tempPath, resource("ios-state-pending.json"))
        val store = makeStore()
        assertNotNull(store.pendingWorkout)
        store.update { it }   // one write through the one path

        val read = StateFile(tempPath).read(reload = false)
        val loaded = assertIs<StateFile.Read.Loaded>(read).data
        assertEquals(store.engineState, loaded.engineState)
        assertEquals(store.records, loaded.records)
        assertEquals(store.settings, loaded.settings)
        assertEquals(store.pendingWorkout, loaded.pendingWorkout)
    }

    /**
     * Shape, not bytes: Swift's key order and the order of its sets and
     * `[Pattern: X]` arrays are hash orders that change from run to run, and
     * it prints `24` where Kotlin prints `24.0`. An alternating
     * [pattern, value, …] array becomes a map; an array of strings (a set of
     * patterns or ids) and `restWeekdays` are compared as sets.
     */
    private fun normal(e: JsonElement, key: String? = null): Any? = when (e) {
        is JsonObject -> e.mapValues { normal(it.value, it.key) }
        is JsonArray -> when {
            isPatternMap(e) -> (e.indices step 2).associate {
                (e[it] as JsonPrimitive).content to normal(e[it + 1])
            }
            e.all { it is JsonPrimitive && it.isString } -> e.map { (it as JsonPrimitive).content }.sorted()
            key == "restWeekdays" -> e.map { normal(it) as BigDecimal }.sorted()
            else -> e.map { normal(it) }
        }
        is JsonNull -> null
        is JsonPrimitive -> if (e.isString) e.content
            else e.content.toBooleanStrictOrNull() ?: BigDecimal(e.content).stripTrailingZeros()
    }

    private fun isPatternMap(a: JsonArray): Boolean =
        a.isNotEmpty() && a.size % 2 == 0 && (a.indices step 2).all {
            val k = a[it]
            k is JsonPrimitive && k.isString && Pattern.fromRaw(k.content) != null &&
                !(a[it + 1] is JsonPrimitive && (a[it + 1] as JsonPrimitive).isString)
        }
}
