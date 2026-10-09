//
//  The month grid. Port of ios/Dredfit/Views/Progress/CalendarScreen.swift:
//  missed days are deliberately unmarked — no ring, no fill, just the date —
//  but not unreadable: the digit is ink2, a text tone. The grid's rule is
//  plain Kotlin below (`monthDays`), the drawing is the composable.
//

package com.dredfit.ui.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppStore
import com.dredfit.store.doneToday
import com.dredfit.store.isRestDay
import com.dredfit.store.nextSession
import com.dredfit.store.nextTrainingDate
import com.dredfit.store.record
import com.dredfit.ui.Observed
import com.dredfit.ui.currentLocale
import com.dredfit.ui.screenDateText
import com.dredfit.ui.theme.ChevronGlyph
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.today.NextWorkoutSheet
import com.dredfit.ui.today.nextTrainingDateLabel
import com.dredfit.ui.tr
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle

object CalendarScreen {

    /** `missed` is distinct from `planned` so past days never carry the
     *  planned ring; `out` is a neighbouring month's filler cell. */
    enum class DayState { done, planned, missed, today, rest, out }

    data class Day(val date: LocalDate, val number: Int, val state: DayState)

    fun shownMonth(store: AppStore, offset: Int): YearMonth =
        YearMonth.from(store.today.atZone(store.zone)).plusMonths(offset.toLong())

    /** Monday-first, padded to whole weeks with the neighbours' days. */
    fun monthDays(store: AppStore, month: YearMonth): List<Day> {
        val zone = store.zone
        val today = store.today.atZone(zone).toLocalDate()
        val first = month.atDay(1)
        val lead = first.dayOfWeek.value - 1   // Monday = 1
        val done = store.records.mapTo(HashSet()) { it.date.atZone(zone).toLocalDate() }
        val days = mutableListOf<Day>()
        for (i in lead downTo 1) {
            val d = first.minusDays(i.toLong())
            days += Day(d, d.dayOfMonth, DayState.out)
        }
        for (n in 1..month.lengthOfMonth()) {
            val d = month.atDay(n)
            val state = when {
                d in done -> DayState.done
                d == today -> DayState.today
                store.isRestDay(d.atStartOfDay(zone).toInstant()) -> DayState.rest
                d.isBefore(today) -> DayState.missed
                else -> DayState.planned
            }
            days += Day(d, n, state)
        }
        var tail = 1L
        while (days.size % 7 != 0) {
            val d = month.atEndOfMonth().plusDays(tail++)
            days += Day(d, d.dayOfMonth, DayState.out)
        }
        return days
    }

    /** The only tappable cell among the non-completed days: the sheet
     *  describes the one computed next workout, nothing else. */
    fun isNextTrainingDay(store: AppStore, day: Day): Boolean =
        (day.state == DayState.planned || day.state == DayState.today) &&
            day.date == store.nextTrainingDate.atZone(store.zone).toLocalDate()

    /** The count under the grid follows the month ON SCREEN. */
    fun completed(store: AppStore, month: YearMonth): Int =
        store.records.count { YearMonth.from(it.date.atZone(store.zone)) == month }

    /** The done card replaces the month's count only on today's month. */
    fun showsDoneCard(store: AppStore, month: YearMonth): Boolean =
        store.doneToday && month == shownMonth(store, 0)
}

@Composable
fun CalendarScreen(observedStore: Observed<AppStore>, modifier: Modifier = Modifier) {
    val store by observedStore
    val c = Theme.colors
    var monthOffset by rememberSaveable { mutableIntStateOf(0) }
    var nextPreviewShown by remember { mutableStateOf(false) }
    var historyRecord by remember { mutableStateOf<WorkoutRecord?>(null) }
    val month = CalendarScreen.shownMonth(store, monthOffset)
    val locale = currentLocale()
    val monthTitle = DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(locale, "LLLLy"), locale)
        .format(month.atDay(1)).replaceFirstChar { it.titlecase(locale) }

    // Inside a scroll, so at large type sizes the legend and the card under
    // the grid stay reachable.
    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 12.dp)) {
        Kicker(tr("Calendar"), Modifier.padding(top = 18.dp))
        Row(Modifier.fillMaxWidth().padding(top = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(monthTitle, style = dredfitFont(19f, Weight.bold), color = c.ink, modifier = Modifier.weight(1f))
            // 44 dp targets: the bare glyphs are far smaller.
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                MonthStep(tr("Previous month"), back = true, tag = "month-previous") { monthOffset -= 1 }
                MonthStep(tr("Next month"), back = false, tag = "month-next") { monthOffset += 1 }
            }
        }
        // shortStandalone, Monday first.
        Row(Modifier.fillMaxWidth().padding(top = 20.dp)) {
            for (d in DayOfWeek.entries) {
                Text(d.getDisplayName(TextStyle.SHORT_STANDALONE, locale).replaceFirstChar { it.titlecase(locale) },
                     style = dredfitFont(11f, Weight.semibold), color = c.ink2,
                     textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.weight(1f))
            }
        }
        Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            for (week in CalendarScreen.monthDays(store, month).chunked(7)) {
                Row(Modifier.fillMaxWidth()) {
                    for (day in week) {
                        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                            DayCell(store, day,
                                    open = when {
                                        day.state == CalendarScreen.DayState.done -> {
                                            { historyRecord = store.record(day.date.atStartOfDay(store.zone).toInstant()) }
                                        }
                                        CalendarScreen.isNextTrainingDay(store, day) -> { { nextPreviewShown = true } }
                                        else -> null
                                    })
                        }
                    }
                }
            }
        }
        Legend(Modifier.padding(top = 22.dp))
        if (CalendarScreen.showsDoneCard(store, month)) {
            DoneCard(store, Modifier.padding(top = 20.dp)) { nextPreviewShown = true }
        } else {
            MonthStat(store, month, monthTitle, Modifier.padding(top = 20.dp))
        }
    }
    if (nextPreviewShown) NextWorkoutSheet(observedStore) { nextPreviewShown = false }
    historyRecord?.let { HistorySheet(observedStore, it) { historyRecord = null } }
}

@Composable
private fun MonthStep(label: String, back: Boolean, tag: String, onClick: () -> Unit) {
    // ink2, not ink3: interactive controls need 3:1.
    Box(Modifier.size(MinTarget).clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }.testTag(tag),
        contentAlignment = Alignment.Center) {
        ChevronGlyph(Theme.colors.ink2, 14.dp, Modifier.rotate(if (back) 180f else 0f))
    }
}

@Composable
private fun DayCell(store: AppStore, day: CalendarScreen.Day, open: (() -> Unit)?) {
    val c = Theme.colors
    val state = day.state
    val label = when (state) {
        CalendarScreen.DayState.done -> screenDateText(day.instant(store), store.zone) + ", " + tr("completed")
        CalendarScreen.DayState.planned -> screenDateText(day.instant(store), store.zone) + ", " + tr("planned")
        CalendarScreen.DayState.today -> screenDateText(day.instant(store), store.zone) + ", " + tr("today")
        CalendarScreen.DayState.rest -> screenDateText(day.instant(store), store.zone) + ", " + tr("rest day")
        // Just the date: TalkBack gets the same silence about a missed day.
        CalendarScreen.DayState.missed, CalendarScreen.DayState.out -> screenDateText(day.instant(store), store.zone)
    }
    val foreground = when (state) {
        // bg, not white: the digit sits on the ink fill and flips with it.
        CalendarScreen.DayState.done -> c.bg
        CalendarScreen.DayState.planned, CalendarScreen.DayState.today -> c.ink
        CalendarScreen.DayState.rest, CalendarScreen.DayState.missed -> c.ink2
        // Filler cells of the neighbouring months: padding, drawn faintly.
        CalendarScreen.DayState.out -> c.hairline
    }
    var cell = Modifier.size(MinTarget)
    if (open != null) cell = cell.clip(CircleShape).clickable(role = Role.Button, onClick = open)
    cell = if (state == CalendarScreen.DayState.out) cell.semantics { hideFromAccessibility() }
    // The tag inside the block: a testTag modifier after it would be cleared.
    else cell.clearAndSetSemantics { contentDescription = label; testTag = "day-${day.number}" }
    Box(cell, contentAlignment = Alignment.Center) {
        Box(Modifier.size(36.dp).then(medallion(state)), contentAlignment = Alignment.Center) {
            Text("${day.number}", style = dredfitFont(15f, if (state == CalendarScreen.DayState.today) FontWeight.Bold else FontWeight.Normal,
                                                     monospacedDigit = true),
                 color = foreground, maxLines = 1)
        }
    }
}

@Composable
private fun medallion(state: CalendarScreen.DayState): Modifier {
    val c = Theme.colors
    return when (state) {
        CalendarScreen.DayState.done -> Modifier.background(c.ink, CircleShape)
        CalendarScreen.DayState.planned -> Modifier.border(1.5.dp, c.ink3, CircleShape)
        CalendarScreen.DayState.today -> Modifier.border(2.dp, c.accent, CircleShape)
        // restFill, not cardBG: cardBG on white is 1.07:1.
        CalendarScreen.DayState.rest -> Modifier.background(c.restFill, CircleShape)
        CalendarScreen.DayState.missed, CalendarScreen.DayState.out -> Modifier
    }
}

private fun CalendarScreen.Day.instant(store: AppStore) = date.atStartOfDay(store.zone).toInstant()

/** One row while the four fit it, two by two when they do not — the
 *  language decides this as much as the type size. */
@Composable
private fun Legend(modifier: Modifier) {
    val c = Theme.colors
    Layout({
        LegendItem(tr("completed")) { drawCircle(c.ink) }
        LegendItem(tr("planned")) { drawCircle(c.ink3, style = Stroke(1.5.dp.toPx()), radius = size.minDimension / 2 - 0.75.dp.toPx()) }
        LegendItem(tr("rest day")) { drawCircle(c.restFill) }
        LegendItem(tr("today")) { drawCircle(c.accent, style = Stroke(2.dp.toPx()), radius = size.minDimension / 2 - 1.dp.toPx()) }
    }, modifier.fillMaxWidth()) { measurables, constraints ->
        val gap = 16.dp.roundToPx()
        val items = measurables.map { it.measure(constraints.copy(minWidth = 0)) }
        val oneRow = items.sumOf { it.width } + gap * (items.size - 1)
        if (oneRow <= constraints.maxWidth) {
            val height = items.maxOf { it.height }
            layout(constraints.maxWidth, height) {
                var x = (constraints.maxWidth - oneRow) / 2
                for (p in items) {
                    p.placeRelative(x, (height - p.height) / 2)
                    x += p.width + gap
                }
            }
        } else {
            val rows = items.chunked(2)
            val rowGap = 8.dp.roundToPx()
            val widest = rows.maxOf { r -> r.sumOf { it.width } + gap * (r.size - 1) }
            val heights = rows.map { r -> r.maxOf { it.height } }
            layout(constraints.maxWidth, heights.sum() + rowGap * (rows.size - 1)) {
                var y = 0
                val left = ((constraints.maxWidth - widest) / 2).coerceAtLeast(0)
                for ((i, r) in rows.withIndex()) {
                    var x = left
                    for (p in r) {
                        p.placeRelative(x, y)
                        x += p.width + gap
                    }
                    y += heights[i] + rowGap
                }
            }
        }
    }
}

@Composable
private fun LegendItem(label: String, mark: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Canvas(Modifier.size(13.dp), onDraw = mark)
        Text(label, style = dredfitFont(12.5f), color = Theme.colors.ink2)
    }
}

@Composable
private fun DoneCard(store: AppStore, modifier: Modifier, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(20.dp)
    Row(modifier.fillMaxWidth().clip(shape).background(c.ink, shape).clickable(role = Role.Button, onClick = onClick)
            .testTag("calendar-done-card").padding(horizontal = 20.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(tr("Completed today ✓"), style = dredfitFont(16f, Weight.semibold), color = c.bg)
            Text(tr("Next: workout %lld · %@", store.nextSession.sessionNumber, nextTrainingDateLabel(store)),
                 style = dredfitFont(13f), color = c.bg.copy(alpha = 0.6f))
        }
        ChevronGlyph(c.bg.copy(alpha = 0.6f), 14.dp)
    }
}

@Composable
private fun MonthStat(store: AppStore, month: YearMonth, monthTitle: String, modifier: Modifier) {
    val c = Theme.colors
    val shape = RoundedCornerShape(16.dp)
    Row(modifier.fillMaxWidth().background(c.cardBG, shape).padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically) {
        // The count follows the month on screen, so the label must too.
        Text(if (month == CalendarScreen.shownMonth(store, 0)) tr("This month") else monthTitle,
             style = dredfitFont(13.5f), color = c.ink2, modifier = Modifier.weight(1f))
        Text(tr("%lld completed", CalendarScreen.completed(store, month)),
             style = dredfitFont(15f, Weight.semibold, monospacedDigit = true), color = c.ink,
             modifier = Modifier.testTag("month-completed"))
    }
}
