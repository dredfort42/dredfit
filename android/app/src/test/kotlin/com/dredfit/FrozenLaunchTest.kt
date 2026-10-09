//
//  Port of ios/DredfitTests/FrozenLaunchTests.swift: the frozen launch meeting
//  a state written before v3. A launch that cannot READ its state file
//  degrades to an empty state and waits for `reloadIfNeeded()`; the rule here
//  lives in `AppStore.adopt`, the one path a launch and a reload share — a
//  frozen launch is exactly the one that must not swallow the migration
//  announcement, the ONLY thing that explains the new shape to an upgrading
//  trainee.
//

package com.dredfit

import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppData
import com.dredfit.store.AppSettings
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.canStartWorkout
import com.dredfit.store.retryPersist
import com.dredfit.store.setSounds
import com.dredfit.store.showsMigrationNotice
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.name
import kotlin.io.path.readBytes
import kotlin.io.path.writeBytes
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FrozenLaunchTest : AppStoreTestCase() {

    @BeforeEach
    fun onlyWherePermissionsHold() = assumeNotRoot()

    @AfterEach
    fun readable() {
        if (Files.exists(tempPath)) setPermissions(tempPath, "rw-r--r--")
    }

    // MARK: - Fixtures

    /** A v2 file in the shape v2 actually wrote: `[Pattern: Int]` as an
     *  UNKEYED array. Deliberately its own copy rather than a shared helper:
     *  a shared factory is what gets "improved" into the current shape, and
     *  then no suite tests a migration any more. */
    private fun v2Payload(levels: Map<String, Int>, counter: Int, hasBar: Boolean): ByteArray {
        fun pairs(map: Map<String, Int>) =
            map.toSortedMap().entries.joinToString(",") { "\"${it.key}\",${it.value}" }
        val json = """
        {"engineState":{"counter":$counter,"hasBar":$hasBar,
          "levels":[${pairs(levels)}],
          "failStreak":[${pairs(levels.mapValues { 1 })}]},
         "records":[],"settings":null}
        """.trimIndent()
        return json.toByteArray()
    }

    private fun v3Payload(counter: Int): ByteArray =
        AppData(engineState = EngineState.initial.also { it.counter = counter }, records = emptyList(),
                settings = AppSettings(), pendingWorkout = null).encode().toByteArray()

    /** A store built over a file it cannot read, the file left unreadable.
     *  Asserts the freeze itself: a launch that quietly READ the file would
     *  make every assertion after it vacuous. */
    private fun frozenStore(over: ByteArray): AppStore {
        tempPath.writeBytes(over)
        setPermissions(tempPath, "---------")
        val store = makeStore()
        assertTrue(store.journalFrozen,
                   "the fixture must actually freeze, or this suite is testing the cold path twice")
        assertFalse(store.showsMigrationNotice, "nothing has been read yet, so there is nothing to announce yet")
        return store
    }

    private fun makeReadable() = setPermissions(tempPath, "rw-r--r--")

    // MARK: - The announcement

    @Test
    fun frozenLaunch_reloadingAV2StateOnceReadable_stillAnnouncesTheMigration() {
        val store = frozenStore(over = v2Payload(mapOf("squat" to 20, "pull" to 8), counter = 37, hasBar = true))

        makeReadable()
        store.reloadIfNeeded()

        assertFalse(store.journalFrozen, "the reload must lift the freeze it was written for")
        assertEquals(37, store.engineState.counter,
                     "the v2 state must actually have been carried over, or the flag below means nothing")
        assertTrue(store.showsMigrationNotice,
                   "a frozen launch is exactly the launch that must not swallow the announcement")
    }

    @Test
    fun frozenLaunch_reloadingAV3StateOnceReadable_announcesNothing() {
        val store = frozenStore(over = v3Payload(counter = 5))

        makeReadable()
        store.reloadIfNeeded()

        assertEquals(5, store.engineState.counter, "the v3 state loads on the reload as it always did")
        assertFalse(store.showsMigrationNotice,
                    "nothing migrated, so nobody is told anything — without this the test above would " +
                        "pass just as well against a flag that is always true")
    }

    @Test
    fun frozenLaunch_thatWasAlreadyUsed_defersTheAnnouncementInsteadOfSpendingIt() {
        val payload = v2Payload(mapOf("squat" to 20, "pull" to 8), counter = 37, hasBar = true)
        val store = frozenStore(over = payload)
        store.setSounds(false)   // any mutation — from here the launch owns state of its own

        makeReadable()
        store.reloadIfNeeded()

        assertTrue(store.journalFrozen,
                   "a used launch stays frozen: reloading over work already done erases it silently")
        assertFalse(store.showsMigrationNotice, "and it announces nothing, because it has still not read the v2 state")
        assertContentEquals(payload, tempPath.readBytes(),
                            "the v2 file itself must be untouched — that is what carries the announcement on")
        assertTrue(makeStore().showsMigrationNotice, "so the very next launch announces it: deferred, never spent")
    }

    // MARK: - Starting a workout

    @Test
    fun frozenLaunch_cannotStartAWorkout_andRetryingTheReadLiftsThat() {
        val store = frozenStore(over = v3Payload(counter = 5))
        assertFalse(store.canStartWorkout,
                    "a workout done now is kept in memory only, and the person must be told instead")

        store.activate()   // what the card's Try again calls — still unreadable
        assertFalse(store.canStartWorkout, "a read that fails again changes nothing")

        makeReadable()
        store.activate()
        assertTrue(store.canStartWorkout, "the second read lifts the freeze, and Start comes back")
    }

    @Test
    fun frozenLaunch_retryingTheWrite_doesNotPinTheFreeze() {
        val store = frozenStore(over = v3Payload(counter = 5))

        store.retryPersist()
        makeReadable()
        store.reloadIfNeeded()

        assertFalse(store.journalFrozen,
                    "an empty retry is not work done on this launch — counting it would pin the freeze " +
                        "and leave only a relaunch")
        assertEquals(5, store.engineState.counter)
    }

    // MARK: - What the reload finds

    /** The copies a read put aside for this test's file. */
    private fun corruptCopies(): List<Path> =
        tempDir.listDirectoryEntries().filter { it.name.startsWith("dredfit-test.corrupt") }

    @Test
    fun frozenLaunch_reloadingAFileThatNoLongerDecodes_movesItAsideAndThaws() {
        val garbage = "not a state file".toByteArray()
        val store = frozenStore(over = garbage)

        makeReadable()
        store.reloadIfNeeded()

        assertFalse(store.journalFrozen, "a file that will never decode must not keep the launch frozen for good")
        assertFalse(Files.exists(tempPath), "moved, so the next write cannot land on the only copy")
        val copies = corruptCopies()
        assertEquals(1, copies.size)
        assertContentEquals(garbage, copies.first().readBytes())
    }

    @Test
    fun frozenLaunch_reloadingAPartlyReadableFile_keepsWhatReadsAndACopyOfTheRest() {
        val record = WorkoutRecord(sessionNumber = 1, date = Instant.ofEpochSecond(1_800_000_000),
                                   result = FeedbackResult.plan)
        val future = JsonObject(mapOf("from" to JsonPrimitive("a future build")))
        val payload = JsonObject(mapOf(
            "engineState" to future,
            "records" to JsonArray(listOf(record.toJson(), future)),
        )).toString().toByteArray()
        val store = frozenStore(over = payload)

        makeReadable()
        store.reloadIfNeeded()

        assertFalse(store.journalFrozen)
        assertEquals(1, store.records.size, "the readable entry loads on the reload")
        assertEquals(EngineState.initial, store.engineState, "a state neither shape reads starts clean")
        assertTrue(Files.exists(tempPath), "copied, not moved")
        val copies = corruptCopies()
        assertEquals(1, copies.size)
        assertContentEquals(payload, copies.first().readBytes(),
                            "the state and the dropped entry can still be recovered from the copy")
    }
}
