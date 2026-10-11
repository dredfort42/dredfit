//
//  Port of ios/DredfitTests/AppStoreTests+ProgressAndCalendar.swift: the
//  progress curve, the week summary, the pull-up bar branch and the
//  calendar/rest-day logic — the same journal read as a curve, as an ISO week
//  and as a next-training date.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.journal.RecordedPosition
import com.dredfit.store.WeekSummary
import com.dredfit.store.isDone
import com.dredfit.store.isRestDay
import com.dredfit.store.nextSession
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.progressCurve
import com.dredfit.store.record
import com.dredfit.store.sameDay
import com.dredfit.store.weekSummary
import java.time.Instant
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AppStoreTestProgressAndCalendar : AppStoreTestCase() {

    // MARK: - Level curve

    @Test
    fun progressCurveIsCutAtTheGivenDate() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)

        assertEquals(store.records.mapNotNull { it.totalProgressAfter }, store.progressCurve())
        // Swift's `.distantPast` / `.distantFuture`.
        assertEquals(emptyList(), store.progressCurve(through = Instant.MIN),
                     "nothing was recorded before the cut, so there is no curve")
        assertEquals(store.records.size, store.progressCurve(through = Instant.MAX).size)
    }

    // MARK: - Week summary

    @Test
    fun weekSummaryUsesMondayFirstIsoWeeks() {
        val store = makeStore()
        // Sunday Jul 12, 2026 closes the ISO week Mon Jul 6 – Sun Jul 12.
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 12))
        val sundaySteps = assertNotNull(store.records.last().totalProgressAfter)
        // Monday Jul 13 opens the next ISO week Mon Jul 13 – Sun Jul 19.
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = date(2026, 7, 14))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.more, date = date(2026, 7, 16))
        val last = assertNotNull(store.records.last().totalProgressAfter)

        // A Sunday-first calendar (US default) would wrongly pull in Jul 12.
        val thisWeek = store.weekSummary(date(2026, 7, 15))
        assertEquals(2, thisWeek.workouts, "the Sunday-Jul-12 workout must fall in the previous ISO week")
        assertEquals(last - sundaySteps, thisWeek.stepsDelta, "the delta counts from the last record before Monday")

        val prevWeek = store.weekSummary(date(2026, 7, 12))
        assertEquals(1, prevWeek.workouts, "Sunday closes the previous ISO week")
        assertEquals(sundaySteps, prevWeek.stepsDelta, "the first week counts from zero")
    }

    @Test
    fun weekSummaryEmptyWeekIsZero() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.more, date = date(2026, 7, 10))
        assertEquals(WeekSummary(workouts = 0, stepsDelta = 0), store.weekSummary(date(2026, 7, 22)),
                     "a week without workouts must read 0 · +0, not carry old gains")
    }

    // MARK: - Pull-up bar

    @Test
    fun hasBarPersistsAndDrivesAlternation() {
        val store = makeStore()
        store.setHasBar(true)
        // session 1 (counter 0) stays horizontal even with the bar on
        assertFalse(store.nextSession.exercises.any { it.pattern == Pattern.pullBar })
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        // session 2 (counter 1) trains the vertical branch
        val second = store.nextSession
        assertTrue(second.exercises.any { it.pattern == Pattern.pullBar },
                   "with the bar on, the second session must swap in the vertical pull")
        assertFalse(second.exercises.any { it.pattern == Pattern.pull })

        store.completeWorkout(session = second, result = FeedbackResult.more)
        // The cross-credit moves the branch on pull sessions too, so the level
        // is read from the engine — this test is about the snapshot and the reload.
        val barPosition = store.engineState.position(Pattern.pullBar)
        assertEquals(RecordedPosition(variation = barPosition.variation, sets = barPosition.sets, dose = barPosition.dose),
                     store.records.last().positionsAfter?.get(Pattern.pullBar),
                     "the journal snapshot must include the pull_bar position")
        val reloaded = makeStore()
        assertTrue(reloaded.engineState.hasBar)
        assertEquals(barPosition, reloaded.engineState.position(Pattern.pullBar))

        // turning the bar off freezes the branch but keeps its progress
        reloaded.setHasBar(false)
        assertFalse(reloaded.nextSession.exercises.any { it.pattern == Pattern.pullBar })
        assertEquals(barPosition, reloaded.engineState.position(Pattern.pullBar),
                     "turning the bar off keeps the branch where it was")
    }

    // MARK: - Calendar logic

    @Test
    fun isRestDayOnTheDefaultWeekdays() {
        val store = makeStore()
        assertTrue(store.isRestDay(date(2026, 7, 20)), "Monday is a default rest day")
        assertTrue(store.isRestDay(date(2026, 7, 15)), "and Wednesday")
        assertTrue(store.isRestDay(date(2026, 7, 17)), "and Friday")
        assertFalse(store.isRestDay(date(2026, 7, 16)), "Thursday is a training day")
        assertFalse(store.isRestDay(date(2026, 7, 19)), "and so is Sunday")
    }

    @Test
    fun nextTrainingDateFromFreeWeekday() {
        val store = makeStore()
        val thursday = date(2026, 7, 16)
        assertEquals(thursday, store.nextTrainingDate(thursday), "no workout today and not a rest day → today")
    }

    @Test
    fun nextTrainingDateSkipsARestDay() {
        val store = makeStore()
        val next = store.nextTrainingDate(date(2026, 7, 20))
        assertTrue(store.sameDay(next, date(2026, 7, 21)), "from Monday the next workout is on Tuesday")
    }

    @Test
    fun nextTrainingDateAfterADoneSundaySkipsToTuesday() {
        val store = makeStore()
        val sunday = date(2026, 7, 19)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = sunday)
        val next = store.nextTrainingDate(sunday)
        assertTrue(store.sameDay(next, date(2026, 7, 21)),
                   "Sunday completed → next on Tuesday (Monday is a rest day)")
    }

    @Test
    fun doneTodayAndRecordLookup() {
        val store = makeStore()
        val day = date(2026, 7, 16)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = day)
        assertTrue(store.isDone(day))
        assertFalse(store.isDone(date(2026, 7, 17)), "the next day, done should reset without migrations")
        assertNotNull(store.record(day))
        assertNull(store.record(date(2026, 7, 15)))
    }

    // MARK: - A full month of workouts

    @Test
    fun monthOfWorkoutsAccumulatesConsistently() {
        val store = makeStore()
        var day = date(2026, 7, 1).atZone(ZoneId.systemDefault())
        var completed = 0
        while (completed < 24) {
            if (!store.isRestDay(day.toInstant())) {
                store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan, date = day.toInstant())
                completed += 1
            }
            day = day.plusDays(1)
        }
        assertEquals(24, store.records.size)
        assertEquals((1..24).toList(), store.records.map { it.sessionNumber })
        val chart = store.records.mapNotNull { it.totalProgressAfter }
        assertEquals(chart.sorted(), chart, "the total must not drop with \"on plan\"")
        assertEquals(24, makeStore().records.size)
    }
}
