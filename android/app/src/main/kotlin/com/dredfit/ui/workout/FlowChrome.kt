//
//  The small pieces every timed block of the workout flow shares: the header,
//  the big countdown number, the set dots and the "ⓘ technique" affordance.
//  Port of ios/Dredfit/Views/Workout/FlowChrome.swift — one look, defined
//  once; the escapes and the rest ring are FlowChromeControls.kt and
//  FlowChromeRest.kt.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.dredfit.ui.theme.InfoGlyph
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

/**
 * The bar every timed phase wears: the way out on the left, what the screen
 * is in the middle, the per-exercise capsules under it. `steps` 0 hides the
 * capsules (the warm-up is not an exercise yet); `doneIndex` is how many
 * exercises are BEHIND — `steps` itself on the cool-down, where none is under
 * way (FlowChrome.swift says why).
 */
@Composable
fun FlowHeader(title: String, steps: Int, doneIndex: Int, minutesLeft: Int?, onExit: () -> Unit) {
    val c = Theme.colors
    Column(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            ExitButton("workout-exit", visible = true, onExit)
            Text(title, style = dredfitFont(13f, Weight.semibold, tracking = 0.5f), color = c.ink2,
                 textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            // The title is centred by two equal ends, so the right one has to
            // measure the same. Its own name, so a query cannot pick it.
            ExitButton("workout-exit-spacer", visible = false) {}
        }
        if (steps > 0) {
            Row(Modifier.width(200.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                for (i in 0 until steps) {
                    // Three states: done, under way, ahead — ahead in ink2,
                    // since hairline is not on the light screen at all.
                    val fill = when {
                        i < doneIndex -> c.ink
                        i == doneIndex -> c.accent
                        else -> c.ink2
                    }
                    Box(Modifier.weight(1f).height(4.dp).background(fill, CircleShape))
                }
            }
        }
        if (minutesLeft != null) {
            // An answer to "how much longer", not a deadline.
            Text(tr("≈ %lld min left", minutesLeft), style = dredfitFont(12f, monospacedDigit = true),
                 color = c.ink2, modifier = Modifier.testTag("time-left"))
        }
    }
}

/** 44 dp: this is the control someone reaches for when a set has gone wrong. */
@Composable
private fun ExitButton(tag: String, visible: Boolean, onClick: () -> Unit) {
    val c = Theme.colors
    Box(
        Modifier
            .heightIn(min = MinTarget)
            .alpha(if (visible) 1f else 0f)
            .then(if (visible) Modifier.clickable(role = Role.Button, onClick = onClick).testTag(tag)
                  else Modifier.semantics { hideFromAccessibility() })
            .padding(end = 4.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(tr("Exit"), style = dredfitFont(14f), color = c.ink2)
    }
}

/** A dot that follows the reader's text size, as `@ScaledMetric(relativeTo:
 *  .caption)` does: 10 dp at the default size. */
@Composable
fun scaledDot(base: Dp = 10.dp): Dp = base * LocalDensity.current.fontScale

/**
 * The big number with the word under it: the unit while a position simply
 * runs itself down, or the STATE when the same digit is doing something
 * else. Paused outranks the caption: a frozen "Get ready" would say what the
 * screen is FOR while hiding that it is not doing it.
 */
@Composable
fun CountdownNumber(value: Int, tag: String, paused: Boolean = false, caption: String? = null) {
    val c = Theme.colors
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("$value", style = dredfitFont(112f, Weight.heavy, cap = 150f, tracking = -4f, monospacedDigit = true),
             color = if (paused) c.ink2 else c.ink, modifier = Modifier.testTag(tag))
        when {
            paused -> Text(tr("Paused"), style = dredfitFont(15f, Weight.semibold), color = c.accentText)
            // Hidden from TalkBack: the position's name already speaks it.
            caption != null -> Text(caption, style = dredfitFont(15f, Weight.semibold), color = c.accentText,
                                    modifier = Modifier.semantics { hideFromAccessibility() })
            else -> Text(tr("sec"), style = dredfitFont(15f), color = c.ink2)
        }
    }
}

/** One definition for the warm-up, the cool-down and the transition.
 *  `upcoming`: on the transition the dot at `current` has not begun, and is
 *  outlined rather than filled. */
@Composable
fun BlockDots(count: Int, current: Int, upcoming: Boolean = false) {
    val c = Theme.colors
    val dot = scaledDot()
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (i in 0 until count) {
            val m = Modifier.size(dot)
            if (upcoming && i == current) {
                Box(m.border(2.dp, c.accent, CircleShape))
            } else {
                val fill = when {
                    i < current -> c.ink
                    i == current -> c.accent
                    else -> c.ink2
                }
                Box(m.background(fill, CircleShape))
            }
        }
    }
}

/** "ⓘ technique" — offered on five screens, three of them mid-effort, where
 *  the hand that reaches for it just did the set: 44 dp. */
@Composable
fun TechniqueButton(modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val c = Theme.colors
    Row(
        modifier
            .heightIn(min = MinTarget)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .testTag("technique")
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        InfoGlyph(c.ink2, 15.dp)
        Text(tr("technique"), style = dredfitFont(14f, Weight.medium), color = c.ink2)
    }
}

/** Where the flow's spoken announcements go: a polite live region, read by
 *  TalkBack without taking the focus — `AccessibilityNotification
 *  .Announcement` on iOS. Drawn at no size. */
@Composable
fun Announcer(text: String?) {
    if (text == null) return
    Box(Modifier.size(1.dp).semantics { liveRegion = LiveRegionMode.Polite }) {
        Text(text, style = dredfitFont(1f), color = Theme.colors.bg.copy(alpha = 0f))
    }
    Spacer(Modifier.height(0.dp))
}

/** A clipped rounded rectangle every flow card shares. */
internal val CardShape = RoundedCornerShape(16.dp)
