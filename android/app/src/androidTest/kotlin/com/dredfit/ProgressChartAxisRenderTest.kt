//
//  The RENDER half of ios/DredfitTests/ProgressChartAxisTests.swift (the rule
//  half is the JVM ProgressChartAxisTest): the date axis under the level
//  chart, measured in ink. Whether every date asked for is DRAWN, clear of
//  the y-axis digits, is a layout fact only pixels settle — the iOS screen
//  asked for three and drew two for a whole release.
//

package com.dredfit

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.dredfit.ui.progress.StepsChart
import com.dredfit.ui.progress.xAxisDates
import com.dredfit.ui.theme.DredfitTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import com.dredfit.core.FeedbackResult
import java.time.Instant
import java.time.ZoneId

@RunWith(AndroidJUnit4::class)
class ProgressChartAxisRenderTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun everyDateTheAxisAsksForIsDrawn() {
        val points = points(listOf(0, 20, 40, 62, 95))
        assertEquals("first, middle and last is the ask this axis makes", 3, StepsChart.xAxisDates(points).size)
        val ink = labelInk(points)
        assertEquals("the axis asked for 3 dates and drew ${ink.labels.size}", 3, ink.labels.size)
        assertTrue("the last label must clear the y-axis digits, not overprint them",
                   ink.labels.last().last <= ink.plotRight)
    }

    /** Two workouts are the least this chart draws at all, and both ends are
     *  labelled — the last one by its trailing edge. */
    @Test
    fun theSmallestChartLabelsBothOfItsEnds() {
        val points = points(listOf(0, 47))
        assertEquals(2, StepsChart.xAxisDates(points).size)
        assertEquals("a two-point chart labels both ends", 2, labelInk(points).labels.size)
    }

    /** The JVM suite's fixture, repeated (the two source sets do not see
     *  each other): a fixed origin, because the labels are dates. */
    private fun points(dayOffsets: List<Int>): List<StepsChart.StepPoint> {
        val origin = Instant.ofEpochSecond(1_780_000_000)
        return dayOffsets.mapIndexed { i, day ->
            StepsChart.StepPoint(id = i, date = origin.plusSeconds(day * 86_400L), value = 3 + i,
                                 result = FeedbackResult.plan, ownNumber = false, ownSkips = false)
        }
    }

    private class Ink(val labels: List<IntRange>, val plotRight: Int)

    /** The chart at the width the screen gives it on a 402 pt iPhone (less
     *  the two 24 dp gutters), on white: everything not white is ink. The
     *  date labels are the bottom-most ink; the y-axis "0" stops at the plot
     *  floor, above them. */
    private fun labelInk(points: List<StepsChart.StepPoint>): Ink {
        compose.setContent {
            DredfitTheme(dark = false) {
                Box(Modifier.size(354.dp, 134.dp).background(Color.White).testTag("chart-box")) {
                    StepsChart(points, emptyList(), ZoneId.of("UTC")) {}
                }
            }
        }
        val pixels = compose.onNodeWithTag("chart-box").captureToImage().toPixelMap()
        val w = pixels.width
        val h = pixels.height
        val density = compose.density.density
        fun isInk(x: Int, y: Int) = pixels[x, y] != Color.White
        val bottom = (h - 1 downTo 0).firstOrNull { y -> (0 until w).any { isInk(it, y) } } ?: return Ink(emptyList(), w)
        val band = maxOf(0, bottom - (11 * density * compose.density.fontScale).toInt())
        val columns = (0 until w).filter { x -> (band..bottom).any { isInk(x, it) } }
        // 8 dp apart or more is a different label: the space inside "Jun 18"
        // is far narrower.
        val gap = (8 * density).toInt()
        val spans = mutableListOf<IntRange>()
        var start = -1
        var previous = -1
        for (c in columns) {
            if (start < 0) start = c else if (c - previous > gap) {
                spans += start..previous
                start = c
            }
            previous = c
        }
        if (start >= 0) spans += start..previous
        // The plot ends where the y-axis column begins: the widest digit
        // column is on the right, so the plot's right edge is the leftmost
        // ink of the y labels — read off the rows above the band.
        val yLabelsLeft = (0 until band).flatMap { y -> (w * 3 / 4 until w).filter { isInk(it, y) && pixels[it, y].red < 0.8f } }
            .minOrNull() ?: w
        return Ink(spans, yLabelsLeft)
    }
}
