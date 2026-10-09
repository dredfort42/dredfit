//
//  The level chart: the line of steps, the bands of the breaks, and the tap
//  that opens the nearest record. Port of
//  ios/Dredfit/Views/Progress/StepsChart.swift — Swift Charts there, a Canvas
//  here (no chart library: the app carries no third-party dependency), drawn
//  to the same marks: a 2 dp accent line with a dot on its last point, a
//  zero-based y scale of at least 8 with about three labelled grid lines on the
//  trailing side, three dates under it, and restFill bands behind the line.
//

package com.dredfit.ui.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.FeedbackResult
import com.dredfit.ui.currentLocale
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.theme.isAccessibilitySize
import com.dredfit.ui.tr
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

object StepsChart {

    /** A gap between two adjacent points wide enough for the silent decay to
     *  have run. `costSteps`: the far side is lower AND the session that
     *  produced it cannot be what lowered it (StepsChart.swift). */
    data class BreakBand(val id: Int, val from: Instant, val to: Instant, val days: Int, val costSteps: Boolean)

    /** One record's point. `result`, `ownNumber` and `ownSkips` are the three
     *  ways the returning session can lower a level by itself. */
    data class StepPoint(val id: Int, val date: Instant, val value: Int, val result: FeedbackResult,
                         val ownNumber: Boolean, val ownSkips: Boolean)

    /** The y domain: zero-based — scaling from the lowest session would turn
     *  a quiet fortnight into a cliff — and never under 8. */
    fun yMax(points: List<StepPoint>): Int = maxOf(points.maxOfOrNull { it.value } ?: 1, 8)

    /** About three grid values over 0…max, on a 1-2-5 step. */
    fun yTicks(max: Int): List<Int> {
        val raw = max / 3.0
        val magnitude = 10.0.pow(kotlin.math.floor(log10(raw)))
        val step = listOf(1.0, 2.0, 5.0, 10.0).map { it * magnitude }.first { it >= raw }.let { ceil(it).toInt() }
        return (0..max step step).toList()
    }

    /** A label is drawn only when its band is wide enough to hold it — the
     *  fractions StepsChart.swift measured, wider at accessibility sizes. */
    fun labelFits(band: BreakBand, points: List<StepPoint>, accessibilitySize: Boolean): Boolean {
        val first = points.firstOrNull()?.date ?: return false
        val last = points.last().date
        if (last <= first) return false
        val needed = if (accessibilitySize) 0.33 else 0.155
        val span = (last.toEpochMilli() - first.toEpochMilli()).toDouble()
        return (band.to.toEpochMilli() - band.from.toEpochMilli()) / span >= needed
    }

    /** Nearest point in x rather than a hit box on the 2 dp line. */
    fun nearest(points: List<StepPoint>, tapped: Instant): StepPoint? =
        points.minByOrNull { abs(it.date.toEpochMilli() - tapped.toEpochMilli()) }
}

@Composable
fun StepsChart(points: List<StepsChart.StepPoint>, bands: List<StepsChart.BreakBand>, zone: ZoneId,
               modifier: Modifier = Modifier, onOpen: (Instant) -> Unit) {
    val c = Theme.colors
    if (points.size < 2) {
        Box(modifier.fillMaxSize().border(1.5.dp, c.hairline, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
            Text(tr("The chart will appear after a couple of workouts"), style = dredfitFont(12.5f), color = c.ink2,
                 textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp))
        }
        return
    }
    val measurer = rememberTextMeasurer()
    // caption2 on iOS: 11 pt, scaled with the reader's setting.
    val axisStyle = dredfitFont(11f).copy(color = c.ink2)
    val bandStyle = dredfitFont(11f).copy(color = c.ink)
    val locale = currentLocale()
    val dateFormat = DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd"), locale)
    val accessibility = isAccessibilitySize()
    val bandLabels = bands.associate { it.id to tr("%lld days", it.days) }
    val yMax = StepsChart.yMax(points)
    val ticks = StepsChart.yTicks(yMax)
    val dates = StepsChart.xAxisDates(points)
    val first = points.first().date.toEpochMilli()
    val span = (points.last().date.toEpochMilli() - first).coerceAtLeast(1)

    BoxWithConstraints(modifier.fillMaxSize()) {
    // TalkBack's view of the chart, what Swift Charts hands VoiceOver for
    // free: one element per point, in order, its date as the axis prints it
    // and its value, and the double-tap opens that workout's record — the
    // same thing a tap on the chart does. Invisible and with no pointer input
    // of its own, so a finger still reaches the Canvas underneath.
    val yWidthPx = ticks.maxOf { measurer.measure(it.toString(), axisStyle).size.width } +
        with(LocalDensity.current) { 6.dp.toPx() }
    val plotWidthPx = constraints.maxWidth - yWidthPx
    points.forEachIndexed { i, pt ->
        val label = dateFormat.format(pt.date.atZone(zone)) + ", " + tr("%lld steps", pt.value)
        val x = plotWidthPx * (pt.date.toEpochMilli() - first).toFloat() / span
        Box(Modifier.offset { IntOffset((x - 6.dp.toPx()).roundToInt(), 0) }.width(12.dp).fillMaxHeight()
                .semantics {
                    contentDescription = label
                    onClick { onOpen(pt.date); true }
                    testTag = "chart-point-$i"
                })
    }
    Canvas(Modifier.fillMaxSize().testTag("steps-chart").pointerInput(points) {
        detectTapGestures { tap ->
            val yWidth = ticks.maxOf { measurer.measure(it.toString(), axisStyle).size.width } + 6.dp.toPx()
            val plotWidth = size.width - yWidth
            val fraction = (tap.x / plotWidth).coerceIn(0f, 1f)
            val tapped = Instant.ofEpochMilli(first + (span * fraction).toLong())
            StepsChart.nearest(points, tapped)?.let { onOpen(it.date) }
        }
    }) {
        val yLabels = ticks.map { measurer.measure(it.toString(), axisStyle) }
        val yWidth = yLabels.maxOf { it.size.width } + 6.dp.toPx()
        val xLabels = dates.map { measurer.measure(dateFormat.format(it.atZone(zone)), axisStyle) }
        val xHeight = (xLabels.maxOfOrNull { it.size.height } ?: 0) + 4.dp.toPx()
        val plotWidth = size.width - yWidth
        val plotHeight = size.height - xHeight
        fun x(date: Instant) = plotWidth * (date.toEpochMilli() - first).toFloat() / span
        fun y(value: Int) = plotHeight * (1f - value.toFloat() / yMax)

        // Behind the line and meaning nothing on its own: without a band the
        // decay's drop appears inside a workout the athlete completed.
        for (band in bands) {
            val left = x(band.from)
            val right = x(band.to)
            drawRect(c.restFill, Offset(left, 0f), Size(right - left, plotHeight))
            if (StepsChart.labelFits(band, points, accessibility)) {
                val label = measurer.measure(bandLabels.getValue(band.id), bandStyle)
                drawText(label, topLeft = Offset((left + right - label.size.width) / 2, (plotHeight - label.size.height) / 2))
            }
        }
        for ((i, tick) in ticks.withIndex()) {
            val ty = y(tick)
            drawLine(c.hairline, Offset(0f, ty), Offset(plotWidth, ty), 1.dp.toPx())
            val label = yLabels[i]
            // Centred on its grid line, but never below the plot's floor:
            // the "0" would otherwise reach down into the date labels' band.
            drawText(label, topLeft = Offset(plotWidth + 6.dp.toPx(),
                                             (ty - label.size.height / 2).coerceAtMost(plotHeight - label.size.height).coerceAtLeast(0f)))
        }
        val line = Path()
        points.forEachIndexed { i, pt ->
            if (i == 0) line.moveTo(x(pt.date), y(pt.value)) else line.lineTo(x(pt.date), y(pt.value))
        }
        drawPath(line, c.accent, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        val last = points.last()
        drawCircle(c.accent, radius = 4.dp.toPx(), center = Offset(x(last.date), y(last.value)))

        // A label grows right from its date, but the last one grows left —
        // StepsChartAxis.kt. A middle label that would run into the last one
        // is left out rather than overprinted.
        val lastLeft = xLabels.lastOrNull()?.let { plotWidth - it.size.width } ?: plotWidth
        for ((i, date) in dates.withIndex()) {
            val label = xLabels[i]
            val left = when (StepsChart.xLabelAnchor(i, dates.size)) {
                LabelAnchor.trailing -> plotWidth - label.size.width
                LabelAnchor.leading -> x(date)
            }
            val isLast = i == dates.size - 1
            if (!isLast && dates.size > 1 && left + label.size.width > lastLeft - 4.dp.toPx()) continue
            drawText(label, topLeft = Offset(left.coerceAtLeast(0f), plotHeight + 4.dp.toPx()))
        }
    }
    }
}
