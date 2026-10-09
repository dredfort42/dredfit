//
//  Every set of a finished hold movement on one screen, the last one a tap
//  from being corrected — and under them what the next plan will be and the
//  one control that raises it. Port of
//  ios/Dredfit/Views/Workout/ExerciseSummary.swift: TWO TENSES, TWO BLOCKS —
//  the cards are the past, the block under them the future, and only the
//  future wears the accent.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.EngineConfig
import com.dredfit.core.LoadUnit
import com.dredfit.core.SessionExercise
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.HeldSet
import com.dredfit.workout.NextTimeBlock
import com.dredfit.workout.RaiseLabel

/** One tappable number. A card that is not correctable is inert, without
 *  the outline that says "tap me" — it stays in the tree so a test can read it. */
@Composable
fun HeldSetCard(held: HeldSet, onEdit: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(16.dp)
    val spoken = if (held.approximate) {
        tr("set %lld, approximately %lld seconds, planned %lld", held.index + 1, held.seconds, held.planned)
    } else {
        tr("set %lld, %lld seconds, planned %lld", held.index + 1, held.seconds, held.planned)
    }
    Column(
        Modifier
            .widthIn(min = 78.dp)
            .heightIn(min = 72.dp)
            .background(c.cardBG, shape)
            .border(1.5.dp, if (held.correctable) c.targetStroke else c.cardBG, shape)
            .clickable(role = Role.Button) { if (held.correctable) onEdit() }
            .semantics { contentDescription = spoken }
            .testTag("summary-set-${held.index + 1}")
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        // The "≈" in the number's own colour: a mark that says "this figure is
        // an estimate" is not decoration.
        Text(if (held.approximate) "≈${held.seconds}" else "${held.seconds}",
             style = dredfitFont(34f, Weight.heavy, cap = 46f, monospacedDigit = true), color = c.ink)
        Text(tr("set %lld", held.index + 1), style = dredfitFont(12f, Weight.medium, monospacedDigit = true), color = c.ink2)
        // THE PLAN ON EVERY CARD: the comparison is the reader's to make.
        Text(tr("plan %lld", held.planned), style = dredfitFont(12f, Weight.semibold, monospacedDigit = true), color = c.ink)
        if (held.approximate) Text(tr("stopped by hand"), style = dredfitFont(12f, Weight.medium), color = c.ink2)
    }
}

/** The row of cards: one line while they fit, wrapping when they do not. */
@Composable
fun HeldSetsRow(sets: List<HeldSet>, onEdit: (Int) -> Unit) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (held in sets) HeldSetCard(held) { onEdit(held.index) }
    }
}

/**
 * What the next plan for this movement will be, and the stepper that adds to
 * it — the only future tense on the screen, and the only accent. ONE
 * SENTENCE THAT CHANGES: each tap rewrites the plan in the sentence itself.
 */
@Composable
fun NextTimeBlockCard(exercise: SessionExercise, steps: Int, factEntered: Boolean,
                      preview: (Int) -> SessionExercise?, onChange: (Int) -> Unit) {
    val c = Theme.colors
    val planned = preview(steps)
    val next = preview(steps + 1)
    // The grid's ceiling parks the raise: one more step would set the same plan.
    val atCeiling = planned == null || next == null || NextTimeBlock.samePlan(planned, next)
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(if (steps > 0) c.accentSoft else c.cardBG, shape)
            .border(1.5.dp, if (steps > 0) c.accent else c.hairline, shape)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(tr("Next time").uppercase(), style = dredfitFont(11f, Weight.heavy, tracking = 0.6f),
             color = if (steps > 0) c.ink else c.accentText, modifier = Modifier.testTag("summary-next-time"))
        if (planned != null) {
            val what = tr(NextTimeBlock.planWords(planned, exercise))
            // With a fact entered the sentence is the plan; without one the
            // number is not a promise until the rating is given.
            Text(if (factEntered) tr("The app will set %@.", what)
                 else tr("The app will set %@ if you rate the workout “on plan”.", what),
                 style = dredfitFont(14f, monospacedDigit = true), color = c.ink,
                 modifier = Modifier.testTag("summary-next-plan"))
        }
        if (steps == 0 && atCeiling) {
            // A sentence that says why, instead of a "+" dead on arrival.
            Text(tr("This is the most for this movement."), style = dredfitFont(14f), color = c.ink2,
                 modifier = Modifier.testTag("summary-next-max"))
        } else {
            RaiseStepper(exercise.unit, steps, canAdd = steps < EngineConfig.raiseStepsMax && !atCeiling, onChange)
        }
    }
}

/** −/value/+ for the addition. No OK: the value is standing, and the
 *  sentence above already shows the consequence. */
@Composable
private fun RaiseStepper(unit: LoadUnit, steps: Int, canAdd: Boolean, onChange: (Int) -> Unit) {
    val c = Theme.colors
    val spoken = tr(RaiseLabel.spoken(steps, unit))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically) {
        RaiseButton(minus = true, enabled = steps > 0) { onChange(steps - 1) }
        Text(tr(RaiseLabel.text(steps, unit)), style = dredfitFont(22f, Weight.heavy, monospacedDigit = true),
             color = c.ink, maxLines = 1, softWrap = false, textAlign = TextAlign.Center,
             modifier = Modifier.widthIn(min = 64.dp).semantics { contentDescription = spoken }.testTag("raise-value"))
        RaiseButton(minus = false, enabled = canAdd) { onChange(steps + 1) }
    }
}

/** The panel's own stepper look, with the same 62 × 68 hit shape over the
 *  44 dp ring (#251). Dimmed AND disabled at a bound. */
@Composable
private fun RaiseButton(minus: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val c = Theme.colors
    val label = if (minus) tr("Fewer") else tr("More")
    Box(Modifier.size(MinTarget), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .requiredSize(62.dp, 68.dp)
                .alpha(if (enabled) 1f else 0.3f)
                .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
                .semantics { contentDescription = label }
                .testTag(if (minus) "raise-minus" else "raise-plus"),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.size(MinTarget)) {
                drawCircle(c.targetStroke, radius = size.minDimension / 2 - 0.75.dp.toPx(), style = Stroke(1.5.dp.toPx()))
                val half = 6.5.dp.toPx()
                val stroke = 2.dp.toPx()
                drawLine(c.ink, center.copy(x = center.x - half), center.copy(x = center.x + half), stroke)
                if (!minus) drawLine(c.ink, center.copy(y = center.y - half), center.copy(y = center.y + half), stroke)
            }
        }
    }
}
