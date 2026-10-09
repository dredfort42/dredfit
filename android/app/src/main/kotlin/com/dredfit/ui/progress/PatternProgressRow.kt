//
//  One movement's row of the Progress screen: its name, how far along its
//  ladder it stands, and — once picked — what the ladder promises next.
//  Port of ios/Dredfit/Views/Progress/PatternProgressRow.swift; the
//  milestone rule is plain Kotlin below so a unit test reaches it.
//

package com.dredfit.ui.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.dredfit.core.Engine
import com.dredfit.core.EngineConfig
import com.dredfit.core.Library
import com.dredfit.core.Pattern
import com.dredfit.store.AppStore
import com.dredfit.store.nextSetWaitsForThePulls
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.ChevronGlyph
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.theme.isAccessibilitySize
import com.dredfit.ui.tr
import com.dredfit.workout.Words

object PatternProgressRow {

    /** What the ladder promises next: below the top variation the PROBE
     *  that opens the next one; on the top variation a set, until five; a
     *  push's set also waits for the pulls. */
    sealed interface NextMilestone {
        data class Probe(val steps: Int) : NextMilestone
        data class SetIn(val steps: Int) : NextMilestone
        data object SetOncePullsCatchUp : NextMilestone
        data object Ceiling : NextMilestone
    }

    /** Distance to the MILESTONE, not to the ceiling: the ceiling costs its
     *  steps, the crossing one more, and every set taken off comes back
     *  first — so the label lands on the tick the bar draws. */
    fun nextMilestone(store: AppStore, p: Pattern): NextMilestone {
        val position = store.engineState.position(p)
        val steps = Engine.stepsToVariationCeiling(store.engineState, p) + position.cut + 1
        if (position.variation != Library.count(p)) return NextMilestone.Probe(steps)
        if (position.sets >= EngineConfig.setsMax) return NextMilestone.Ceiling
        return if (store.nextSetWaitsForThePulls(p)) NextMilestone.SetOncePullsCatchUp else NextMilestone.SetIn(steps)
    }

    /** "movement" names the whole ladder in this app, so the probe is
     *  named for what it is. */
    fun label(milestone: NextMilestone): Words? = when (milestone) {
        is NextMilestone.Probe -> Words.of("next variation probe in %lld", milestone.steps)
        is NextMilestone.SetIn -> Words.of("+1 set in %lld", milestone.steps)
        NextMilestone.SetOncePullsCatchUp -> Words.of("+1 set once pulling catches up")
        NextMilestone.Ceiling -> null
    }
}

/** The row IS the chart selector: a tap projects the chart above, a second
 *  tap goes back to the total. */
@Composable
fun PatternProgressRow(observedStore: Observed<AppStore>, pattern: Pattern, selected: Boolean, onClick: () -> Unit) {
    val store by observedStore
    val c = Theme.colors
    val steps = Engine.progress(store.engineState, pattern)
    val position = store.engineState.position(pattern)
    val total = Library.count(pattern)
    val shape = RoundedCornerShape(10.dp)
    val rowLabel = tr(pattern.displayName) + ", " + tr("step %lld of %lld", steps, Engine.ladderSpan(pattern))
    val accessibility = isAccessibilitySize()
    Column(
        Modifier.fillMaxWidth().clip(shape).background(if (selected) c.accentSoft else Color.Transparent, shape)
            .clickable(role = Role.Button, onClick = onClick)
            // Colour alone does not reach TalkBack — state has to be a trait.
            .semantics { this.selected = selected }
            .testTag("progress-row-${pattern.rawValue}")
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        // "Squat, 18" was a number with no scale; the bar says nothing to
        // TalkBack, so the head speaks the scale.
        val head = Modifier.clearAndSetSemantics { contentDescription = rowLabel }
        if (accessibility) {
            Column(head, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    PatternName(pattern, Modifier.weight(1f))
                    StepsNumber(steps, selected)
                    Disclosure(selected)
                }
                ProgressBar(pattern, steps, Modifier.fillMaxWidth())
            }
        } else {
            Row(head, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // Wide enough for "Горизонтальный жим" on one line.
                PatternName(pattern, Modifier.width(152.dp))
                ProgressBar(pattern, steps, Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(Modifier.width(44.dp), horizontalArrangement = Arrangement.End) { StepsNumber(steps, selected) }
                    Disclosure(selected)
                }
            }
        }
        if (selected) {
            // ink, not ink2: on the accented fill ink2 is 4.03:1 in light.
            val variation = tr(Library.name(pattern, position.variation))
            val detail = "$variation · ${position.variation}/$total · ${position.sets}×${position.dose}"
            val detailLabel = "$variation, " + tr("variation %lld of %lld", position.variation, total)
            val milestone = PatternProgressRow.label(PatternProgressRow.nextMilestone(store, pattern))?.let { tr(it) }
            // One line while both halves fit it, two when they do not: a long
            // variation name beside the countdown would truncate the dose.
            OneLineOrTwo(gap = 8.dp) {
                Text(detail, style = dredfitFont(11f), color = c.ink, maxLines = if (accessibility) Int.MAX_VALUE else 1,
                     overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { contentDescription = detailLabel })
                milestone?.let {
                    Text(it, style = dredfitFont(11f, monospacedDigit = true), color = c.ink,
                         modifier = Modifier.testTag("progress-milestone"))
                }
            }
        }
    }
}

/** SwiftUI's `ViewThatFits` over an HStack(a, Spacer, b) and a VStack(a, b):
 *  the pair on one line, the second pushed to the trailing edge, while both
 *  fit at their natural width; otherwise one under the other. */
@Composable
private fun OneLineOrTwo(gap: Dp, content: @Composable () -> Unit) {
    Layout(content) { measurables, constraints ->
        val gapPx = gap.roundToPx()
        val loose = constraints.copy(minWidth = 0)
        val natural = measurables.sumOf { it.maxIntrinsicWidth(constraints.maxHeight) } + gapPx * (measurables.size - 1)
        val placeables = measurables.map { it.measure(loose) }
        if (natural <= constraints.maxWidth) {
            val height = placeables.maxOfOrNull { it.height } ?: 0
            layout(constraints.maxWidth, height) {
                placeables.firstOrNull()?.placeRelative(0, 0)
                if (placeables.size > 1) {
                    val last = placeables.last()
                    last.placeRelative(constraints.maxWidth - last.width, height - last.height)
                }
            }
        } else {
            val spacing = 2.dp.roundToPx()
            val height = placeables.sumOf { it.height } + spacing * (placeables.size - 1).coerceAtLeast(0)
            layout(constraints.maxWidth, height) {
                var y = 0
                for (p in placeables) {
                    p.placeRelative(0, y)
                    y += p.height + spacing
                }
            }
        }
    }
}

@Composable
private fun PatternName(p: Pattern, modifier: Modifier) {
    Text(tr(p.displayName), style = dredfitFont(13.5f, Weight.medium), color = Theme.colors.ink, maxLines = 1,
         overflow = TextOverflow.Ellipsis, modifier = modifier)
}

@Composable
private fun StepsNumber(steps: Int, selected: Boolean) {
    val c = Theme.colors
    Text("$steps", style = dredfitFont(13.5f, Weight.semibold, monospacedDigit = true),
         color = if (selected) c.ink else c.ink2, maxLines = 1)
}

/** Down/up rather than the right chevron of Today and Settings: this row
 *  opens nothing, it projects the chart above. */
@Composable
private fun Disclosure(selected: Boolean) {
    ChevronGlyph(Theme.colors.ink2, 11.dp, Modifier.rotate(if (selected) -90f else 90f))
}

/** The pattern's OWN ladder, ticks where each variation begins. */
@Composable
private fun ProgressBar(p: Pattern, steps: Int, modifier: Modifier) {
    val c = Theme.colors
    val span = maxOf(Engine.ladderSpan(p), 1)
    val boundaries = Engine.variationBoundaries(p)
    Canvas(modifier.height(6.dp)) {
        val r = CornerRadius(size.height / 2)
        drawRoundRect(c.hairline, cornerRadius = r)
        val fill = maxOf(size.width * steps / span, if (steps > 0) 6.dp.toPx() else 0f)
        if (fill > 0) drawRoundRect(c.accent, size = Size(minOf(fill, size.width), size.height), cornerRadius = r)
        for (b in boundaries) {
            val x = size.width * b / span
            drawRect(c.bg, Offset(x, (size.height - 8.dp.toPx()) / 2), Size(2.dp.toPx(), 8.dp.toPx()))
        }
    }
}
