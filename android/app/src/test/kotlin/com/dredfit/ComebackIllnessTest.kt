//
//  Port of ios/DredfitTests/ComebackIllnessTests.swift: the app half of the
//  comeback (#127, #128) — the accept guard and the sighted decline path.
//  `testThePreviewShowsBothOffersAsNumbers` waits for `comebackPreview`,
//  which states plans in UI words and arrives with the Today screen.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppData
import com.dredfit.store.AppStore
import com.dredfit.store.declineComeback
import com.dredfit.store.offersFreshStart
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ComebackIllnessTest : AppStoreTestCase() {

    /** A store whose only workout was `days` ago (midnights — the 89/90
     *  boundary is exactly what an elapsed-seconds seed gets wrong), every
     *  movement a couple of variations up, with the journal of what was shown:
     *  the probe at the ceiling is offered off it. */
    private fun returned(after: Long): AppStore {
        val state = EngineState.initial
        state.counter = 11
        for (p in Pattern.allCases) {
            val target = minOf(3, Library.count(p))
            state.vars[p] = target
            state.doses[p] = Dose.grid(Library.unit(p, target)).max
            state.shown[p] = (1..target).associateWith { v -> Dose.grid(Library.unit(p, v)).max }.toMutableMap()
        }
        val record = WorkoutRecord(sessionNumber = 11, date = daysAgo(after), result = FeedbackResult.plan,
                                   totalProgressAfter = Engine.totalProgress(state))
        Files.writeString(tempPath, AppData(engineState = state, records = listOf(record), settings = null).encode())
        return makeStore()
    }

    // MARK: - #128 the reentrancy guard

    @Test
    fun aDoubleAcceptDropsOnlyOnce() {
        val store = returned(after = 35)
        store.acceptComeback()
        val once = Engine.progress(store.engineState, Pattern.pull)
        store.acceptComeback()   // a double tap, an assistive-tech repeat…
        assertEquals(once, Engine.progress(store.engineState, Pattern.pull), "the second call must be a silent no-op")
        assertEquals(1, store.engineState.returnRun, "and must not deepen the v2.12 return series either")
    }

    @Test
    fun acceptAfterDeclineIsANoOpToo() {
        val store = returned(after = 35)
        store.declineComeback()
        val kept = Engine.progress(store.engineState, Pattern.pull)
        store.acceptComeback()
        assertEquals(kept, Engine.progress(store.engineState, Pattern.pull),
                     "the question was answered — a stray accept changes nothing")
    }

    // MARK: - #127 the sighted decline path

    @Test
    fun theFreshStartIsReachableFromNinetyDays() {
        assertFalse(returned(after = 89).offersFreshStart(), "89 midnights is one short of the fresh start")
        assertTrue(returned(after = 90).offersFreshStart(), "90 midnights reaches it, and the boundary is inclusive")
    }
}
