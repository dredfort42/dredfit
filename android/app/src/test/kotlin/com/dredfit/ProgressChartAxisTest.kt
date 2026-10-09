//
//  Port of ios/DredfitTests/ProgressChartAxisTests.swift, its rule half: the
//  dates the axis asks for and how each label is anchored
//  (ui/progress/StepsChartAxis.kt). The two RENDER tests — every date asked
//  for is drawn, and the last clears the y-axis digits — measure ink on a
//  device: androidTest/…/ProgressChartAxisRenderTest.kt. Their ask
//  (`xAxisDates` count) is pinned here as well.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.ui.progress.LabelAnchor
import com.dredfit.ui.progress.StepsChart
import com.dredfit.ui.progress.xAxisDates
import com.dredfit.ui.progress.xLabelAnchor
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals

class ProgressChartAxisTest {

    /** Pinned, not derived: a "fix" that stops asking for the last date
     *  would make the axis honest by deleting the information. */
    @Test
    fun everyDateTheAxisAsksForIsDrawn() {
        assertEquals(3, StepsChart.xAxisDates(points(listOf(0, 20, 40, 62, 95))).size,
                     "first, middle and last is the ask this axis makes")
    }

    @Test
    fun theSmallestChartLabelsBothOfItsEnds() {
        assertEquals(2, StepsChart.xAxisDates(points(listOf(0, 47))).size)
    }

    /** Anchoring every label by its trailing edge pushes the FIRST one off
     *  the left edge — so only the last. */
    @Test
    fun onlyTheLastLabelIsAnchoredByItsTrailingEdge() {
        assertEquals(LabelAnchor.leading, StepsChart.xLabelAnchor(index = 0, count = 3))
        assertEquals(LabelAnchor.leading, StepsChart.xLabelAnchor(index = 1, count = 3))
        assertEquals(LabelAnchor.trailing, StepsChart.xLabelAnchor(index = 2, count = 3))
        assertEquals(LabelAnchor.trailing, StepsChart.xLabelAnchor(index = 1, count = 2))
    }

    companion object {
        /** A fixed origin: the labels are dates. */
        fun points(dayOffsets: List<Int>): List<StepsChart.StepPoint> {
            val origin = Instant.ofEpochSecond(1_780_000_000)
            return dayOffsets.mapIndexed { i, day ->
                StepsChart.StepPoint(id = i, date = origin.plusSeconds(day * 86_400L), value = 3 + i,
                                     result = FeedbackResult.plan, ownNumber = false, ownSkips = false)
            }
        }
    }
}
