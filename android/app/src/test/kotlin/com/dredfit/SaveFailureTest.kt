//
//  Port of ios/DredfitTests/SaveFailureTests.swift: a write that fails must
//  say so, and the next write that works must take the message back.
//
//  No fake writer — `StateFile.write` is the real one, atomicity included.
//  The iOS fixture is a directory that does not exist yet; that cannot fail
//  here, because this `StateFile.write` creates its directory. A READ-ONLY
//  directory fails it instead (the temp file beside the target cannot be
//  created), and making it writable is what "the disk recovered" means.
//

package com.dredfit

import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.store.retryPersist
import com.dredfit.store.setSounds
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SaveFailureTest : AppStoreTestCase() {

    private val directory: Path get() = tempDir.resolve("dredfit-locked")
    private val statePath: Path get() = directory.resolve("state.json")

    @BeforeEach
    fun lock() {
        assumeNotRoot()
        Files.createDirectory(directory)
        setPermissions(directory, "r-xr-xr-x")
    }

    @AfterEach
    fun unlock() {
        if (Files.exists(directory)) setPermissions(directory, "rwxr-xr-x")
    }

    /** A store whose first write fails, with the failure already asserted:
     *  a store that wrote fine would make every test below vacuous. */
    private fun failedStore(): AppStore {
        val store = makeStore(statePath)
        assertNull(store.lastPersistError, "nothing has been written yet")
        store.setSounds(false)
        assertNotNull(store.lastPersistError, "the fixture must actually fail to write")
        return store
    }

    private fun recover() = setPermissions(directory, "rwxr-xr-x")

    @Test
    fun aFailedWrite_isRecorded() {
        val store = failedStore()
        assertFalse(store.settings.soundsEnabled, "the change itself stays in memory — only the file missed it")
    }

    @Test
    fun theNextSuccessfulWrite_clearsTheError() {
        val store = failedStore()
        recover()

        store.setSounds(true)

        assertNull(store.lastPersistError)
        assertTrue(Files.exists(statePath))
    }

    @Test
    fun retryPersist_writesTheStateThatWasKeptInMemory() {
        val store = failedStore()
        recover()

        store.retryPersist()

        assertNull(store.lastPersistError, "a working disk takes the retry")
        assertFalse(makeStore(statePath).settings.soundsEnabled, "and what it took is the change the first write missed")
    }

    @Test
    fun retryPersist_onAStillFailingDisk_keepsTheError() {
        val store = failedStore()

        store.retryPersist()

        assertNotNull(store.lastPersistError, "the banner must not claim a save that did not happen")
    }

    @Test
    fun activate_retriesAFailedWrite() {
        val store = failedStore()
        recover()

        store.activate()

        assertNull(store.lastPersistError, "coming back to the app is the second chance a quiet session gets")
        assertTrue(Files.exists(statePath))
    }
}
