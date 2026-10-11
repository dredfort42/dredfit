//
//  Port of ios/DredfitTests/SafetySignalsTests.swift: the run of consecutive
//  training days (#98), derived from the journal — nothing persisted, so the
//  same journal always gives the same answer. (The pain-streak tests were
//  removed on iOS too: there is no pain channel left to count.)
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.store.consecutiveTrainingDays
import com.dredfit.store.nextSession
import com.dredfit.store.todayWouldExtendALongRun
import com.dredfit.store.wouldBeConsecutiveDay
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SafetySignalsTest : AppStoreTestCase() {

    private fun day(offset: Long, zone: ZoneId = ZoneId.systemDefault()): Instant =
        LocalDate.now(zone).plusDays(offset).atTime(10, 0).atZone(zone).toInstant()

    // MARK: - Consecutive training days (#98)

    @Test
    fun consecutiveDaysCountRunsAndBreakOnAGap() {
        val store = makeStore()
        for (offset in listOf(-5L, -4, -2, -1)) {
            store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = day(offset))
        }
        assertEquals(2, store.consecutiveTrainingDays(endingOn = day(-1)), "the gap on day −3 breaks the run")
        assertEquals(2, store.consecutiveTrainingDays(endingOn = day(-4)))
        assertEquals(0, store.consecutiveTrainingDays(endingOn = day(-3)), "an untrained day carries no run")
    }

    @Test
    fun twoWorkoutsOnOneDayCountOnce() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = day(-1))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              date = day(-1).plusSeconds(3600))
        assertEquals(1, store.consecutiveTrainingDays(endingOn = day(-1)), "days are counted, not records")
    }

    /** The offer appears exactly when today would be the fourth day in a
     *  row, and never once today's workout is done. */
    @Test
    fun longRunOfferThreshold() {
        val two = makeStore()
        for (offset in listOf(-2L, -1)) {
            two.completeWorkout(session = two.nextSession, result = FeedbackResult.plan, date = day(offset))
        }
        assertEquals(3, two.wouldBeConsecutiveDay)
        assertFalse(two.todayWouldExtendALongRun, "a third day in a row is fine")

        val three = makeStore(path = tempDir.resolve("dredfit-test.three.json"))
        for (offset in listOf(-3L, -2, -1)) {
            three.completeWorkout(session = three.nextSession, result = FeedbackResult.plan, date = day(offset))
        }
        assertEquals(4, three.wouldBeConsecutiveDay)
        assertTrue(three.todayWouldExtendALongRun, "a would-be fourth day earns the one quiet sentence")

        three.completeWorkout(session = three.nextSession, result = FeedbackResult.plan)
        assertFalse(three.todayWouldExtendALongRun, "once today is trained the offer is moot")
    }
}
