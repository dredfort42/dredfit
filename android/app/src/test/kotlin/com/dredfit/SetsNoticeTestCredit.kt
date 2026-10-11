//
//  Port of ios/DredfitTests/SetsNoticeTests+Credit.swift: a set the
//  cross-credit gives back, announced on the row of a movement that did not
//  train.
//

package com.dredfit

import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.store.AppData
import com.dredfit.store.AppSettings
import com.dredfit.store.aSetJustCameBack
import com.dredfit.store.nextSession
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SetsNoticeTestCredit : SetsNoticeTestCase() {

    /** The pull slot's two branches share their gains: the credit hands the
     *  bar a set and arms its hold, as the bar's own return would. The card
     *  last seen for the bar carried one set fewer, so its row says so. */
    @Test
    fun aSetTheCreditGivesBackIsAnnouncedOnItsRow() {
        val seed = EngineState.initial
        seed.hasBar = true
        seed.counter = 1
        seed.vars[Pattern.pull] = 4
        seed.doses[Pattern.pull] = 8
        seed.shown[Pattern.pull] = mutableMapOf(4 to 8)
        seed.vars[Pattern.pullBar] = 7
        seed.sets[Pattern.pullBar] = 5
        seed.doses[Pattern.pullBar] = 9
        seed.cut[Pattern.pullBar] = 3
        seed.setsHold[Pattern.pullBar] = 1
        seed.shown[Pattern.pullBar] = mutableMapOf(6 to 15, 7 to 15)
        Files.writeString(tempPath, AppData(engineState = seed, records = emptyList(), settings = AppSettings()).encode())
        val store = makeStore()
        assertEquals(seed, store.engineState, "the seed did not load — everything below would be about a clean start")

        train(store)
        val card = assertNotNull(store.records.last().exercises?.firstOrNull { it.pattern == Pattern.pullBar },
                                 "an odd counter puts the bar in this workout — its card is what the row is read against")
        assertEquals(2, card.sets, "the bar's card must be journalled with the set still off")
        assertNull(store.engineState.setsHold[Pattern.pullBar],
                   "the bar's own appearance must spend the hold without giving the set back — " +
                       "otherwise the line would be that appearance's, not the credit's")

        val crediting = train(store)
        assertEquals(listOf(Pattern.pull), crediting.exercises.map { it.pattern }.filter { it in Pattern.pullSide },
                     "the workout that credits the bar must train the row — the bar sits it out")
        assertEquals(2, store.engineState.cutOf(Pattern.pullBar),
                     "the credit must give the bar its set back — that return is what the row announces")
        assertEquals(EngineConfig.setsBackHold, store.engineState.setsHold[Pattern.pullBar],
                     "the credit's set return must arm the bar's hold — the hold is what the row reads")

        val row = assertNotNull(store.nextSession.exercises.firstOrNull { it.pattern == Pattern.pullBar },
                                "the next workout's pull slot is the bar again")
        assertEquals(3, row.sets,
                     "the row must show the set the credit gave back — a line about a set it does not show is false")
        assertTrue(store.aSetJustCameBack(row), "a set the credit gave back reached the row without a word")
    }
}
