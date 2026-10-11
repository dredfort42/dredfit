//
//  The date axis of the level chart: which dates it asks for, and how each
//  label is anchored. Port of ios/Dredfit/Views/Progress/StepsChart+Axis.swift,
//  plain Kotlin so ProgressChartAxisTest reaches both rules.
//
//  On iOS the anchor is a Swift Charts layout fact (a label that does not fit
//  is DROPPED). Here the chart draws its own labels, and the rule is the
//  same for the same reason: a label grows from its date to the right, and
//  the last date sits on the plot's right edge, beside the trailing y-axis
//  digits — so only the last label is anchored by its trailing edge and
//  grows leftwards, clear of them.
//

package com.dredfit.ui.progress

import java.time.Instant

/** Where a date label stands against its date. */
enum class LabelAnchor { leading, trailing }

/** First, middle and last; dates can coincide, so duplicates collapse. */
fun StepsChart.xAxisDates(points: List<StepsChart.StepPoint>): List<Instant> {
    val first = points.firstOrNull()?.date ?: return emptyList()
    val last = points.last().date
    val mid = points[points.size / 2].date
    val dates = mutableListOf(first)
    if (mid > first && mid < last) dates += mid
    if (last > first) dates += last
    return dates
}

/** Index and count rather than a label, so the rule can be asserted. */
fun StepsChart.xLabelAnchor(index: Int, count: Int): LabelAnchor =
    if (index == count - 1) LabelAnchor.trailing else LabelAnchor.leading
