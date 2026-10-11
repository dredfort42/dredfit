//
//  Port of ios/DredfitTests/AppStoreTests+CorruptedStorage.swift. One shape:
//  a state file that cannot be trusted (garbage bytes, a stale permission, one
//  bad journal entry) must never cost the rest of the journal, or get silently
//  overwritten by the clean state that stood in for it.
//

package com.dredfit

import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.store.BackupError
import com.dredfit.store.exportBackup
import com.dredfit.store.nextSession
import com.dredfit.store.setSounds
import com.dredfit.store.shouldShowOnboarding
import com.dredfit.store.totalProgress
import org.junit.jupiter.api.Test
import java.nio.file.Files
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.name
import kotlin.io.path.readBytes
import kotlin.io.path.writeBytes
import kotlin.io.path.writeText
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppStoreTestCorruptedStorage : AppStoreTestCase() {

    @Test
    fun corruptedStorageFallsBackToInitial() {
        tempPath.writeText("{not a json")
        val store = makeStore()
        assertTrue(store.records.isEmpty(), "a corrupted file should give a clean start, not a crash")
        assertEquals(0, store.totalProgress)
    }

    @Test
    fun corruptedStorageIsQuarantinedNotOverwritten() {
        tempPath.writeText("{not a json")
        val store = makeStore()
        store.setSounds(false)   // any persisted mutation
        assertTrue(Files.exists(corruptPath), "the unreadable file must be kept aside")
        assertContentEquals("{not a json".toByteArray(), corruptPath.readBytes(),
                            "the quarantined copy must be the original bytes")
    }

    /** Regression: a state file that exists but cannot be read (data
     *  protection before the first unlock, a transient I/O failure) must never
     *  be overwritten by the empty state that replaced it — and must resume
     *  normal persistence once the file becomes readable again. */
    @Test
    fun unreadableStateFileFreezesPersistenceUntilReloaded() {
        assumeNotRoot()
        val seed = makeStore()
        seed.completeWorkout(session = seed.nextSession, result = FeedbackResult.plan)
        val original = tempPath.readBytes()
        setPermissions(tempPath, "---------")
        try {
            val store = makeStore()
            assertTrue(store.records.isEmpty(), "the unreadable launch degrades to empty state")
            assertFalse(store.shouldShowOnboarding, "an unread journal is not a fresh install")
            assertTrue(store.journalFrozen)
            assertFailsWith<BackupError.JournalUnavailable>("a frozen launch has nothing honest to export") {
                store.exportBackup()
            }
            store.setSounds(false)   // any mutation that would persist

            setPermissions(tempPath, "rw-r--r--")
            assertContentEquals(original, tempPath.readBytes(),
                                "the journal on disk must survive the frozen launch byte-for-byte")

            // A launch nobody touched yet takes the file the moment it can
            // read it — the prewarm-before-first-unlock case this is all for.
            setPermissions(tempPath, "---------")
            val untouched = makeStore()
            assertTrue(untouched.journalFrozen)
            setPermissions(tempPath, "rw-r--r--")
            untouched.reloadIfNeeded()
            assertEquals(1, untouched.records.size, "the journal must load once readable")
            untouched.setSounds(false)
            assertFalse(makeStore().settings.soundsEnabled, "persistence must resume after a successful reload")
        } finally {
            setPermissions(tempPath, "rw-r--r--")
        }
    }

    @Test
    fun usedFrozenLaunchIsNotReplacedByTheFileItCouldNotRead() {
        assumeNotRoot()
        val seed = makeStore()
        repeat(3) { seed.completeWorkout(session = seed.nextSession, result = FeedbackResult.plan) }
        val original = tempPath.readBytes()
        setPermissions(tempPath, "---------")
        try {
            val store = makeStore()
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
            assertEquals(1, store.records.size, "the frozen launch keeps its own work in memory")

            setPermissions(tempPath, "rw-r--r--")
            store.reloadIfNeeded()
            assertEquals(1, store.records.size, "a used launch must not be swapped mid-flight")
            assertEquals(1, store.engineState.counter, "the counter must stay where the running session expects it")
            assertContentEquals(original, tempPath.readBytes(), "and the real journal on disk stays untouched")
        } finally {
            setPermissions(tempPath, "rw-r--r--")
        }
    }

    /** One unreadable journal entry (e.g. written by a newer version) must not
     *  throw away the readable rest of the file. */
    @Test
    fun oneBadRecordDoesNotDropTheJournal() {
        val mixed = """
        {"engineState":{"counter":2,
          "levels":["squat",2,"push_h",2,"hinge",2,"pull",2,"push_v",2,"lunge",2,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[
           {"sessionNumber":1,"date":700000000,"result":"plan","totalLevelAfter":12},
           {"sessionNumber":2,"date":"not-a-date","result":"someday","totalLevelAfter":18}]}
        """.trimIndent()
        tempPath.writeText(mixed)

        val store = makeStore()
        assertEquals(1, store.records.size, "the readable record must survive")
        assertEquals(1, store.records.first().sessionNumber)
        // An upgrading trainee's work is CARRIED OVER; MigrationV2Test owns
        // what the rungs land on.
        assertTrue(store.totalProgress > Engine.totalProgress(EngineState.initial),
                   "the v2 rungs migrate, so progress is above a clean start")
        assertTrue(Files.exists(corruptPath), "the full original must be kept aside when entries are dropped")
    }

    /** After a whole-file failure the quarantined copy is the ONLY copy of the
     *  journal the app started over from — a second failure must keep it and
     *  set its own file aside under a new name. */
    @Test
    fun aSecondQuarantineDoesNotReplaceTheFirst() {
        val first = "{first garbage".toByteArray()
        val second = "{second garbage".toByteArray()

        tempPath.writeBytes(first)
        makeStore()
        tempPath.writeBytes(second)
        makeStore()

        assertContentEquals(first, corruptPath.readBytes(), "the first quarantine must survive")
        val later = tempDir.listDirectoryEntries().filter { it.name.startsWith("dredfit-test.corrupt-") }
        assertEquals(1, later.size, "the second failure gets a file of its own")
        assertContentEquals(second, later.first().readBytes())
    }

    /** An engine state neither v3 nor v2 starts clean beside an intact
     *  journal, and the next persist rewrites the positions from `initial` —
     *  so the original must already be copied aside at launch. */
    @Test
    fun anUnreadableEngineStateKeepsTheOriginalAside() {
        val original = """{"engineState":{"nonsense":true},"records":[],"settings":null}""".toByteArray()
        tempPath.writeBytes(original)

        val store = makeStore()
        assertEquals(EngineState.initial, store.engineState, "the unreadable state starts clean")
        assertTrue(Files.exists(corruptPath), "the plan must stay recoverable")
        assertContentEquals(original, corruptPath.readBytes(), "the copy must be the original bytes")
    }
}
