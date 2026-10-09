//
//  Port of ios/DredfitTests/PushGateSignalsTests.swift: what the person reads
//  about the pull cap's two newer rules. A push whose next set band waits for
//  the pulls says so on its Progress row; a push the cap releases gets "A set
//  is back." — over a card that carries the stamp of the hold, and only there.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.EngineConfig
import com.dredfit.core.EngineState
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppData
import com.dredfit.store.AppSettings
import com.dredfit.store.AppStore
import com.dredfit.store.aSetJustCameBack
import com.dredfit.store.nextSession
import com.dredfit.store.nextSetWaitsForThePulls
import com.dredfit.store.setsJustHeldBackByThePulls
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class PushGateSignalsTest : AppStoreTestCase() {

    /** The pull slot and both pushes on their top variations, where sets
     *  come in bands. The pull stands at its dose floor (no band of its own
     *  while a test reads it); the pushes on their dose ceiling, where their
     *  next growth is the band above. */
    private fun seed(pullSets: Int, pushSets: Int, barSets: Int? = null): EngineState {
        val seed = EngineState.initial
        fun put(p: Pattern, sets: Int, ceiling: Boolean) {
            val top = Library.count(p)
            val grid = Dose.grid(Library.unit(p, top))
            seed.vars[p] = top
            if (sets == EngineConfig.setsBase) seed.sets.remove(p) else seed.sets[p] = sets
            seed.doses[p] = if (ceiling) grid.max else grid.min
            seed.shown[p] = mutableMapOf(top to (seed.doses[p] ?: grid.min))
        }
        put(Pattern.pull, pullSets, ceiling = false)
        if (barSets != null) {
            seed.hasBar = true
            put(Pattern.pullBar, barSets, ceiling = false)
        }
        put(Pattern.pushH, pushSets, ceiling = true)
        put(Pattern.pushV, pushSets, ceiling = true)
        return seed
    }

    private fun launch(state: EngineState, records: List<WorkoutRecord> = emptyList()): AppStore {
        Files.writeString(tempPath, AppData(engineState = state, records = records, settings = AppSettings()).encode())
        val store = makeStore()
        assertEquals(state, store.engineState, "the seed did not load — everything below would be about a clean start")
        return store
    }

    private fun day(offset: Long, zone: ZoneId = ZoneId.systemDefault()): Instant =
        LocalDate.now(zone).plusDays(offset).atStartOfDay(zone).toInstant()

    /** One workout on plan every two days, the plan as Today shows it. */
    private fun train(store: AppStore, setsSkipped: Map<Pattern, Int> = emptyMap()) {
        val session = store.nextSession
        store.recordPlanShown(session)
        store.completeWorkout(session = session, result = FeedbackResult.plan, setsSkipped = setsSkipped,
                              date = day(-300L + 2 * store.records.size))
    }

    private fun row(p: Pattern, session: Session): SessionExercise =
        assertNotNull(session.exercises.firstOrNull { it.pattern == p }, "this workout must carry $p — the rotation moved")

    // MARK: - The Progress row

    @Test
    fun aPushOnItsCeilingBehindThePullsWaitsForThem() {
        val store = launch(seed(pullSets = 3, pushSets = 3))
        assertTrue(store.nextSetWaitsForThePulls(Pattern.pushH),
                   "band 4 needs a pull on four sets: no count of steps says when that comes")
        assertTrue(store.nextSetWaitsForThePulls(Pattern.pushV))
        assertFalse(store.nextSetWaitsForThePulls(Pattern.pull), "nothing caps the pull itself")
    }

    @Test
    fun aPullOnTheBandsSetsBringsTheCountdownBack() {
        val store = launch(seed(pullSets = 4, pushSets = 3))
        assertFalse(store.nextSetWaitsForThePulls(Pattern.pushH),
                    "the pull already shows four: the push's set is a matter of its own steps")
    }

    /** With the bar on, the cap is the weaker branch, and that decides. */
    @Test
    fun withTheBarTheWeakerBranchKeepsThePushWaiting() {
        val store = launch(seed(pullSets = 4, pushSets = 3, barSets = 3))
        assertTrue(store.nextSetWaitsForThePulls(Pattern.pushH),
                   "the bar stands on three, and the push enters band 4 behind the weaker branch")
    }

    /** The band is what waits, not the sets on screen. */
    @Test
    fun theBandWaitsNotTheSetsOnScreen() {
        val state = seed(pullSets = 4, pushSets = 4)
        state.cut[Pattern.pushH] = 1
        val store = launch(state)
        assertTrue(store.nextSetWaitsForThePulls(Pattern.pushH),
                   "band 5 needs a pull on five, whatever the push shows today")
    }

    @Test
    fun onlyAPushBelowTheTopBandOfItsTopVariationWaits() {
        val below = seed(pullSets = 3, pushSets = 3)
        below.vars[Pattern.pushH] = Library.count(Pattern.pushH) - 1
        below.doses[Pattern.pushH] = Dose.grid(Library.unit(Pattern.pushH, Library.count(Pattern.pushH) - 1)).max
        val store = launch(below)
        assertFalse(store.nextSetWaitsForThePulls(Pattern.pushH),
                    "below the top variation the next milestone is a probe, which nothing caps")

        val full = launch(seed(pullSets = 3, pushSets = 5))
        assertFalse(full.nextSetWaitsForThePulls(Pattern.pushV), "at five sets there is no next set to wait for")
    }

    // MARK: - Today, through the pull cap's lines

    /** A push parked on its ceiling behind a pull on three shows the sets it
     *  showed last time: nothing was taken off, so nothing is said. */
    @Test
    fun aParkedPushSaysNothingAboutFewerSets() {
        val store = launch(seed(pullSets = 3, pushSets = 3))
        train(store)
        val vertical = row(Pattern.pushV, store.nextSession)
        assertEquals(3, store.engineState.position(Pattern.pushV).sets, "the push parked on band 3")
        assertEquals(3, vertical.sets, "and shows the three sets it showed last time")
        assertFalse(store.setsJustHeldBackByThePulls(vertical), "nothing was taken off")
        assertFalse(store.aSetJustCameBack(vertical))
        assertTrue(store.nextSetWaitsForThePulls(Pattern.pushV), "its next set still waits for the pulls")
    }

    /** Both pushes on 5×15 and a pull set skipped: the vertical push shows
     *  four while the pull does, then gets the fifth back — announced once. */
    @Test
    fun aFrozenPushTheCapReleasesSaysASetIsBack() {
        val store = launch(seed(pullSets = 5, pushSets = 5))
        val shown = mutableListOf<Int>()
        val cameBack = mutableListOf<Boolean>()
        for (k in 0 until 4) {
            val session = store.nextSession
            session.exercises.firstOrNull { it.pattern == Pattern.pushV }?.let { vertical ->
                shown += vertical.sets
                cameBack += store.aSetJustCameBack(vertical)
            }
            train(store, setsSkipped = if (k == 0) mapOf(Pattern.pull to 1) else emptyMap())
        }
        assertEquals(listOf(5, 4, 5), shown, "capped once while the pull showed four, then released")
        assertEquals(listOf(false, false, true), cameBack, "the released set is announced, once")
    }

    /** The first plan after the update releases a push the build before had
     *  frozen: announced over a stamped card, silent over one from before. */
    @Test
    fun theReleaseAfterTheUpdateIsAnnouncedOnlyOverAStampedCard() {
        val before = launch(seed(pullSets = 4, pushSets = 5))
        train(before)
        val record = before.records.last()
        assertEquals(4, assertNotNull(record.exercises?.firstOrNull { it.pattern == Pattern.pushV }).sets,
                     "the pull on four held the push at four")
        assertEquals(setOf(Pattern.pushH, Pattern.pushV), record.heldBack, "and the card carries the stamp")

        // The state a build without the cap memory left.
        val legacy = before.engineState.copy()
        legacy.sets[Pattern.pull] = 5
        legacy.shownCap.clear()
        legacy.shownOwn.clear()
        legacy.shownSkip.clear()

        val stamped = launch(legacy, records = listOf(record))
        val released = row(Pattern.pushV, stamped.nextSession)
        assertEquals(5, released.sets, "the update hands the frozen push its fifth set back")
        assertTrue(stamped.aSetJustCameBack(released), "over a stamped card the release is announced")

        val older = launch(legacy, records = listOf(record.copy(heldBack = null)))
        assertEquals(5, row(Pattern.pushV, older.nextSession).sets)
        assertFalse(older.aSetJustCameBack(row(Pattern.pushV, older.nextSession)),
                    "a card from before the stamp claims nothing, so the set returns without a word")
    }
}
