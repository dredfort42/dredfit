//
//  One line of a plan. Port of ios/Dredfit/Views/Today/ExerciseRow.swift:
//  the notes under the row are the statics of the SwiftUI view there; here
//  they are plain Kotlin returning `Words` (`ExerciseRow`), so a JVM unit test
//  reaches the rules, and the row composable (`ExerciseRowView`) resolves them
//  with `tr`. Which facts hold is the store's (`aSetJustCameBack`,
//  `setsJustHeldBackByThePulls`); these own the words.
//

package com.dredfit.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.unit.dp
import com.dredfit.core.LoadUnit
import com.dredfit.core.SessionExercise
import com.dredfit.ui.theme.ChevronGlyph
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.RaiseLabel
import com.dredfit.workout.Words

object ExerciseRow {

    fun note(setCameBack: Boolean): Words? = if (setCameBack) Words.of("A set is back.") else null

    /** A probing row's `sets` is already one lower — the probe replaces the
     *  last of them — so the row names the set standing after it, and the
     *  movement it is. */
    fun probeNote(exercise: SessionExercise): Words? {
        val probe = exercise.probe ?: return null
        return Words.keyed("plan.probeNote", "Then a probe: one set of %@ · %@",
                           Words.name(probe.name), Words.display(probe))
    }

    /** About the NAME: the athlete's own handle stands alone; the other
     *  movers are not named, since a guess at one would be wrong about the rest. */
    fun variationNote(easedByHand: Boolean, dropped: Boolean): Words? = when {
        easedByHand -> Words.keyed("plan.easedByHand", "You made this one easier.")
        dropped -> Words.keyed("plan.variationDropped", "An easier variation than last time.")
        else -> null
    }

    /** The part of this plan the person asked for on the last summary. */
    fun raisedNote(steps: Int, unit: LoadUnit): Words? =
        if (steps > 0) Words.keyed("plan.raised", "%@ — your addition", RaiseLabel.text(steps, unit)) else null

    /** A push the pull slot's cap took sets from: names the pulls, never a
     *  row on screen, and "fewer" — the cap can take more than one set. */
    fun pullsNote(heldBack: Boolean): Words? =
        if (heldBack) Words.keyed("plan.heldBackByPulls", "Fewer sets for now — pushes keep pace with your pulls.")
        else null

    /** All of them, in reading order: the name, the number, what stands after
     *  both. The defaults mean "no claim", as on iOS. */
    fun notes(exercise: SessionExercise, setCameBack: Boolean, easedByHand: Boolean = false,
              variationDropped: Boolean = false, raisedSteps: Int = 0,
              heldBackByPulls: Boolean = false): List<Words> =
        listOfNotNull(variationNote(easedByHand, variationDropped),
                      raisedNote(raisedSteps, exercise.unit),
                      note(setCameBack),
                      pullsNote(heldBackByPulls),
                      probeNote(exercise))
}

/**
 * The row: the name (with the "new variation" pill INLINE at its end, so it
 * wraps with the last word instead of pushing the load off screen — the
 * longest catalog name is wider than the column by itself), the load, and
 * the notes under the number, one line each, in reading order.
 */
@Composable
fun ExerciseRowView(exercise: SessionExercise, badge: String?, notes: List<Words>, modifier: Modifier = Modifier) {
    val c = Theme.colors
    Column(modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NameWithBadge(tr(exercise.name), badge, Modifier.weight(1f))
            Text(shortLoad(exercise), style = dredfitFont(15.5f, monospacedDigit = true), color = c.ink2,
                 modifier = Modifier.padding(start = 8.dp))
            Box(Modifier.padding(start = 6.dp)) { ChevronGlyph(c.ink3.copy(alpha = 0.7f), 12.dp) }
        }
        for (note in notes) {
            Text(tr(note), style = dredfitFont(12.5f), color = c.ink2, modifier = Modifier.fillMaxWidth())
        }
    }
}

/** The pill is the words on an accentSoft capsule in `ink` — accentText on
 *  that fill is 4.20:1 in the dark scheme (I-21). An inline placeholder sized
 *  to the measured words, so it rides the name's last line. */
@Composable
private fun NameWithBadge(name: String, badge: String?, modifier: Modifier) {
    val c = Theme.colors
    val style = dredfitFont(16.5f, Weight.medium)
    if (badge == null) {
        Text(name, style = style, color = c.ink, modifier = modifier)
        return
    }
    val pillStyle = dredfitFont(11f, Weight.semibold)
    val measured = rememberTextMeasurer().measure(badge, pillStyle)
    val density = LocalDensity.current
    val width = with(density) { (measured.size.width + 16.dp.roundToPx()).toSp() }
    val height = with(density) { (measured.size.height + 4.dp.roundToPx()).toSp() }
    val text = buildAnnotatedString {
        append(name)
        append(" ")
        appendInlineContent("badge", badge)
    }
    val inline = mapOf("badge" to InlineTextContent(Placeholder(width, height, PlaceholderVerticalAlign.TextCenter)) {
        Box(Modifier.fillMaxSize().background(c.accentSoft, CircleShape), contentAlignment = Alignment.Center) {
            Text(badge, style = pillStyle, color = c.ink, maxLines = 1)
        }
    })
    Text(text, style = style, color = c.ink, inlineContent = inline,
         modifier = modifier.semantics { contentDescription = "$name, $badge" })
}

/** "3 × 12", "9-8-8 /side", "3 × 40 s": an uneven plan spells its sets out —
 *  where the sub-step becomes visible. Explicit keys, as on iOS. */
@Composable
private fun shortLoad(ex: SessionExercise): String {
    val side = if (ex.perSide) tr(" /side") else ""
    val loads = ex.loads
    if (loads != null) {
        val spelled = loads.joinToString("-")
        return when (ex.unit) {
            LoadUnit.reps -> tr("plan.perSet", spelled, side)
            LoadUnit.hold -> tr("plan.perSetHold", spelled, side)
        }
    }
    return when (ex.unit) {
        LoadUnit.reps -> tr("%lld × %lld%@", ex.sets, ex.load, side)
        LoadUnit.hold -> tr("%lld × %lld s%@", ex.sets, ex.load, side)
    }
}
