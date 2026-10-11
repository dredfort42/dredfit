//
//  Port of ios/DredfitTests/CalendarCaptionTests.swift: what the calendar
//  side of the store says — the week card's number and the next training day.
//  All five tests; the label's words are `NextTrainingDateLabel.words`
//  (ui/today/NextTrainingDateLabel.kt), the locale a parameter.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.restAppliesToday
import com.dredfit.store.sameDay
import com.dredfit.store.swiftWeekday
import com.dredfit.store.weekSummary
import com.dredfit.ui.today.NextTrainingDateLabel
import com.dredfit.workout.Words
import java.time.Instant
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class CalendarCaptionTest : AppStoreTestCase() {

    /** ISO week Mon 6 Jul 2026 – Sun 12 Jul 2026. */
    private val monday: Instant get() = date(2026, 7, 6)
    private val wednesday: Instant get() = date(2026, 7, 8)
    private val saturday: Instant get() = date(2026, 7, 11)
    private val sunday: Instant get() = date(2026, 7, 12)

    /** Seeded directly: `completeWorkout` always stamps a
     *  `totalProgressAfter`, and the branch under test exists only for
     *  records written before v3, which carry none. */
    private fun journalEntry(day: Instant, progress: Int?) =
        WorkoutRecord(sessionNumber = 1, date = day, result = FeedbackResult.plan, totalProgressAfter = progress)

    // MARK: - The week card's number

    @Test
    fun weekSummary_whenTheWeeksLastRecordPredatesTheScale_readsZeroRatherThanTheBaselineBackwards() {
        val store = makeStore()
        store.update {
            it.copy(records = listOf(journalEntry(date(2026, 7, 3), progress = 40),   // Friday, the week before
                                     journalEntry(wednesday, progress = null)))          // written before v3
        }

        val week = store.weekSummary(wednesday)

        assertEquals(1, week.workouts, "the workout itself happened and still counts")
        assertEquals(0, week.stepsDelta,
                     "a week that straddles the update measures from zero: subtracting the baseline " +
                         "from a missing number would print the whole history back as a loss")
    }

    @Test
    fun weekSummary_whenTheWeekEndsLowerThanItStarted_reportsTheDropInsteadOfHidingIt() {
        val store = makeStore()
        store.update {
            it.copy(records = listOf(journalEntry(date(2026, 7, 3), progress = 40),
                                     journalEntry(wednesday, progress = 30)))
        }
        assertEquals(-10, store.weekSummary(wednesday).stepsDelta,
                     "a deload week is negative, and that is honest rather than an error to clamp away")
    }

    // MARK: - The next training day

    /** A fresh install on a marked weekday is offered the plan on Today (rest
     *  is rest FROM something), so the next training date is today as well. */
    @Test
    fun nextTrainingDate_whenAFreshInstallStartsOnAMarkedWeekday_isToday() {
        val store = makeStore()
        val weekday = swiftWeekday(store.today.atZone(store.zone).dayOfWeek)
        store.update { it.copy(settings = it.settings.copy(restWeekdays = setOf(weekday))) }
        assertFalse(store.restAppliesToday, "Today offers the plan")
        assertTrue(store.sameDay(store.nextTrainingDate, store.today))
    }

    /** Saturday and Sunday off, so Monday is the next training day seen from
     *  either — the same date, two different words. */
    @Test
    fun nextTrainingDateLabel_forAGivenDay_speaksFromThatDayAndNotFromToday() {
        val store = makeStore()
        store.update { it.copy(settings = it.settings.copy(restWeekdays = setOf(7, 1))) }
        val fromSaturday = NextTrainingDateLabel.words(store, saturday, Locale.US)
        val fromSunday = NextTrainingDateLabel.words(store, sunday, Locale.US)
        assertEquals(store.nextTrainingDate(saturday), store.nextTrainingDate(sunday),
                     "the fixture must aim both days at the same Monday, or the words below " +
                         "are allowed to differ for an uninteresting reason")
        assertEquals(Words.of("tomorrow"), fromSunday, "one day before it, the next training day is tomorrow")
        assertNotEquals(fromSaturday, fromSunday,
                        "two days before it, it is not — a relative word baked at write time reads wrong on every later day")
        assertNotEquals(Words.of("today"), fromSaturday, "and it is certainly not today: Saturday is a rest day here")
        assertEquals("on Monday", fromSaturday.english)
    }

    /** `toggleRestDay` refuses the seventh day, so this state only arrives
     *  from a file; the hop limit is the whole defence against a search that
     *  never ends. */
    @Test
    fun nextTrainingDate_whenEveryWeekdayIsMarkedAsRest_stopsAfterASingleWeek() {
        val store = makeStore()
        store.update { it.copy(settings = it.settings.copy(restWeekdays = (1..7).toSet())) }
        val aWeekOn = monday.atZone(store.zone).plusDays(7).toInstant()
        assertEquals(aWeekOn, store.nextTrainingDate(monday),
                     "the search gives up after exactly seven hops rather than walking forever")
    }
}
