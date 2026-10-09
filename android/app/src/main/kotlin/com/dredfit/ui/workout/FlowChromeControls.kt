//
//  The buttons a person taps to change course mid-workout: pause, the skips,
//  "Went differently", and a hold's "Set the time" and Stop. Port of
//  ios/Dredfit/Views/Workout/FlowChrome+Controls.swift — every outline wears
//  `targetStroke` there for the 3:1 a target's boundary owes, and so here.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PauseGlyph
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

/** The pause of the guided blocks (#61) and of a rest that starts the next
 *  set by itself. The identifier carries the STATE, so a localized run can
 *  tell a paused block from a running one. */
@Composable
fun BlockPauseButton(paused: Boolean, onClick: () -> Unit) {
    val c = Theme.colors
    val color = if (paused) c.accentText else c.ink2
    Row(
        Modifier
            .heightIn(min = MinTarget)
            .clip(CircleShape)
            .border(1.5.dp, c.targetStroke, CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(if (paused) "block-resume" else "block-pause")
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        PauseGlyph(paused, color, 12.dp)
        Text(if (paused) tr("Resume") else tr("Pause"), style = dredfitFont(14f, Weight.medium), color = color)
    }
}

/** The per-position escape both guided blocks carry. */
@Composable
fun PositionSkipButton(onClick: () -> Unit) {
    Box(Modifier.heightIn(min = MinTarget).clickable(role = Role.Button, onClick = onClick).padding(horizontal = 8.dp),
        contentAlignment = Alignment.Center) {
        Text(tr("Skip this position"), style = dredfitFont(14f, Weight.medium), color = Theme.colors.ink2)
    }
}

/** The full-width outline escape at the bottom of a block — "Skip warm-up",
 *  "Skip rest", "Skip cool-down" — and the rest's "+N s". The identifier is
 *  always stated: a localized title must never become the name. */
@Composable
fun BlockSkipButton(title: String, tag: String, modifier: Modifier = Modifier, enabled: Boolean = true,
                    description: String? = null, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(18.dp)
    Box(
        modifier
            .heightIn(min = BlockSkipHeight)
            .clip(shape)
            .border(1.5.dp, c.targetStroke, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (description != null) Modifier.semantics { contentDescription = description } else Modifier)
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = dredfitFont(17f, Weight.medium), color = c.ink2, textAlign = TextAlign.Center)
    }
}

/** Named because the rest screen lays its pair out by hand. */
val BlockSkipHeight = 56.dp

/**
 * The two escapes of an exercise: skip the set in front of you, or the rest
 * of the movement. One row while both fit, stacked when they do not —
 * measured rather than assumed, because the same words run longer in German,
 * and a row that truncates the escape hides the way out.
 */
@Composable
fun ExerciseActionsRow(onSkipSet: (() -> Unit)?, skipsProbe: Boolean, escape: Pair<ExerciseEscape, () -> Unit>?,
                       modifier: Modifier = Modifier, enabled: Boolean = true) {
    val c = Theme.colors
    val hint = if (skipsProbe) tr(SkipConfirmation.probeHint) else tr(SkipConfirmation.workingSetHint)
    val skipTitle = tr("Skip this set")
    val escapeTitle = escape?.let { tr(it.first.title) }
    androidx.compose.foundation.layout.FlowRow(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (onSkipSet != null) {
            Box(Modifier.heightIn(min = MinTarget)
                    .clickable(enabled = enabled, role = Role.Button, onClick = onSkipSet)
                    .semantics { stateDescription = hint }
                    .testTag("exercise-skip-set"),
                contentAlignment = Alignment.Center) {
                Text(skipTitle, style = dredfitFont(14.5f), color = c.ink2)
            }
        }
        if (escape != null && escapeTitle != null) {
            Box(Modifier.heightIn(min = MinTarget)
                    .clickable(enabled = enabled, role = Role.Button, onClick = escape.second)
                    .testTag(escape.first.identifier),
                contentAlignment = Alignment.Center) {
                Text(escapeTitle, style = dredfitFont(14.5f), color = c.ink2)
            }
        }
    }
}

/** The look of the two secondary controls above the primary one — the
 *  alternative answer, never a rival to it. */
@Composable
private fun FlowSecondary(title: String, tag: String, hint: String, enabled: Boolean, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(14.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 46.dp)
            .clip(shape)
            .border(1.5.dp, c.targetStroke, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { stateDescription = hint }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = dredfitFont(15.5f, Weight.medium), color = c.ink2)
    }
}

/** "Went differently" — the second control of the pair, ABOVE the primary. */
@Composable
fun WentDifferentlyButton(enabled: Boolean, onClick: () -> Unit) =
    FlowSecondary(tr("Went differently"), "exercise-adjust",
                  tr("Enter what you actually did. The plan follows your numbers."), enabled, onClick)

/** "Set the time" — the ONE thing a hold takes before the effort: a target,
 *  not a report. */
@Composable
fun SetHoldTimeButton(onClick: () -> Unit) =
    FlowSecondary(tr("Set the time"), "hold-set-time",
                  tr("How long every set of this exercise runs. Stop ends one early and records what you held."),
                  enabled = true, onClick)

/** "Stop · 60 s": the primary of a running hold, naming the figure it will
 *  write — nil inside the mis-tap grace, where the tap writes nothing. */
@Composable
fun HoldStopButton(records: Int?, onClick: () -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(18.dp)
    val spoken = if (records != null) tr("Stop, records %lld seconds", records) else tr("Stop")
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(c.ink, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = spoken }
            .testTag("hold-stop"),
        contentAlignment = Alignment.Center,
    ) {
        Text(if (records != null) tr("Stop · %lld s", records) else tr("Stop"),
             style = dredfitFont(17f, Weight.semibold, monospacedDigit = true), color = c.bg)
    }
}

/** A primary-sized slot that keeps its height and takes no tap: the hidden
 *  "Start hold" of a count-in or a side switch. */
@Composable
fun PrimarySpacer() {
    Column(Modifier.fillMaxWidth().heightIn(min = 56.dp)) {}
}
