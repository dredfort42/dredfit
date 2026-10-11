//
//  Port of ios/DredfitTests/SessionLengthTests.swift: how long a session
//  takes, and what the person can do about it. Every number is DERIVED from
//  the engine, the only place duration arithmetic lives.
//  `sessionLengthRange()` is Swift's `(floor:, full:)` as a Pair, in that order.
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.core.easierVariation
import com.dredfit.core.generateSession
import com.dredfit.core.roundedAwayFromZero
import com.dredfit.core.setCut
import com.dredfit.store.AppStore
import com.dredfit.store.canMakeEasier
import com.dredfit.store.easierStep
import com.dredfit.store.nextSession
import com.dredfit.store.sessionLengthRange
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionLengthTest : AppStoreTestCase() {

    /** A trainee `variation` rungs up every ladder, at the dose ceiling —
     *  where a full session runs long. v3 shape, so it loads as written;
     *  `lastHard` keeps a probe out of the plan. */
    private fun advancedStore(counter: Int = 0, variation: Int, hasBar: Boolean = false): AppStore {
        fun at(p: Pattern) = minOf(variation, Library.count(p))
        val journal = Pattern.allCases.joinToString(",") { p ->
            val rows = (1..at(p)).joinToString(",") { "\"$it\":${Dose.grid(Library.unit(p, it)).max}" }
            "\"${p.rawValue}\",{$rows}"
        }
        val hard = Pattern.allCases.joinToString(",") { "\"${it.rawValue}\"" }
        val store = storeFrom("""
            {"engineState":{"counter":$counter,"hasBar":$hasBar,
                            "vars":[${pairs { at(it) }}],"doses":[${pairs { Dose.grid(Library.unit(it, at(it))).max }}],
                            "shown":[$journal],"lastHard":[$hard],
                            "failStreak":[${pairs { 0 }}]},
             "records":[],
             "settings":{"restWeekdays":[],"soundsEnabled":true,
                         "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """)
        assertEquals(at(Pattern.squat), store.engineState.vars[Pattern.squat], "the seed must load")
        return store
    }

    private val deepestVariation: Int get() = Pattern.allCases.maxOf { Library.count(it) }

    private fun minutes(x: Double): Int = roundedAwayFromZero(x).toInt()

    // MARK: - The range on Today

    /** Both ends are the ENGINE's own estimate. The low end is built as
     *  `min(floored, full)`, so `floor <= full` is what the clamp guarantees:
     *  the width is asserted STRICTLY. */
    @Test
    fun sessionLengthRange_onEveryVariation_isStrictlyShorterAtItsFloor() {
        for (variation in 1..deepestVariation) {
            val store = advancedStore(variation = variation)
            val (floor, full) = store.sessionLengthRange()
            assertTrue(floor < full,
                       "variation $variation: the range must have width — ${EngineConfig.setsBase} sets " +
                           "can be taken down to ${EngineConfig.setsFloor} on every movement")
            assertEquals(minutes(store.nextSession.estimatedTotalMin), full,
                         "variation $variation: the full end is not the announced plan")
            assertTrue(floor > 0, "variation $variation: a session takes time")
        }
    }

    /** …and the low end is the session it CLAIMS to be: every movement on the
     *  sets floor, checked to have landed there before the minutes compare. */
    @Test
    fun sessionLengthRange_floor_isTheSessionWithEveryMovementOnTheSetsFloor() {
        for (variation in 1..deepestVariation) {
            val store = advancedStore(variation = variation)
            var floored = store.engineState
            for (pattern in Pattern.allCases) {
                floored = Engine.setCut(state = floored, pattern = pattern,
                                        cut = floored.position(pattern).sets - EngineConfig.setsFloor)
            }
            val shortest = Engine.generateSession(floored)
            for (ex in shortest.exercises) {
                assertEquals(EngineConfig.setsFloor, ex.sets,
                             "variation $variation ${ex.pattern}: the expectation itself did not reach the floor")
            }
            assertEquals(minutes(shortest.estimatedTotalMin), store.sessionLengthRange().first,
                         "variation $variation: the low end is not the floored session")
        }
    }

    /** Nothing on the scale can be squeezed below a clean start on its floor. */
    @Test
    fun noPositionIsShorterThanACleanStartOnItsFloor() {
        val cleanFloor = advancedStore(variation = 1).sessionLengthRange().first
        for (variation in 1..deepestVariation) {
            val store = advancedStore(variation = variation)
            assertTrue(store.sessionLengthRange().first >= cleanFloor,
                       "variation $variation can be squeezed under the shortest session there is")
        }
    }

    /** A session grows as the ladder does. */
    @Test
    fun theFullSessionGrowsAlongTheLadder() {
        val low = advancedStore(variation = 1).sessionLengthRange().second
        val high = advancedStore(variation = deepestVariation).sessionLengthRange().second
        assertTrue(high > low, "a session at the top of the ladders must cost more than one at the bottom")
    }

    // MARK: - The handle that is left

    /** No step below the first variation, and no block carrying one. */
    @Test
    fun theEasierHandleIsInactiveOnTheFirstVariation() {
        val store = advancedStore(variation = 1)
        for (ex in store.nextSession.exercises) {
            assertEquals(1, ex.variation)
            assertFalse(store.canMakeEasier(ex.pattern), "${ex.pattern}: there is nothing below the first variation")
            assertNull(store.easierStep(ex.pattern))
        }
    }

    /** Where it IS active it carries its RESULT: what the block names is what
     *  the tap delivers. */
    @Test
    fun theEasierHandlePreviewIsWhatTheTapDelivers() {
        val store = advancedStore(variation = 3)
        val target = store.nextSession.exercises.first().pattern
        val step = assertNotNull(store.easierStep(target))

        store.makeEasier(target)

        val now = assertNotNull(store.nextSession.exercises.firstOrNull { it.pattern == target })
        assertEquals(now.name, step.name, "the block promised a variation the tap did not deliver")
        assertEquals(now.display, step.dose, "the block promised a dose the tap did not deliver")
        assertEquals(now.variation, step.variation, "the block promised a rung the tap did not land on")
    }

    /** The block asks the engine on a copy: reading it writes nothing. */
    @Test
    fun theEasierStepWritesNothing() {
        val store = advancedStore(variation = 3)
        val before = store.engineState.copy()
        for (ex in store.nextSession.exercises) store.easierStep(ex.pattern)
        assertEquals(before, store.engineState, "reading the step below moved the state")
    }

    /** `pull_bar` 3 → 2 is the ONLY boundary where the unit changes (negatives
     *  in reps → a hang in seconds), pinned by its two ends. The bar branch
     *  needs `hasBar` AND an odd counter. */
    @Test
    fun theUnitChangeIsFlaggedOnTheOneBoundaryThatHasOne() {
        val crossing = advancedStore(counter = 1, variation = 3, hasBar = true)
        val down = assertNotNull(crossing.easierStep(Pattern.pullBar))
        assertEquals(2, down.variation)
        assertTrue(down.unitChanged, "negatives → a hang is reps → seconds, and the block has to say so")

        val inside = advancedStore(counter = 1, variation = 4, hasBar = true)
        val quiet = assertNotNull(inside.easierStep(Pattern.pullBar))
        assertEquals(3, quiet.variation)
        assertFalse(quiet.unitChanged, "4 → 3 stays in reps; the unit note would be a lie")
    }

    /** The landing is the engine's: one variation down, on the base band,
     *  under the journal — and the work must not go up (hinge 4 → 3 is
     *  two-legged → per-side, where landing ON the journal would double it). */
    @Test
    fun theEasierHandleLandsInTheJournalAndNeverHeavier() {
        fun work(p: Pattern, v: Int, sets: Int, dose: Int): Int = sets * dose * Library.sides(p, v)
        for (variation in 2..deepestVariation) {
            val store = advancedStore(variation = variation)
            for (ex in store.nextSession.exercises) {
                if (!store.canMakeEasier(ex.pattern)) continue
                val p = ex.pattern
                val target = ex.variation - 1
                val journal = store.engineState.shownDose(p, variation = target)
                    ?: Dose.grid(Library.unit(p, target)).min

                val easier = Engine.easierVariation(state = store.engineState, pattern = p)
                val landed = assertNotNull(easier.doses[p])

                assertEquals(target, easier.vars[p], "variation $variation $p: the variation must drop")
                assertEquals(EngineConfig.setsBase, easier.sets[p] ?: EngineConfig.setsBase,
                             "variation $variation $p: the landing is on the base band")
                assertEquals(0, easier.sub[p] ?: 0)
                assertEquals(0, easier.cutOf(p))
                assertTrue(landed <= journal, "variation $variation $p: the journal is the ceiling")

                val before = (ex.loads ?: List(ex.sets) { ex.load }).sum() * Library.sides(p, ex.variation)
                val after = work(p, target, sets = EngineConfig.setsBase, dose = landed)
                assertTrue(after <= before, "variation $variation $p: easier must be easier")
            }
        }
    }
}
