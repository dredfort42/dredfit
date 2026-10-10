//
//  What each size of the home-screen widget draws, per state — the render
//  half of WidgetTimelineTest (JVM), as ShareCardRenderTest is ShareCardTest's.
//  `runGlanceAppWidgetUnitTest` composes the widget's content without a host;
//  on the device, so the words are the real resources in en and ru (its
//  environment also needs android.os on the classpath, which the JVM suite's
//  stub jar throws on).
//
//  The iOS counterpart is the views' switch in TodayStatusWidget.swift, which
//  no Swift test renders: its suite pins `headline`/`subline` as strings.
//  What is pinned here is which pieces each family shows — iOS's small (kicker
//  and status), medium (kicker, steps, status, week strip) and large (kicker,
//  status, next plan line, plan list, week line) — and the widget's own
//  catalog winning over the app's for a key both carry. The lines that
//  shrink before they truncate (headline, plan names, week line) are
//  RemoteViews of their own, which Glance's test tree cannot read into:
//  here they are present or absent, and WidgetHostTest reads their words off
//  the inflated widget.
//

package com.dredfit

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import androidx.glance.appwidget.testing.unit.GlanceAppWidgetUnitTest
import androidx.glance.appwidget.testing.unit.hasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasTestTag
import androidx.glance.testing.unit.hasTextEqualTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.core.LoadUnit
import com.dredfit.ui.tr
import com.dredfit.widgets.TodayEntry
import com.dredfit.widgets.TodayFamily
import com.dredfit.widgets.TodayProvider
import com.dredfit.widgets.TodayStatusContent
import com.dredfit.widgets.WidgetColors
import com.dredfit.widgets.WidgetSnapshot
import com.dredfit.widgets.WidgetSnapshot.DayStatus
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate
import java.util.Locale

@RunWith(AndroidJUnit4::class)
class TodayStatusWidgetTest {

    private val app: Context = InstrumentationRegistry.getInstrumentation().targetContext

    /** The app's resources in `language`, as a per-app language gives them. */
    private fun resources(language: String): Resources {
        val config = Configuration(app.resources.configuration).apply { setLocale(Locale.forLanguageTag(language)) }
        return app.createConfigurationContext(config).resources
    }

    /** Monday 5 October 2026; "today" is Wednesday the 7th. */
    private val monday = LocalDate.of(2026, 10, 5)
    private fun date(offset: Int) = monday.plusDays(offset.toLong())

    private val plan = listOf(
        WidgetSnapshot.PlanRow("Push-up", "3×12", LoadUnit.reps, perSide = false),
        WidgetSnapshot.PlanRow("Side plank", "3×30", LoadUnit.hold, perSide = true),
    )

    /** The write week: Monday done, Tuesday missed, `today` as given, Thursday
     *  and Friday planned, the weekend resting; the next week planned. */
    private fun snapshot(today: DayStatus, sessionNumber: Int? = null): WidgetSnapshot {
        val statuses = listOf(DayStatus.done, DayStatus.unmarked, today, DayStatus.workout, DayStatus.workout,
                              DayStatus.rest, DayStatus.rest) + List(7) { if (it >= 5) DayStatus.rest else DayStatus.workout }
        // As the store writes it: from today on, a day that is not itself a
        // workout names the next one.
        fun next(i: Int): LocalDate? = (i + 1 until statuses.size).firstOrNull { statuses[it] == DayStatus.workout }?.let(::date)
        val days = statuses.mapIndexed { i, status ->
            WidgetSnapshot.Day(date(i), status, sessionNumber = if (i == 2) sessionNumber else null,
                               nextDate = if (i >= 2 && status != DayStatus.workout) next(i) else null)
        }
        return WidgetSnapshot(days = days, totalSteps = 27, week = WidgetSnapshot.Week(workouts = 1, stepsDelta = 6),
                              weekStart = monday, planSessionNumber = 3, plan = plan)
    }

    private fun entry(today: DayStatus, sessionNumber: Int? = null): TodayEntry =
        TodayProvider.entry(snapshot(today, sessionNumber), date(2))

    private fun draw(entry: TodayEntry, family: TodayFamily, language: String = "en",
                     check: GlanceAppWidgetUnitTest.() -> Unit) = runGlanceAppWidgetUnitTest {
        val res = resources(language)
        setAppWidgetSize(when (family) {
            TodayFamily.small -> TodayFamily.SMALL
            TodayFamily.medium -> TodayFamily.MEDIUM
            TodayFamily.large -> TodayFamily.LARGE
        })
        setContext(app)
        provideComposable {
            TodayStatusContent(entry, family, WidgetColors(highContrast = false), say = { res.tr(it, widget = true) },
                               locale = res.configuration.locales[0], open = MainActivity.openToday(app))
        }
        check()
    }

    private fun GlanceAppWidgetUnitTest.text(tag: String, value: String) {
        onNode(hasTestTag(tag)).assert(hasTextEqualTo(value))
    }

    private fun GlanceAppWidgetUnitTest.present(tag: String) {
        onNode(hasTestTag(tag)).assertExists()
    }

    private fun GlanceAppWidgetUnitTest.absent(tag: String) {
        onNode(hasTestTag(tag)).assertDoesNotExist()
    }

    // MARK: - Small: the kicker and the status

    @Test
    fun aWorkoutDayInSmallIsTheKickerTheDotAndTheHeadline() = draw(entry(DayStatus.workout, 3), TodayFamily.small) {
        text("widget-kicker", "TODAY")
        present("widget-dot")
        present("widget-headline")
        absent("widget-steps")
        absent("widget-plan")
        absent("widget-week")
        onAllNodes(hasTestTag("mark-today")).assertCountEquals(0)
    }

    @Test
    fun aDoneDayHasNoDot() = draw(entry(DayStatus.done), TodayFamily.small) {
        present("widget-headline")
        absent("widget-dot")
    }

    @Test
    fun noSnapshotSignsItself() = draw(TodayEntry.empty(date(2)), TodayFamily.large) {
        present("widget-headline")
        absent("widget-dot")
        absent("widget-steps")
        absent("widget-next")
        absent("widget-plan")
        absent("widget-week")
    }

    // MARK: - Medium: the steps and the week strip

    @Test
    fun theMediumCarriesTheStepsAndTheWeekAroundToday() = draw(entry(DayStatus.workout, 3), TodayFamily.medium) {
        text("widget-steps", "27")
        text("widget-steps-unit", "steps")
        present("widget-headline")
        // The seven letters, Monday first.
        listOf("M", "T", "W", "T", "F", "S", "S").forEachIndexed { i, letter -> text("widget-day-${date(i)}", letter) }
        // One mark per state, and today's ring over its planned one.
        onAllNodes(hasTestTag("mark-done")).assertCountEquals(1)
        onAllNodes(hasTestTag("mark-rest")).assertCountEquals(2)
        onAllNodes(hasTestTag("mark-workout")).assertCountEquals(3)
        onAllNodes(hasTestTag("mark-today")).assertCountEquals(1)
        absent("widget-plan")
        absent("widget-next")
        absent("widget-week")
    }

    /** A done day is its own mark: the accent fill, no ring over it. */
    @Test
    fun aDoneTodayCarriesNoRing() = draw(entry(DayStatus.done), TodayFamily.medium) {
        onAllNodes(hasTestTag("mark-done")).assertCountEquals(2)
        onAllNodes(hasTestTag("mark-today")).assertCountEquals(0)
    }

    // MARK: - Large: the next plan, the plan list, the week line

    @Test
    fun aRestDayInLargePointsAtTheNextWorkoutAndListsIt() = draw(entry(DayStatus.rest), TodayFamily.large) {
        absent("widget-dot")
        text("widget-next", "Next: Workout 3 · tomorrow")
        onAllNodes(hasTestTag("widget-plan-name")).assertCountEquals(2)
        onAllNodes(hasTestTag("widget-plan-detail"))[0].assert(hasTextEqualTo("3×12"))
        onAllNodes(hasTestTag("widget-plan-detail"))[1].assert(hasTextEqualTo("3×30 sec per side"))
        present("widget-week")
        absent("widget-steps")
    }

    @Test
    fun aWorkoutDayInLargeHasNoNextLine() = draw(entry(DayStatus.workout, 3), TodayFamily.large) {
        present("widget-dot")
        absent("widget-next")
        onAllNodes(hasTestTag("widget-plan-name")).assertCountEquals(2)
    }

    // MARK: - The words in Russian

    /** The widget's catalog first: "steps" is «ступеней» on iOS's widget and
     *  «ступени» in its app — the app's word here would be the app's screen. */
    @Test
    fun russianReadsTheWidgetsOwnCatalog() = draw(entry(DayStatus.workout, 3), TodayFamily.medium, "ru") {
        text("widget-kicker", "СЕГОДНЯ")
        text("widget-steps-unit", "ступеней")
        text("widget-day-${date(0)}", "П")
    }

    @Test
    fun russianRestDaySaysTheNextDayInRussian() = draw(entry(DayStatus.rest), TodayFamily.large, "ru") {
        text("widget-next", "Следующая: тренировка 3 · завтра")
        onAllNodes(hasTestTag("widget-plan-detail"))[1].assert(hasTextEqualTo("3×30 сек на сторону"))
    }

    // MARK: - The tap

    /** The whole widget opens Today — the reminder's door (MainActivity). */
    @Test
    fun aTapOpensToday() = draw(entry(DayStatus.workout, 3), TodayFamily.small) {
        onAllNodes(hasStartActivityClickAction(MainActivity.openToday(app))).assertCountEquals(1)
    }
}
