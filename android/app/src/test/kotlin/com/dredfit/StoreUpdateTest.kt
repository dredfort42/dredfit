//
//  Port of ios/DredfitTests/StoreUpdateTests.swift: `update`, the one way into
//  the persisted state from outside AppStore.kt, and the import as one update.
//
//  Not ported, each for want of its subject on this side:
//  `testAChangeToOneFieldLeavesReadersOfAnotherAlone` pins @Observable's
//  per-property tracking, and `observe` here is one store-wide listener;
//  `testASeedIsNotWritten` is the UI tests' DEBUG seed.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.store.AppData
import com.dredfit.store.backfillHealth
import com.dredfit.store.enableHealth
import com.dredfit.store.exportBackup
import com.dredfit.store.healthBackfillCount
import com.dredfit.store.importBackup
import com.dredfit.store.nextSession
import org.junit.jupiter.api.Test
import kotlin.io.path.readText
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class StoreUpdateTest : AppStoreTestCase() {

    @Test
    fun aChangeIsOnDiskWhenUpdateReturns() {
        val store = makeStore()
        store.update { it.copy(settings = it.settings.copy(soundsEnabled = false)) }
        val onDisk = AppData.decode(tempPath.readText())
        assertEquals(false, onDisk.settings?.soundsEnabled)
    }

    // MARK: - The import, one update

    @Test
    fun anImportOntoAPhoneWithoutTheShareTurnsHealthOff() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        val backup = store.exportBackup()
        spy.shareGranted = false
        store.importBackup(backup)
        assertFalse(store.settings.healthEnabled, "a backup cannot prove this phone granted the workout write")
        assertFalse(makeStore(health = spy).settings.healthEnabled, "and the file says so too")
    }

    @Test
    fun anEntryExportedHereStaysExportedThroughTheImport() = runHealth {
        val spy = HealthSpy()
        val store = makeStore(health = spy)
        store.enableHealth()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.healthExportJob?.join()
        spy.allFail = true
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 16))
        store.healthExportJob?.join()
        val backup = store.exportBackup()
        spy.allFail = false
        store.backfillHealth()
        assertEquals(0, store.healthBackfillCount, "the premise: the second entry went out after the backup")
        store.importBackup(backup)
        assertEquals(0, store.healthBackfillCount, "or the backfill writes it to Health Connect a second time")
    }
}
