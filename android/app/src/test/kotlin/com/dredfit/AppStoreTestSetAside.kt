//
//  Port of ios/DredfitTests/AppStoreTests+SetAside.swift: the cap on set-aside
//  block moves when the set holds ids no pool has — moves this build does not
//  carry, such as cat-cow, the bird dog and Y-T-W.
//

package com.dredfit

import com.dredfit.store.canHideAnotherBlockMove
import com.dredfit.store.isBlockMoveHidden
import com.dredfit.store.setBlockMoveHidden
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppStoreTestSetAside : AppStoreTestCase() {

    /** An id no pool knows stays in the set — an imported backup or a
     *  downgrade must not lose it — but it takes no slot from the three. The
     *  sheet can neither name it nor bring it back, so a slot it held could
     *  never be freed: three such ids would lock the control for good.
     *
     *  Set through the control here; on a real phone they arrive in the state
     *  file of the build that still had those moves. */
    @Test
    fun aMoveAnOlderBuildHadTakesNoSlotFromTheThree() {
        val store = makeStore()
        val gone = setOf("cat-cow", "bird-dog", "y-t-w")
        for (id in gone) store.setBlockMoveHidden(id, true)
        assertEquals(gone, store.settings.hiddenBlockMoveIDs, "kept, not pruned")
        assertTrue(store.canHideAnotherBlockMove,
                   "ids nothing can name or bring back must not fill the cap")

        // Both pools count: one list holds the warm-up's and the cool-down's.
        for (id in listOf("side-steps", "chest-wall", "side-bends")) store.setBlockMoveHidden(id, true)
        assertTrue(store.isBlockMoveHidden("side-bends"))
        assertFalse(store.canHideAnotherBlockMove,
                    "three moves of the pools are the cap, a cool-down position among them")
    }
}
