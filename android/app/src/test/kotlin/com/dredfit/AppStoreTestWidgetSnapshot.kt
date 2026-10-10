//
//  Port of ios/DredfitTests/AppStoreTests+WidgetSnapshot.swift: what the
//  store hands the widget. iOS decodes the App Group file the store wrote;
//  here the store hands its snapshot to `WidgetPublishing` (the app's
//  WidgetCenter writes the file), so the suite reads what a recorder was
//  handed, and WidgetSnapshotFileTest pins the file's round trip.
//
//  Changed subject: `testWidgetSnapshotLabelsSpeakFromTheirOwnDay` compares
//  each day's next training DATE (the words are the widget's, at render),
//  read through the same `NextTrainingDateLabel.words` the widget says.
//  Not ported: `testWidgetSnapshotFromAnOlderBuildStillDecodes` and
//  `testWidgetSnapshotWeekFromBeforeTheScaleChangeStillDecodes` — no
//  Android build wrote a snapshot before this one (WidgetShared.kt).
//  Android-only: a past day done by its own record (iOS's first test only
//  ever has today's), the launch and the second read of a frozen journal
//  publishing, and every persisted change reaching the widget.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.store.isRestDay
import com.dredfit.store.localDay
import com.dredfit.store.nextSession
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.setSounds
import com.dredfit.store.swiftWeekday
import com.dredfit.store.totalProgress
import com.dredfit.store.weekSummary
import com.dredfit.ui.today.NextTrainingDateLabel
import com.dredfit.widgets.WidgetSnapshot
import com.dredfit.widgets.WidgetSnapshot.DayStatus
import com.dredfit.widgets.refreshWidgetSnapshot
import com.dredfit.workout.Words
import java.nio.file.Files
import java.time.Clock
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AppStoreTestWidgetSnapshot : AppStoreTestCase() {

    @AfterTest
    fun readable() {
        if (Files.exists(tempPath)) setPermissions(tempPath, "rw-r--r--")
    }

    private val zone: ZoneId get() = ZoneId.systemDefault()

    private fun mondayOf(day: LocalDate): LocalDate = day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    @Test
    fun widgetSnapshotMirrorsWeekStatuses() {
        val widget = WidgetRecorder()
        val store = makeStore(widgets = widget)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)   // today → done

        val snap = widget.last
        val today = LocalDate.now(zone)
        assertEquals(14, snap.days.size, "the snapshot must cover two weeks")
        assertEquals(mondayOf(today), snap.days[0].date, "it must start on Monday so any entry can draw its own week")
        assertEquals(DayStatus.done, snap.days.first { it.date == today }.status)

        for (day in snap.days.filter { it.date > today }) {
            val expected = if (store.isRestDay(day.date.atStartOfDay(zone).toInstant())) DayStatus.rest else DayStatus.workout
            assertEquals(expected, day.status, "${day.date}: future days must mirror the rest-day settings")
        }
        for (day in snap.days.filter { it.date < today }) {
            val expected = if (store.isRestDay(day.date.atStartOfDay(zone).toInstant())) DayStatus.rest else DayStatus.unmarked
            assertEquals(expected, day.status, "${day.date}: a past training day with nothing recorded stays " +
                "unmarked — the Calendar does not accuse and neither does the widget")
        }
        for (day in snap.days) assertNull(day.sessionNumber, "${day.date}: a finished day carries no session number")
    }

    @Test
    fun widgetSnapshotCarriesTheStepsWeekAndPlan() {
        val widget = WidgetRecorder()
        val store = makeStore(widgets = widget)
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)

        val snap = widget.last
        assertEquals(store.totalProgress, snap.totalSteps)
        assertEquals(store.weekSummary().workouts, snap.week.workouts)
        assertEquals(store.weekSummary().stepsDelta, snap.week.stepsDelta)
        assertEquals(store.nextSession.sessionNumber, snap.planSessionNumber)
        // The write day's own next day is the one the app shows right now;
        // the week tally is stamped with its Monday so the widget can keep it
        // inside the week it belongs to.
        val today = LocalDate.now(zone)
        assertEquals(localDay(store.nextTrainingDate(store.today), zone), snap.days.first { it.date == today }.nextDate)
        assertEquals(mondayOf(today), snap.weekStart)

        assertEquals(store.nextSession.exercises.size, snap.plan.size)
        assertEquals(store.nextSession.exercises.first().name, snap.plan.first().name)
        assertEquals(store.nextSession.exercises.map { it.name }, snap.plan.map { it.name })
        assertEquals(store.nextSession.exercises.map { Words.display(it) }, snap.plan.map { it.detail },
                     "the widget cannot format loads itself — they arrive as the parts of the app's own words")
        assertTrue(snap.plan.any { it.unit == com.dredfit.core.LoadUnit.hold },
                   "the fixture's plan must carry a hold, or the unit's journey goes unchecked")
        assertFalse(snap.plan.any { it.head.isEmpty() })
    }

    /** Next days are per day, not per write: a rest-day entry rendered days
     *  after the app was last opened must not repeat the write day's — each
     *  entry speaks from its own day. */
    @Test
    fun widgetSnapshotLabelsSpeakFromTheirOwnDay() {
        val widget = WidgetRecorder()
        val store = makeStore(widgets = widget)
        val today = LocalDate.now(zone)
        // Exactly one rest day, and it is tomorrow: the dates below are read
        // off a calendar this test owns, not off the shipped default.
        val tomorrowWeekday = swiftWeekday(today.plusDays(1).dayOfWeek)
        store.update(refreshWidget = false) { it.copy(settings = it.settings.copy(restWeekdays = setOf(tomorrowWeekday))) }
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)

        val snap = widget.last
        val tomorrow = Words.of("tomorrow")
        fun label(day: WidgetSnapshot.Day) =
            day.nextDate?.let { NextTrainingDateLabel.words(it, day.date, Locale.ENGLISH) }
        assertNotEquals(tomorrow, label(snap.days.first { it.date == today }),
                        "from the write day the rest day is in the way — its label is \"on X\"")
        for (day in snap.days) {
            when {
                day.status == DayStatus.rest && day.date > today ->
                    assertEquals(tomorrow, label(day), "${day.date}: a rest-day entry must speak from its own day")
                day.status == DayStatus.workout ->
                    assertNull(day.nextDate, "${day.date}: a planned day IS the workout — no next day")
                else -> Unit   // past days and today are covered elsewhere
            }
        }
    }

    /** The home screen must not be told "nothing done" over a history the
     *  app cannot currently read — a frozen launch publishes nothing, at
     *  launch or when backgrounded. */
    @Test
    fun frozenLaunchLeavesTheWidgetSnapshotAlone() {
        assumeNotRoot()
        val seed = makeStore()
        seed.completeWorkout(session = seed.nextSession, result = FeedbackResult.plan)

        setPermissions(tempPath, "---------")
        val widget = WidgetRecorder()
        val frozen = makeStore(widgets = widget)
        assertTrue(frozen.journalFrozen, "the fixture must freeze the launch")
        frozen.refreshWidgetSnapshot()   // what backgrounding does
        assertTrue(widget.published.isEmpty(), "the widget must keep showing the last state that was real")
    }

    // MARK: - Android-only

    /** Past days come from the journal, not `isDone`, which knows only the
     *  latest record: Monday's workout stays done on a Wednesday that has
     *  none, and Tuesday, missed, stays unmarked. */
    @Test
    fun aPastDayIsDoneByItsOwnRecord() {
        val wednesday = LocalDate.of(2026, 10, 7)
        val clock = Clock.fixed(wednesday.atTime(10, 0).atZone(zone).toInstant(), zone)
        val widget = WidgetRecorder()
        val store = makeStore(clock = clock, widgets = widget)
        store.update { it.copy(settings = it.settings.copy(restWeekdays = setOf(1))) }   // Sundays only
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan,
                              date = wednesday.minusDays(2).atTime(10, 0).atZone(zone).toInstant())
        store.refreshWidgetSnapshot()

        val days = widget.last.days.associateBy { it.date }
        assertEquals(DayStatus.done, days.getValue(wednesday.minusDays(2)).status)
        assertEquals(DayStatus.unmarked, days.getValue(wednesday.minusDays(1)).status)
        assertEquals(DayStatus.workout, days.getValue(wednesday).status)
        assertEquals(2, days.getValue(wednesday).sessionNumber, "today's workout carries its number")
    }

    /** Rest is rest FROM something: a fresh install whose onboarding ended on
     *  a marked weekday is offered the plan on Today, and the widget must not
     *  tell that person "Rest day" — only today; the marked weekdays still
     *  rest everywhere else in the grid. */
    @Test
    fun aFreshInstallOnAMarkedWeekdayIsOfferedTheWorkout() {
        val wednesday = LocalDate.of(2026, 10, 7)
        val clock = Clock.fixed(wednesday.atTime(10, 0).atZone(zone).toInstant(), zone)
        val widget = WidgetRecorder()
        val store = makeStore(clock = clock, widgets = widget)
        store.update { it.copy(settings = it.settings.copy(restWeekdays = setOf(swiftWeekday(DayOfWeek.WEDNESDAY)))) }

        val days = widget.last.days.associateBy { it.date }
        assertEquals(DayStatus.workout, days.getValue(wednesday).status)
        assertEquals(1, days.getValue(wednesday).sessionNumber)
        assertEquals(DayStatus.rest, days.getValue(wednesday.plusDays(7)).status, "next Wednesday still rests")
    }

    /** iOS's init refreshes the snapshot: a widget placed before the app is
     *  next opened still has the launch's state. */
    @Test
    fun theLaunchPublishesTheSnapshot() {
        val seed = makeStore()
        seed.completeWorkout(session = seed.nextSession, result = FeedbackResult.plan)

        val widget = WidgetRecorder()
        makeStore(widgets = widget)
        assertEquals(1, widget.published.size)
        assertEquals(DayStatus.done, widget.last.days.first { it.date == LocalDate.now(zone) }.status)
    }

    /** The second read of a frozen journal is the first moment the store
     *  knows the person: the widget hears it then, not at the next change. */
    @Test
    fun aJournalReadOnTheSecondTryPublishesTheSnapshot() {
        assumeNotRoot()
        val seed = makeStore()
        seed.completeWorkout(session = seed.nextSession, result = FeedbackResult.plan)
        setPermissions(tempPath, "---------")
        val widget = WidgetRecorder()
        val store = makeStore(widgets = widget)
        assertTrue(store.journalFrozen)

        setPermissions(tempPath, "rw-r--r--")
        store.reloadIfNeeded()
        assertFalse(store.journalFrozen)
        assertEquals(1, widget.published.size, "the reload publishes once")
        assertEquals(DayStatus.done, widget.last.days.first { it.date == LocalDate.now(zone) }.status)
    }

    /** Every persisted change reaches the widget (it decides whether it
     *  shows anything new) — a setting as much as a workout. */
    @Test
    fun aSettingWrittenReachesTheWidget() {
        val widget = WidgetRecorder()
        val store = makeStore(widgets = widget)
        val before = widget.published.size
        store.setSounds(false)
        assertEquals(before + 1, widget.published.size)
    }
}
