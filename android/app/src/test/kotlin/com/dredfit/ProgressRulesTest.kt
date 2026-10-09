//
//  The rules the iOS Progress, Calendar, History and Settings views keep
//  beside their bodies, ported with the Compose screens — Android's own
//  file, no Swift twin (iOS cannot reach them from a test; see the "a rule
//  written as a private member of a SwiftUI view" notes in HistorySheet.swift):
//  the break bands under the chart and the line that explains one
//  (ProgressScreen.swift), the next-milestone label (PatternProgressRow.swift),
//  the month grid (CalendarScreen.swift), the history sheet's wall clock,
//  walk and rating change (HistorySheet.swift), and the rest-day chips
//  (SettingsSections.swift).
//

package com.dredfit

import com.dredfit.core.Dose
import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.nextSession
import com.dredfit.ui.progress.CalendarScreen
import com.dredfit.ui.progress.HistorySheet
import com.dredfit.ui.progress.PatternProgressRow
import com.dredfit.ui.progress.ProgressScreen
import com.dredfit.ui.progress.StepsChart
import com.dredfit.ui.settings.RhythmSection
import com.dredfit.workout.Words
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProgressRulesTest : AppStoreTestCase() {

    private val zone: ZoneId = ZoneId.of("Europe/Berlin")

    private fun point(id: Int, day: LocalDate, value: Int, result: FeedbackResult = FeedbackResult.plan,
                      ownNumber: Boolean = false, ownSkips: Boolean = false) =
        StepsChart.StepPoint(id, day.atTime(10, 0).atZone(zone).toInstant(), value, result, ownNumber, ownSkips)

    private val d0 = LocalDate.of(2026, 7, 1)

    // MARK: - The break bands

    /** Seven calendar days is the decay's gap; six is not a break. */
    @Test
    fun aBandStandsOnlyOnAGapTheSilentDecayCouldHaveRunIn() {
        val six = listOf(point(0, d0, 10), point(1, d0.plusDays(6), 8))
        assertTrue(ProgressScreen.breakBands(six, zone).isEmpty())
        val seven = listOf(point(0, d0, 10), point(1, d0.plusDays(EngineConfig.silentDecayGapDays.toLong()), 8))
        val band = ProgressScreen.breakBands(seven, zone).single()
        assertEquals(EngineConfig.silentDecayGapDays, band.days)
        assertTrue(band.costSteps, "a drop under 'on plan' with nothing of the session's own is the break's")
    }

    /** "Tough", a number of its own, skipped sets: each lowers a level by
     *  itself, so under any of them the break claims no drop. */
    @Test
    fun theBreakClaimsNoDropTheReturningSessionExplains() {
        val back = d0.plusDays(10)
        fun cost(after: StepsChart.StepPoint) =
            ProgressScreen.breakBands(listOf(point(0, d0, 10), after), zone).single().costSteps
        assertFalse(cost(point(1, back, 8, result = FeedbackResult.less)))
        assertFalse(cost(point(1, back, 8, ownNumber = true)))
        assertFalse(cost(point(1, back, 8, ownSkips = true)))
        assertFalse(cost(point(1, back, 10)), "no drop, nothing to claim")
        assertTrue(cost(point(1, back, 9)))
    }

    /** The freshest band that COST steps explains the chart, else the longest. */
    @Test
    fun theLineUnderTheChartExplainsTheBandThatCostSteps() {
        val points = listOf(point(0, d0, 10), point(1, d0.plusDays(30), 11),     // 30 days, no cost
                            point(2, d0.plusDays(38), 9),                        // 8 days, cost
                            point(3, d0.plusDays(60), 9))                        // 22 days, no cost
        val bands = ProgressScreen.breakBands(points, zone)
        assertEquals(3, bands.size)
        assertEquals(8, ProgressScreen.explainedBand(bands)?.days)
        val harmless = bands.map { it.copy(costSteps = false) }
        assertEquals(30, ProgressScreen.explainedBand(harmless)?.days)
        assertEquals(listOf(Words.of("A break of %lld days.", 8), Words.of("The plan met you lower."), Words.of("Others are marked too.")),
                     ProgressScreen.breakFact(bands[1], bands.size))
        assertEquals(listOf(Words.of("A break of %lld days.", 30)), ProgressScreen.breakFact(harmless[0], 1))
    }

    /** Records with no snapshot plot nothing — and the total plots the
     *  number the record carries. */
    @Test
    fun theChartPlotsOnlyRecordsThatCarryTheirPoint() {
        val store = makeStore()
        store.update { it.copy(records = listOf(
            WorkoutRecord(sessionNumber = 1, date = Instant.ofEpochSecond(1_000), result = FeedbackResult.plan),
            WorkoutRecord(sessionNumber = 2, date = Instant.ofEpochSecond(90_000), result = FeedbackResult.plan,
                          totalProgressAfter = 7)),
            engineState = it.engineState.copy().also { s -> s.counter = 2 }) }
        assertEquals(listOf(7), ProgressScreen.chartPoints(store, null).map { it.value })
        assertTrue(ProgressScreen.chartPoints(store, Pattern.squat).isEmpty(), "no position snapshot, no point")
    }

    // MARK: - The next milestone

    @Test
    fun belowTheTopVariationTheLabelCountsToTheProbe() {
        val store = makeStore()
        val milestone = PatternProgressRow.nextMilestone(store, Pattern.squat)
        assertTrue(milestone is PatternProgressRow.NextMilestone.Probe, "$milestone")
        assertEquals("next variation probe in ${milestone.steps}",
                     PatternProgressRow.label(milestone)?.english)
    }

    @Test
    fun onTheTopVariationTheLabelCountsToASetAndStopsAtFive() {
        val store = makeStore()
        val p = Pattern.squat
        store.update { s -> s.copy(engineState = s.engineState.copy().also { it.vars[p] = Library.count(p) }) }
        val milestone = PatternProgressRow.nextMilestone(store, p)
        assertTrue(milestone is PatternProgressRow.NextMilestone.SetIn || milestone == PatternProgressRow.NextMilestone.SetOncePullsCatchUp,
                   "$milestone")
        store.update { s -> s.copy(engineState = s.engineState.copy().also {
            it.sets[p] = EngineConfig.setsMax
            it.doses[p] = Dose.grid(Library.unit(p, Library.count(p))).max
        }) }
        assertEquals(PatternProgressRow.NextMilestone.Ceiling, PatternProgressRow.nextMilestone(store, p))
        assertNull(PatternProgressRow.label(PatternProgressRow.NextMilestone.Ceiling), "a ceiling promises nothing")
    }

    // MARK: - The month grid

    @Test
    fun theGridMarksEachDayAndPadsWholeMondayFirstWeeks() {
        val now = LocalDate.of(2026, 7, 15).atTime(12, 0).atZone(zone).toInstant()
        val store = makeStore(clock = Clock.fixed(now, zone))
        store.update { it.copy(settings = it.settings.copy(restWeekdays = setOf(1)),   // Sundays
                               records = listOf(WorkoutRecord(sessionNumber = 1, result = FeedbackResult.plan,
                                                              date = LocalDate.of(2026, 7, 13).atTime(9, 0).atZone(zone).toInstant()))) }
        val days = CalendarScreen.monthDays(store, YearMonth.of(2026, 7))
        assertEquals(0, days.size % 7)
        // 1 July 2026 is a Wednesday: Monday and Tuesday are June's.
        assertEquals(listOf(29, 30, 1), days.take(3).map { it.number })
        assertEquals(CalendarScreen.DayState.out, days[0].state)
        fun state(day: Int) = days.first { it.date == LocalDate.of(2026, 7, day) }.state
        assertEquals(CalendarScreen.DayState.done, state(13))
        assertEquals(CalendarScreen.DayState.missed, state(14), "a past day with nothing is unmarked")
        assertEquals(CalendarScreen.DayState.today, state(15))
        assertEquals(CalendarScreen.DayState.rest, state(19))
        assertEquals(CalendarScreen.DayState.rest, state(12), "a past Sunday is a rest day, never missed")
        assertEquals(CalendarScreen.DayState.planned, state(16))
        assertEquals(1, CalendarScreen.completed(store, YearMonth.of(2026, 7)))
        assertEquals(0, CalendarScreen.completed(store, YearMonth.of(2026, 6)))
    }

    /** The one tappable non-completed day is the one the sheet describes. */
    @Test
    fun onlyTheNextTrainingDayOpensThePreview() {
        val now = LocalDate.of(2026, 7, 15).atTime(12, 0).atZone(zone).toInstant()
        val store = makeStore(clock = Clock.fixed(now, zone))
        val days = CalendarScreen.monthDays(store, YearMonth.of(2026, 7))
        val tappable = days.filter { CalendarScreen.isNextTrainingDay(store, it) }.map { it.number }
        assertEquals(listOf(15), tappable)
    }

    /** "Completed today" replaces the month's count only on today's month. */
    @Test
    fun theDoneCardStandsOnlyOverTodaysMonth() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        val month = CalendarScreen.shownMonth(store, 0)
        assertTrue(CalendarScreen.showsDoneCard(store, month))
        assertFalse(CalendarScreen.showsDoneCard(store, CalendarScreen.shownMonth(store, -1)))
    }

    // MARK: - The history sheet

    private fun exercise(sets: Int = 3) = SessionExercise(pattern = Pattern.squat, name = "Squat", variation = 1,
                                                          unit = LoadUnit.reps, load = 10, perSide = false, sets = sets,
                                                          restSetSec = 60, restExerciseSec = 90, loads = null, probe = null)

    /** The wall clock stands down past twice the plan, and for a record
     *  with no plan to hold it against. */
    @Test
    fun theClockLineStandsDownWhenItIsAboutTheDayRatherThanTheWorkout() {
        // 3×10 reps at 2.5 s, two rests of 60 and one of 90, no blocks: 285 s.
        fun record(seconds: Int?, exercises: List<SessionExercise>? = listOf(exercise())) =
            WorkoutRecord(sessionNumber = 1, date = Instant.ofEpochSecond(1_000), result = FeedbackResult.plan,
                          exercises = exercises, durationSec = seconds, warmupSec = 0, cooldownSec = 0)
        assertEquals(2, HistorySheet.clockMinutes(record(140)))
        assertEquals(3, HistorySheet.clockMinutes(record(150)), "2.5 rounds away from zero, as Swift`s .rounded()")
        assertEquals(1, HistorySheet.clockMinutes(record(20)), "never 0 minutes")
        assertEquals(10, HistorySheet.clockMinutes(record(570)), "twice the plan still counts; 9.5 rounds away from zero")
        assertNull(HistorySheet.clockMinutes(record(571)))
        assertNull(HistorySheet.clockMinutes(record(150, exercises = null)))
        assertNull(HistorySheet.clockMinutes(record(0)))
        assertNull(HistorySheet.clockMinutes(record(null)))
        // A skipped movement is charged no minutes, so the same clock is
        // past twice a plan that has nothing left in it.
        val skipped = record(150).copy(skipped = setOf(Pattern.squat))
        assertNull(HistorySheet.clockMinutes(skipped))
    }

    @Test
    fun theWalkStepsToTheNeighboursOfTheRecordOnScreen() {
        val a = WorkoutRecord(sessionNumber = 1, date = Instant.ofEpochSecond(1_000), result = FeedbackResult.plan)
        val b = a.copy(sessionNumber = 2, date = Instant.ofEpochSecond(2_000))
        val c = a.copy(sessionNumber = 3, date = Instant.ofEpochSecond(3_000))
        assertEquals(null to b, HistorySheet.neighbours(listOf(a, b, c), a))
        assertEquals(a to c, HistorySheet.neighbours(listOf(a, b, c), b))
        assertEquals(b to null, HistorySheet.neighbours(listOf(a, b, c), c))
        assertEquals(null to null, HistorySheet.neighbours(listOf(a, b), c))
    }

    /** Never the answer already given, and "easy" only for a workout done
     *  in full — the rating screen's own gate. */
    @Test
    fun theRatingChangeOffersTheOtherAnswersAndGatesEasy() {
        val full = WorkoutRecord(sessionNumber = 1, date = Instant.ofEpochSecond(1_000), result = FeedbackResult.plan,
                                 exercises = listOf(exercise()))
        assertEquals(listOf(FeedbackResult.less, FeedbackResult.more), HistorySheet.ratingChoices(full))
        val short = full.copy(setsSkipped = mapOf(Pattern.squat to 1))
        assertEquals(listOf(FeedbackResult.less), HistorySheet.ratingChoices(short))
        assertEquals(listOf(FeedbackResult.plan, FeedbackResult.more),
                     HistorySheet.ratingChoices(full.copy(result = FeedbackResult.less)))
    }

    /** Only the LAST record can be re-rated, and only while the store says so. */
    @Test
    fun onlyTheLastRecordOffersTheRatingChange() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              date = Instant.now().minusSeconds(86_400 * 2))
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        assertTrue(HistorySheet.canChangeRating(store, store.records.last()))
        assertFalse(HistorySheet.canChangeRating(store, store.records.first()))
    }

    // MARK: - The rest-day chips

    @Test
    fun theWeekStartsWhereTheLocaleStartsItAndTheLastTrainingDayIsLocked() {
        assertEquals(listOf(2, 3, 4, 5, 6, 7, 1), RhythmSection.displayOrder(2))
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), RhythmSection.displayOrder(1))
        val six = setOf(1, 2, 3, 4, 5, 6)
        assertTrue(RhythmSection.isLocked(six, 7), "the last training day cannot become rest")
        assertFalse(RhythmSection.isLocked(six, 1), "a rest day can always go back to training")
        assertFalse(RhythmSection.isLocked(setOf(1, 2), 7))
        assertEquals(java.time.DayOfWeek.SUNDAY, RhythmSection.dayOfWeek(1))
        assertEquals(java.time.DayOfWeek.SATURDAY, RhythmSection.dayOfWeek(7))
    }
}
