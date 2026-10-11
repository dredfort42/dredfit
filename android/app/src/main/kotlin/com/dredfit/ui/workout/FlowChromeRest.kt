//
//  What a running set is doing right now, and the ring the rest screen counts
//  down inside. Port of ios/Dredfit/Views/Workout/FlowChrome+Rest.swift.
//

package com.dredfit.ui.workout

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.WorkoutSession

/** The one line under the set dots, in order of precedence: the second
 *  side, an entered actual, or plainly which set is up — with its number
 *  when the sets differ. */
@Composable
fun WorkStatusCaption(secondSide: Boolean, actual: Int?, setIndex: Int, sets: Int, planned: Int, uneven: Boolean) {
    val c = Theme.colors
    val accented = dredfitFont(14f, Weight.semibold)
    when {
        secondSide -> Text(tr("second side"), style = accented, color = c.accentText)
        actual != null -> Text(tr("actual %lld", actual), style = accented, color = c.accentText)
        uneven -> Text(tr("set %lld of %lld · %lld", setIndex + 1, sets, planned), style = accented,
                       color = c.accentText)
        else -> Text(tr("set %lld of %lld", setIndex + 1, sets), style = dredfitFont(14f), color = c.ink2)
    }
}

/**
 * The rest phase. The ring is the primary element, which is why neither
 * control under it is filled: someone who is not recovered must be able to
 * ask for more time about as easily as to cut the rest short. "+15 s" takes a
 * third of the row and Skip two thirds — the thumb comes down on Skip far
 * more often.
 */
@Composable
fun RestRing(remaining: Int, fraction: Float, nextLabel: String, canExtend: Boolean, paused: Boolean,
             onPauseToggle: (() -> Unit)?, onTechnique: () -> Unit, onExtend: () -> Unit, onSkip: () -> Unit) {
    val c = Theme.colors
    // 240 relative to the large title, capped to fit the narrowest screen.
    val ring = minOf(240.dp * LocalDensity.current.fontScale, 330.dp)
    val shown by animateFloatAsState(fraction, tween(1000, easing = LinearEasing), label = "rest")
    val spoken = tr("%lld seconds of rest left", remaining)
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        // No live region: a figure that moves every second must not make the
        // reader talk over itself (iOS's `.updatesFrequently` announces
        // nothing on its own either) — it is there to be asked for.
        Box(Modifier.size(ring).clearAndSetSemantics { contentDescription = spoken },
            contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val line = 7.dp.toPx()
                val inset = line / 2
                val arc = androidx.compose.ui.geometry.Size(size.width - line, size.height - line)
                val topLeft = androidx.compose.ui.geometry.Offset(inset, inset)
                drawArc(c.hairline, 0f, 360f, false, topLeft, arc, style = Stroke(line))
                drawArc(c.accent, -90f, 360f * shown, false, topLeft, arc, style = Stroke(line, cap = StrokeCap.Round))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("$remaining", style = dredfitFont(72f, Weight.heavy, cap = 104f, tracking = -2f, monospacedDigit = true),
                     color = if (paused) c.ink2 else c.ink)
                if (paused) Text(tr("Paused"), style = dredfitFont(15f, Weight.semibold), color = c.accentText)
                else Text(tr("sec"), style = dredfitFont(15f), color = c.ink2)
            }
        }
        Column(Modifier.padding(top = 44.dp), horizontalAlignment = Alignment.CenterHorizontally,
               verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // Two rests look alike and end differently: the one inside a
            // hands-free hold run starts the next set on its own go.
            Kicker(if (onPauseToggle == null) tr("Next up") else tr("Starts by itself"))
            Text(nextLabel, style = dredfitFont(17f, Weight.semibold), color = c.ink, textAlign = TextAlign.Center)
        }
        TechniqueButton(Modifier.padding(top = 16.dp), onClick = onTechnique)
        if (onPauseToggle != null) {
            Box(Modifier.padding(top = 12.dp)) { BlockPauseButton(paused, onPauseToggle) }
        }
        Spacer(Modifier.weight(1f))
        Row(Modifier.fillMaxWidth().padding(bottom = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            // At the cap it greys out instead of disappearing, so the row never
            // jumps out from under the finger.
            BlockSkipButton(tr("+%lld s", WorkoutSession.restExtensionSeconds), tag = "extend-rest",
                            modifier = Modifier.weight(1f).alpha(if (canExtend) 1f else 0.35f), enabled = canExtend,
                            description = tr("Add %lld seconds of rest", WorkoutSession.restExtensionSeconds),
                            onClick = onExtend)
            BlockSkipButton(tr("Skip rest"), tag = "skip-rest", modifier = Modifier.weight(2f), onClick = onSkip)
        }
    }
}
