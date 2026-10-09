//
//  Port of ios/DredfitTests/ShownPlanTests.swift. The engine's memory of
//  "what was on screen" is written when a plan is SHOWN, not only when a
//  session is completed: otherwise a plan looked at and not trained is
//  invisible to it, and "a descent never adds load" holds between finished
//  workouts and nowhere else. `recordPlanShown` is the one caller of
//  `recordShown`.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.store.refreshDay
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ShownPlanTest : AppStoreTestCase() {

    /** A trainee well up the ladders, seeded through the state file in the v3
     *  shape (`vars`/`doses`/`shown`, never `levels` — a v2 shape would go
     *  through the migration): every movement `variation` rungs up, the
     *  journal of what was shown behind it. The dose sits one rung BELOW the
     *  ceiling: at the ceiling the plan offers a probe, which is a different
     *  guarantee and not this suite's. */
    private fun advancedStore(variation: Int = 5): AppStore {
        fun at(p: Pattern) = minOf(variation, Library.count(p))
        fun dose(p: Pattern, v: Int): Int {
            val grid = Dose.grid(Library.unit(p, v))
            return grid.max - grid.step
        }
        val journal = Pattern.allCases.joinToString(",") { p ->
            val rows = (1..at(p)).joinToString(",") { "\"$it\":${dose(p, it)}" }
            "\"${p.rawValue}\",{$rows}"
        }
        val store = storeFrom("""
            {"engineState":{"counter":0,"vars":[${pairs { at(it) }}],"doses":[${pairs { dose(it, at(it)) }}],
                            "shown":[$journal],"failStreak":[${pairs { 0 }}]},
             "records":[],
             "settings":{"restWeekdays":[],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """)
        // The seed must actually load — a clean start would make every
        // assertion vacuous. The journal is checked too: a clean start carries
        // none, so this still bites at `variation == 1`.
        assertEquals(at(Pattern.pull), store.engineState.vars[Pattern.pull],
                     "the seed did not load: the pull slot is not where it was written")
        assertEquals(dose(Pattern.pull, at(Pattern.pull)),
                     store.engineState.shownDose(Pattern.pull, variation = at(Pattern.pull)),
                     "the seed did not load: the journal of what was shown is not there")
        return store
    }

    /** The widest position any ladder reaches — the sweeps walk to it. */
    private val deepestVariation: Int get() = Pattern.allCases.maxOf { Library.count(it) }

    private fun day(offset: Long, zone: ZoneId = ZoneId.systemDefault()): Instant =
        LocalDate.now(zone).plusDays(offset).atTime(10, 0).atZone(zone).toInstant()

    private fun work(ex: SessionExercise): Int = ex.plannedVolume * (if (ex.perSide) 2 else 1)

    // MARK: - Once per showing

    /** The showing is written down whole: every movement, at its work. */
    @Test
    fun aShowingIsWrittenDown() {
        val store = advancedStore()
        val plan = store.nextSession
        assertTrue(store.engineState.shownWork.isEmpty(), "nothing has been shown yet")

        store.recordPlanShown(plan)

        assertEquals(plan.exercises.size, store.engineState.shownWork.size)
        for (ex in plan.exercises) {
            assertEquals(work(ex), store.engineState.shownWork[ex.pattern],
                         "${ex.pattern.rawValue} was shown at a different work")
        }
    }

    /** ONE WRITE PER SHOWING: a redraw is not a new showing. The state file
     *  is the witness — deleted after the first showing, a second write would
     *  put it back. */
    @Test
    fun aRedrawOfTheSameShowingWritesNothing() {
        val store = advancedStore()
        store.recordPlanShown(store.nextSession)
        val afterFirst = store.engineState.copy()

        Files.delete(tempPath)
        store.recordPlanShown(store.nextSession)
        store.recordPlanShown(store.nextSession)

        assertEquals(afterFirst, store.engineState, "a redraw is not a new showing")
        assertFalse(Files.exists(tempPath), "the second and third redraws must not write at all")
    }

    /** …and writing it down must not change it: the plan is a fixed point,
     *  or the card would shrink under the reader's eyes, one set per render. */
    @Test
    fun writingAShowingDownDoesNotChangeThePlan() {
        for (variation in 1..deepestVariation) {
            val store = advancedStore(variation)
            val shown = store.nextSession
            store.recordPlanShown(shown)
            assertEquals(shown, store.nextSession, "variation $variation: the plan moved under the reader")
            store.recordPlanShown(store.nextSession)
            assertEquals(shown, store.nextSession, "variation $variation: and again on the next redraw")
        }
    }

    /** A plan that changed under the reader — the workout in front of it was
     *  finished — is the new showing it is. */
    @Test
    fun theNextPlanIsANewShowing() {
        val store = advancedStore()
        val first = store.nextSession
        store.recordPlanShown(first)
        store.completeWorkout(session = first, result = FeedbackResult.plan, date = day(-1))

        val second = store.nextSession
        store.recordPlanShown(second)
        for (ex in second.exercises) {
            assertEquals(work(ex), store.engineState.shownWork[ex.pattern],
                         "${ex.pattern.rawValue} is remembered at the plan on screen now")
        }
    }

    // MARK: - What the showing buys

    /** The guarantee against a plan only LOOKED at: a movement whose position
     *  did not rise may not come back heavier a week later, when the silent
     *  decay redraws the plan without a single tap. */
    @Test
    fun aPlanThatWasOnlySeenIsNotBeatenAWeekLater() {
        for (variation in 1..deepestVariation) {
            val store = advancedStore(variation)
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = day(-10))
            val seen = store.nextSession
            val ordBefore = seen.exercises.associate { it.pattern to Engine.progress(store.engineState, it.pattern) }
            store.recordPlanShown(seen)

            store.refreshDay(now = day(0))
            store.applySilentDecayIfNeeded(now = day(0))

            for (ex in store.nextSession.exercises) {
                val was = seen.exercises.firstOrNull { it.pattern == ex.pattern } ?: continue
                val before = ordBefore[ex.pattern] ?: continue
                if (Engine.progress(store.engineState, ex.pattern) > before) continue
                assertTrue(work(ex) <= work(was),
                           "variation $variation: ${ex.pattern.rawValue} came back " +
                               "heavier than the plan that was on screen a week ago")
            }
        }
    }

    /** A launch that could not READ the state file draws its plan from an
     *  empty state; writing that down would pin the freeze. A frozen journal
     *  is shown and not written, and the real one still loads once readable. */
    @Test
    fun aFrozenJournalIsNeverWrittenDown() {
        assumeNotRoot()
        val seed = advancedStore()
        seed.completeWorkout(session = seed.nextSession, result = FeedbackResult.plan, date = day(-1))
        setPermissions(tempPath, "---------")
        try {
            val frozen = makeStore()
            assertTrue(frozen.journalFrozen)
            frozen.recordPlanShown(frozen.nextSession)
            assertTrue(frozen.engineState.shownWork.isEmpty(),
                       "a plan drawn from a state nobody could read is not a showing")

            setPermissions(tempPath, "rw-r--r--")
            frozen.reloadIfNeeded()
            assertEquals(1, frozen.records.size, "the showing must not have pinned the freeze")
        } finally {
            setPermissions(tempPath, "rw-r--r--")
        }
    }

    // MARK: - Reset

    /** A reset clears the sets-handle fields — `cut` included, deliberately:
     *  sets skipped five rungs up mean nothing on the first variation — and
     *  keeps the bar in the doorway. */
    @Test
    fun resetClearsTheSetsAxisAndKeepsTheDoorway() {
        val store = advancedStore()
        store.setHasBar(true)
        val session = store.nextSession
        store.recordPlanShown(session)
        store.completeWorkout(session = session, result = FeedbackResult.plan, setsSkipped = mapOf(Pattern.pull to 1))
        assertTrue(store.engineState.cutOf(Pattern.pull) > 0, "the skip landed")
        assertFalse(store.engineState.shownWork.isEmpty())

        store.resetProgress()

        assertTrue(store.engineState.cut.isEmpty())
        assertTrue(store.engineState.setsHold.isEmpty())
        assertTrue(store.engineState.shownWork.isEmpty())
        assertTrue(store.engineState.shownOrd.isEmpty())
        assertTrue(store.engineState.hasBar, "the bar did not leave the doorway")
    }
}
