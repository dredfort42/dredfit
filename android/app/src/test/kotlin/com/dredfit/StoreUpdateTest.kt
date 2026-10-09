//
//  Port of ios/DredfitTests/StoreUpdateTests.swift: `update`, the one way into
//  the persisted state from outside AppStore.kt.
//
//  Not ported, each for want of its subject on this side:
//  `testAChangeToOneFieldLeavesReadersOfAnotherAlone` pins @Observable's
//  per-property tracking, and `observe` here is one store-wide listener;
//  `testASeedIsNotWritten` is the UI tests' DEBUG seed; the two import tests
//  drive the Health share, which arrives with health/.
//

package com.dredfit

import com.dredfit.store.AppData
import org.junit.jupiter.api.Test
import kotlin.io.path.readText
import kotlin.test.assertEquals

class StoreUpdateTest : AppStoreTestCase() {

    @Test
    fun aChangeIsOnDiskWhenUpdateReturns() {
        val store = makeStore()
        store.update { it.copy(settings = it.settings.copy(soundsEnabled = false)) }
        val onDisk = AppData.decode(tempPath.readText())
        assertEquals(false, onDisk.settings?.soundsEnabled)
    }
}
