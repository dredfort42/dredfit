//
//  The store with its disk off the calling thread — Android's own, no Swift
//  twin (iOS writes synchronously inside every change). What must survive the
//  move is everything a caller could observe on iOS: the change is in memory
//  before `update` returns, the file always ends on the newest state, a
//  failure stands until a write succeeds, and a frozen journal's second read
//  lands before the rest of the activation runs. The two executors here are
//  queues the test drains by hand, so every interleaving is a line of code.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.store.AppData
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.nextSession
import java.nio.file.Files
import java.util.concurrent.Executor
import kotlin.io.path.readText
import kotlin.io.path.writeText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StoreThreadingTest : AppStoreTestCase() {

    /** An executor that runs nothing until told to. */
    private class Queue : Executor {
        val tasks = ArrayDeque<Runnable>()
        override fun execute(command: Runnable) {
            tasks.addLast(command)
        }

        fun runAll() {
            while (tasks.isNotEmpty()) tasks.removeFirst().run()
        }
    }

    private val disk = Queue()
    private val main = Queue()

    private fun queuedStore(): AppStore = AppStore(tempPath, null, disk, main)

    private fun onDisk(): AppData = AppData.decode(tempPath.readText())

    @Test
    fun aChangeIsInMemoryBeforeItsWriteRuns() {
        val store = queuedStore()
        store.update { it.copy(settings = it.settings.copy(soundsEnabled = false)) }
        assertFalse(store.settings.soundsEnabled, "readers see the change at once, as on iOS")
        assertFalse(Files.exists(tempPath), "nothing has touched the disk yet")
        disk.runAll()
        assertFalse(onDisk().settings!!.soundsEnabled)
    }

    @Test
    fun changesMadeWhileAWriteWaitsLeaveTheFileOnTheNewest() {
        val store = queuedStore()
        store.update { it.copy(settings = it.settings.copy(reminderHour = 7)) }
        store.update { it.copy(settings = it.settings.copy(reminderHour = 8)) }
        store.update { it.copy(settings = it.settings.copy(reminderHour = 9)) }
        assertEquals(1, disk.tasks.size, "one write waits; the newer changes replace its bytes")
        disk.runAll()
        assertEquals(9, onDisk().settings!!.reminderHour)
    }

    @Test
    fun aChangeMadeAfterAWriteRanGetsATurnOfItsOwn() {
        val store = queuedStore()
        store.update { it.copy(settings = it.settings.copy(reminderHour = 7)) }
        disk.runAll()
        assertEquals(7, onDisk().settings!!.reminderHour)
        store.update { it.copy(settings = it.settings.copy(reminderHour = 8)) }
        assertEquals(1, disk.tasks.size)
        disk.runAll()
        assertEquals(8, onDisk().settings!!.reminderHour)
    }

    /** A workout finished while a settings write waits rides that same
     *  write: the journal never lands without the state it was rated into. */
    @Test
    fun aWorkoutFinishedWhileAWriteWaitsLandsWithIt() {
        val store = queuedStore()
        store.update { it.copy(settings = it.settings.copy(reminderHour = 7)) }
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        disk.runAll()
        val file = onDisk()
        assertEquals(1, file.records.size)
        assertEquals(7, file.settings!!.reminderHour)
        assertEquals(store.engineState.counter, file.engineState.counter)
    }

    @Test
    fun aFailureReachesTheScreenOnlyThroughMainAndStandsUntilAWriteSucceeds() {
        val store = queuedStore()
        var notified = 0
        store.observe { notified += 1 }
        // A directory where the file should be: the atomic rename fails.
        Files.createDirectory(tempPath)
        Files.writeString(tempPath.resolve("occupied"), "x")
        store.update { it.copy(settings = it.settings.copy(reminderHour = 7)) }
        val afterChange = notified
        disk.runAll()
        assertNull(store.lastPersistError, "the result is main's to deliver")
        main.runAll()
        assertNotNull(store.lastPersistError)
        assertEquals(afterChange + 1, notified, "the banner is told it has something to say")

        Files.delete(tempPath.resolve("occupied"))
        Files.delete(tempPath)
        store.update { it.copy(settings = it.settings.copy(reminderHour = 8)) }
        disk.runAll()
        main.runAll()
        assertNull(store.lastPersistError, "a write that succeeded clears it")
        assertEquals(8, onDisk().settings!!.reminderHour)
    }

    @Test
    fun aFrozenJournalsSecondReadLandsBeforeTheRestOfTheActivation() {
        assumeNotRoot()
        tempPath.writeText("{}")
        setPermissions(tempPath, "---------")
        val store = queuedStore()
        assertTrue(store.journalFrozen)
        setPermissions(tempPath, "rw-------")
        // A real journal behind the freeze: one workout eight days ago, which
        // the activation's silent decay reads — and can only read once the
        // journal has landed.
        val writer = AppStore(tempDir.resolve("other.json"))
        writer.completeWorkout(session = writer.nextSession, result = FeedbackResult.plan, date = daysAgo(8))
        Files.copy(tempDir.resolve("other.json"), tempPath, java.nio.file.StandardCopyOption.REPLACE_EXISTING)

        store.activate()
        assertTrue(store.journalFrozen, "the read is still on the disk thread")
        assertTrue(store.records.isEmpty())
        disk.runAll()
        assertTrue(store.journalFrozen, "and its result on its way to main")
        assertNull(store.settings.silentDecayAppliedFor, "nothing of the activation ran ahead of the journal")
        main.runAll()
        assertFalse(store.journalFrozen)
        assertEquals(1, store.records.size)
        assertNotNull(store.settings.silentDecayAppliedFor, "the rest of the activation ran on the journal that landed")
    }

    @Test
    fun aJournalUsedWhileItsReadRanIsNotReplacedByIt() {
        assumeNotRoot()
        tempPath.writeText("{}")
        setPermissions(tempPath, "---------")
        val store = queuedStore()
        setPermissions(tempPath, "rw-------")
        val writer = AppStore(tempDir.resolve("other.json"))
        writer.completeWorkout(session = writer.nextSession, result = FeedbackResult.plan)
        Files.copy(tempDir.resolve("other.json"), tempPath, java.nio.file.StandardCopyOption.REPLACE_EXISTING)

        store.reloadIfNeeded()
        disk.runAll()
        // Used on main while the read was away: the change pins the freeze.
        store.update { it.copy(settings = it.settings.copy(reminderHour = 6)) }
        main.runAll()
        assertTrue(store.journalFrozen, "a reload now would replace the person's change")
        assertEquals(6, store.settings.reminderHour)
        assertTrue(store.records.isEmpty())
    }
}
