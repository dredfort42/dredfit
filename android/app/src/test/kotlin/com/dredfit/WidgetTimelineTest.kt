//
//  Port of ios/DredfitTests/WidgetTimelineTests.swift: the widget side of the
//  snapshot contract — entries start today, every day speaks from its own
//  date, and the week tally never crosses into a week it does not describe.
//  The stale "Next workout today" on a rest-day entry is the bug this file
//  keeps out.
//
//  The words are `Words` here (TodayStatusView), compared by key and
//  arguments; the rendered strings per state are TodayStatusWidgetTest
//  (androidTest), in en and ru.
//
//  Changed subject:
//  - `testEveryEntrySpeaksItsOwnLabel`: the snapshot carries each day's next
//    training DATE (WidgetShared.kt says why), so the entry's label is the
//    words for that date seen from the entry's own day.
//  - `testTallyWithoutWeekStartIsShownNowhere`: Android's snapshot always
//    names its week; the rule it guards — a tally shown only inside its
//    week — is pinned with a `weekStart` naming another Monday.
//  - `testAnExpiredTimelineIsNotAskedForAgainImmediately`: no timeline is
//    handed to a system here; the redraw is booked at the next local
//    midnight (`nextMidnight`), strictly ahead of now — the same loop the
//    Swift test keeps out.
//  Not ported:
//  - the `subline` halves of `testWorkoutDayWordsCarryThePlanNotALabel` and
//    `testDoneAndEmptyWords`, and the whole of
//    `test_subline_onAWorkoutDayWhosePlanIsMissing_…`: `subline` is the
//    lock-screen accessories' line, which has no Android surface
//    (TodayStatusWidget.kt).
//  - `test_entries_fromASnapshotWrittenBeforeThePlanExisted_…`: no Android
//    build wrote a snapshot without the plan.
//  Android-only: the week line (iOS could not test its `Text` chain — its
//  NOT COVERED note), the day an entry is picked for, the run-out snapshot,
//  the midnight a zone skips, and the size breakpoints.
//

package com.dredfit

import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.dredfit.core.LoadUnit
import com.dredfit.widgets.TodayEntry
import com.dredfit.widgets.TodayFamily
import com.dredfit.widgets.TodayProvider
import com.dredfit.widgets.TodayStatusView
import com.dredfit.widgets.WidgetSnapshot
import com.dredfit.widgets.WidgetSnapshot.DayStatus
import com.dredfit.workout.Words
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WidgetTimelineTest {

    // MARK: - Fixtures

    /** A Monday — the anchor the store writes snapshots from. */
    private val monday: LocalDate = LocalDate.of(2026, 10, 5)

    private fun date(offset: Int): LocalDate = monday.plusDays(offset.toLong())

    private fun day(offset: Int, status: DayStatus, next: Int? = null): WidgetSnapshot.Day =
        WidgetSnapshot.Day(date(offset), status, sessionNumber = null, nextDate = next?.let(::date))

    /** Two weeks the way WidgetBridge writes them: the write week fully
     *  statused, the next week planned, a next date where a non-workout day
     *  needs one. "Today" is Wednesday of the write week. */
    private fun fixture(): Pair<WidgetSnapshot, LocalDate> {
        val days = listOf(
            day(0, DayStatus.done), day(1, DayStatus.unmarked),
            day(2, DayStatus.rest, next = 3),               // today
            day(3, DayStatus.workout), day(4, DayStatus.workout), day(5, DayStatus.workout),
            day(6, DayStatus.rest, next = 7),
            day(7, DayStatus.workout), day(8, DayStatus.workout),
            day(9, DayStatus.rest, next = 10),
            day(10, DayStatus.workout), day(11, DayStatus.workout), day(12, DayStatus.workout),
            day(13, DayStatus.rest, next = 15),             // the far one: Sunday → Tuesday
        )
        val snapshot = WidgetSnapshot(
            days = days, totalSteps = 27, week = WidgetSnapshot.Week(workouts = 3, stepsDelta = 6),
            weekStart = monday, planSessionNumber = 12,
            plan = listOf(WidgetSnapshot.PlanRow("Push-up", "3×12", LoadUnit.reps, perSide = false)))
        return snapshot to date(2)
    }

    // MARK: - The timeline mapping

    @Test
    fun entriesStartTodayAndKeepThePastInTheWeekStrip() {
        val (snapshot, today) = fixture()
        val entries = TodayProvider.entries(snapshot, today)

        assertEquals(12, entries.size, "past days are dropped from the timeline")
        assertEquals(today, entries.first().date)
        // The strip still shows the whole calendar week, done Monday included.
        assertEquals((0..6).map(::date), entries.first().week.map { it.date })
        // An entry in the second week draws the second week around itself.
        assertEquals((7..13).map(::date), entries.first { it.date == date(7) }.week.map { it.date })
    }

    @Test
    fun everyEntrySpeaksItsOwnLabel() {
        val (snapshot, today) = fixture()
        val entries = TodayProvider.entries(snapshot, today)

        for (entry in entries) {
            val source = snapshot.days.first { it.date == entry.date }
            assertEquals(source.nextDate, entry.nextDate, "${entry.date}: the entry must carry its own day's date")
        }
        // And concretely: the far rest day says its own words, not today's.
        val far = TodayStatusView(entries.first { it.date == date(13) })
        assertEquals(Words.of("on %@", "Tuesday"), far.nextLabel(Locale.ENGLISH))
        assertEquals(Words.of("tomorrow"), TodayStatusView(entries.first()).nextLabel(Locale.ENGLISH))
    }

    @Test
    fun weekTallyStaysInsideItsWeek() {
        val (snapshot, today) = fixture()
        for (entry in TodayProvider.entries(snapshot, today)) {
            if (entry.date < date(7)) {
                assertNotNull(entry.summary, "${entry.date}: the write week keeps its tally")
            } else {
                assertNull(entry.summary, "${entry.date}: last week's numbers must not read as \"This week\"")
            }
        }
    }

    @Test
    fun aTallyOfAnotherWeekIsShownNowhere() {
        val (snapshot, today) = fixture()
        val stale = snapshot.copy(weekStart = monday.minusWeeks(1))
        for (entry in TodayProvider.entries(stale, today)) assertNull(entry.summary, "${entry.date}")
    }

    @Test
    fun noSnapshotMeansNoEntries() {
        assertTrue(TodayProvider.entries(null, date(2)).isEmpty())
        assertEquals(TodayEntry.empty(date(2)), TodayProvider.entry(null, date(2)),
                     "and the widget draws the signed blank")
    }

    // MARK: - Which day, and when the next one comes

    /** The entry is chosen by the day on the wall when the widget is drawn:
     *  the same snapshot, drawn the next morning, shows the next day. */
    @Test
    fun theEntryIsTheDayOnTheWallNotTheWriteDay() {
        val (snapshot, today) = fixture()
        assertEquals(today, TodayProvider.entry(snapshot, today).date)
        val thursday = TodayProvider.entry(snapshot, today.plusDays(1))
        assertEquals(date(3), thursday.date)
        assertEquals(DayStatus.workout, thursday.status)
    }

    /** Two weeks without the app: nothing is left to say, so the widget
     *  signs itself rather than repeating the last day it knew. */
    @Test
    fun aSnapshotThatRanOutDrawsTheSignedBlank() {
        val (snapshot, _) = fixture()
        val after = date(14)
        assertEquals(TodayEntry.empty(after), TodayProvider.entry(snapshot, after))
        assertEquals(Words.of("Dredfit"), TodayStatusView(TodayProvider.entry(snapshot, after)).headline)
    }

    @Test
    fun theNextRedrawIsTheComingMidnightAndNeverNow() {
        val zone = ZoneId.of("Europe/Berlin")
        val at11 = date(2).atTime(11, 0).atZone(zone).toInstant()
        assertEquals(date(3).atStartOfDay(zone).toInstant(), TodayProvider.nextMidnight(at11, zone))
        // At midnight itself the next one is a day away, not this instant —
        // the loop the Swift test keeps out.
        val midnight = date(3).atStartOfDay(zone).toInstant()
        assertEquals(date(4).atStartOfDay(zone).toInstant(), TodayProvider.nextMidnight(midnight, zone))
        // The wall decides: the same instant has a different midnight in
        // another zone.
        val tokyo = ZoneId.of("Asia/Tokyo")
        assertEquals(LocalTime.MIDNIGHT, TodayProvider.nextMidnight(at11, tokyo).atZone(tokyo).toLocalTime())
    }

    /** Where a zone's clocks jump over midnight, the day starts at the first
     *  minute it has — not at a time that does not exist, and not a day late. */
    @Test
    fun aDayWithoutAMidnightStartsAtItsFirstMinute() {
        val zone = ZoneId.of("America/Santiago")
        val gapDay = (0L until 366L).map { LocalDate.of(2026, 1, 1).plusDays(it) }
            .first { it.atStartOfDay(zone).toLocalTime() != LocalTime.MIDNIGHT }
        val eve = gapDay.minusDays(1).atTime(22, 0).atZone(zone).toInstant()
        val next = TodayProvider.nextMidnight(eve, zone)
        assertEquals(gapDay, next.atZone(zone).toLocalDate())
        assertEquals(gapDay.atStartOfDay(zone).toInstant(), next)
        assertTrue(next.isAfter(eve))
    }

    // MARK: - The views' words

    private fun entry(status: DayStatus?, sessionNumber: Int? = null, next: Int? = null,
                      planSession: Int? = null, plan: List<WidgetSnapshot.PlanRow> = emptyList(),
                      summary: WidgetSnapshot.Week? = null): TodayEntry =
        TodayEntry(date = date(2), status = status, sessionNumber = sessionNumber, week = emptyList(),
                   totalSteps = null, summary = summary, nextDate = next?.let(::date),
                   planSessionNumber = planSession, plan = plan)

    @Test
    fun restDayWordsUseTheEntrysOwnLabel() {
        val view = TodayStatusView(entry(DayStatus.rest, next = 3, planSession = 12))
        assertEquals(Words.of("Rest day"), view.headline)
        assertEquals(Words.of("Next: Workout %lld · %@", 12, Words.of("tomorrow")), view.nextPlanText(Locale.ENGLISH))
        assertTrue(view.restful, "a rest day's headline takes the quieter ink")
    }

    @Test
    fun workoutDayWordsCarryThePlanNotALabel() {
        val rows = listOf(WidgetSnapshot.PlanRow("Push-up", "3×12", LoadUnit.reps, perSide = false))
        val view = TodayStatusView(entry(DayStatus.workout, sessionNumber = 12, planSession = 12, plan = rows))
        assertNull(view.nextPlanText(Locale.ENGLISH), "a planned day IS the workout — no next label")
        assertTrue(view.marksWorkout)
    }

    @Test
    fun doneAndEmptyWords() {
        assertEquals(Words.of("Done ✓"), TodayStatusView(entry(DayStatus.done, next = 3)).headline)
        assertEquals(Words.of("Dredfit"), TodayStatusView(TodayEntry.empty(date(2))).headline,
                     "no snapshot yet — the widget signs itself, it does not guess")
        assertEquals(Words.of("Dredfit"), TodayStatusView(entry(DayStatus.unmarked)).headline)
    }

    /** The number comes from the snapshot's day, never from the view. */
    @Test
    fun headlineOnAWorkoutDayNamesTheSessionOnlyWhenTheSnapshotCarriedItsNumber() {
        assertEquals(Words.of("Workout %lld", 12), TodayStatusView(entry(DayStatus.workout, sessionNumber = 12)).headline,
                     "the day's own number is what the home screen shows")
        assertEquals(Words.of("Workout day"), TodayStatusView(entry(DayStatus.workout)).headline,
                     "and with no number the day is still a workout day, not a blank")
    }

    /** Both halves of "Next: Workout 12 · tomorrow" come out of the
     *  snapshot, and the line exists only when both arrived. */
    @Test
    fun nextPlanTextWhenEitherHalfOfTheLineIsMissingIsNotShownAtAll() {
        assertNotNull(TodayStatusView(entry(DayStatus.rest, next = 3, planSession = 12)).nextPlanText(Locale.ENGLISH),
                      "the fixture must produce the line when both halves are there")
        assertNull(TodayStatusView(entry(DayStatus.rest, next = 3)).nextPlanText(Locale.ENGLISH),
                   "without a session number there is no workout to point at")
        assertNull(TodayStatusView(entry(DayStatus.rest, planSession = 12)).nextPlanText(Locale.ENGLISH),
                   "and without a day there is no when — a half-line reads as a promise for today")
    }

    /** iOS's NOT COVERED note, covered: the week line prints its delta with
     *  its sign, and a deload week's negative one is shown, not hidden
     *  (TESTPLAN 12.12). */
    @Test
    fun theWeekLinePrintsTheDeltaWithItsSign() {
        val up = TodayStatusView(entry(DayStatus.rest, summary = WidgetSnapshot.Week(3, 6))).weekSummary
        assertEquals("This week · 3 workouts · +6 steps", up?.english)
        val down = TodayStatusView(entry(DayStatus.rest, summary = WidgetSnapshot.Week(1, -2))).weekSummary
        assertEquals("This week · 1 workouts · -2 steps", down?.english)
        val flat = TodayStatusView(entry(DayStatus.rest, summary = WidgetSnapshot.Week(0, 0))).weekSummary
        assertEquals("This week · 0 workouts · +0 steps", flat?.english, "a flat week is +0, as on iOS")
        assertNull(TodayStatusView(entry(DayStatus.rest)).weekSummary, "no tally, no line")
    }

    // MARK: - The sizes

    /** iOS's families by the size the launcher gives: the week strip needs a
     *  four-column widget, the plan list a tall one. */
    @Test
    fun eachIosFamilyHasItsSize() {
        assertEquals(TodayFamily.small, TodayFamily.of(TodayFamily.SMALL))
        assertEquals(TodayFamily.medium, TodayFamily.of(TodayFamily.MEDIUM))
        assertEquals(TodayFamily.large, TodayFamily.of(TodayFamily.LARGE))
        // Wide but short is still small (no room for the strip under the
        // headline); tall but narrow is still small (no room for the strip).
        assertEquals(TodayFamily.small, TodayFamily.of(DpSize(320.dp, 110.dp)))
        assertEquals(TodayFamily.small, TodayFamily.of(DpSize(130.dp, 400.dp)))
        assertEquals(TodayFamily.medium, TodayFamily.of(DpSize(320.dp, 200.dp)))
    }
}
