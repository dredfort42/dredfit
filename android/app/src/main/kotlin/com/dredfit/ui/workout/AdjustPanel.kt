//
//  The inline actual adjuster: −/value/+ and OK. Port of
//  ios/Dredfit/Views/Workout/AdjustPanel.swift — the steppers, their
//  press-and-hold repeat and their hit shape keep its numbers and reasons.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.LoadUnit
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.SetFacts
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

object AdjustPanel {
    /** How long a finger stays down before the panel counts on its own —
     *  long enough that no ordinary tap trips it. */
    const val repeatDelayMs = 450L
    const val repeatIntervalMs = 120L
    /** After a second of holding the person is travelling, not picking. */
    const val repeatFastIntervalMs = 60L
    const val stepsBeforeFast = 8

    /** One rep, or FIVE seconds: a hold is set on the grid it is planned on.
     *  A number off the grid — a hand-stopped 38 s — moves to the next grid
     *  line in the tapped direction, so the first tap lands where every
     *  later one will. */
    fun holdStep(value: Int, dir: Int): Int {
        val grid = 5
        if (dir > 0) return (value / grid + 1) * grid
        return if (value % grid == 0) value - grid else (value / grid) * grid
    }

    /** One tap, clamped to the bounds. */
    fun bump(value: Int, dir: Int, unit: LoadUnit, bounds: IntRange): Int {
        val stepped = if (unit == LoadUnit.hold) holdStep(value, dir) else value + dir
        return stepped.coerceIn(bounds.first, bounds.last)
    }
}

/**
 * The panel. `range` is narrower than the corridor when the caller knows one
 * (the hold summary's `summaryRange`); null is the corridor itself.
 */
@Composable
fun AdjustPanel(value: Int, unit: LoadUnit, range: IntRange?, onChange: (Int) -> Unit, onConfirm: () -> Unit) {
    val c = Theme.colors
    val bounds = range ?: SetFacts.corridor(unit)
    Row(
        Modifier
            .fillMaxWidth()
            .background(c.cardBG, RoundedCornerShape(18.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Stepper(minus = true, value, unit, bounds, onChange)
        // ONE line whatever the unit's word is: between two 44 dp targets and
        // OK, "10 сек" at 26 heavy would otherwise break into two lines.
        Text(if (unit == LoadUnit.hold) tr("%lld s", value) else "$value",
             style = dredfitFont(26f, Weight.heavy, monospacedDigit = true), color = c.ink,
             maxLines = 1, softWrap = false, textAlign = TextAlign.Center,
             modifier = Modifier.widthIn(min = 76.dp))
        Stepper(minus = false, value, unit, bounds, onChange)
        // Named, like the steppers: "OK" is also what a system alert calls its
        // button, so a query for the label can resolve to something else.
        Box(
            Modifier
                .background(c.ink, CircleShape)
                .clickable(role = Role.Button, onClick = onConfirm)
                .padding(horizontal = 22.dp, vertical = 10.dp)
                .testTag("adjust-confirm"),
        ) {
            Text(tr("OK"), style = dredfitFont(15f, Weight.semibold), color = c.bg, maxLines = 1)
        }
    }
}

/**
 * A 44 dp ring — the ring IS the button, so it wears `targetStroke` — under a
 * 62 × 68 dp hit shape (#251): a thumb reaching across the phone lands at the
 * ring's edge and must not miss there again on every repeat. Press and hold
 * repeats; the tap that ends a hold is swallowed, or it would add one more.
 */
@Composable
private fun Stepper(minus: Boolean, value: Int, unit: LoadUnit, bounds: IntRange, onChange: (Int) -> Unit) {
    val c = Theme.colors
    val dir = if (minus) -1 else 1
    val atBound = if (minus) value <= bounds.first else value >= bounds.last
    val current by rememberUpdatedState(value)
    val change by rememberUpdatedState(onChange)
    val scope = rememberCoroutineScope()
    var repeatAteTheTap by remember { mutableStateOf(false) }
    var pressed by remember { mutableStateOf(false) }
    val label = if (minus) tr("Fewer") else tr("More")
    fun bump() {
        change(AdjustPanel.bump(current, dir, unit, bounds))
    }
    Box(Modifier.size(MinTarget), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .requiredSize(62.dp, 68.dp)
                .alpha(if (atBound) 0.3f else if (pressed) 0.55f else 1f)
                .testTag(if (minus) "minus" else "plus")
                .semantics {
                    role = Role.Button
                    contentDescription = label
                    if (atBound) disabled()
                    onClick { bump(); true }
                }
                .pointerInput(atBound, unit, bounds) {
                    if (atBound) return@pointerInput
                    detectTapGestures(
                        onPress = {
                            pressed = true
                            repeatAteTheTap = false
                            val repeat = scope.launch {
                                delay(AdjustPanel.repeatDelayMs)
                                // Its own running value: a repeat must not wait
                                // on a redraw to know where it stands.
                                var running = current
                                var steps = 0
                                while (isActive) {
                                    repeatAteTheTap = true
                                    running = AdjustPanel.bump(running, dir, unit, bounds)
                                    change(running)
                                    steps += 1
                                    delay(if (steps < AdjustPanel.stepsBeforeFast) AdjustPanel.repeatIntervalMs
                                          else AdjustPanel.repeatFastIntervalMs)
                                }
                            }
                            // `finally`: a press cut short by the panel leaving
                            // (OK is one thumb away) must not leave the repeat
                            // moving a number nobody is looking at.
                            try {
                                tryAwaitRelease()
                            } finally {
                                repeat.cancel()
                                pressed = false
                            }
                        },
                        onTap = {
                            if (repeatAteTheTap) repeatAteTheTap = false else bump()
                        },
                    )
                },
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
