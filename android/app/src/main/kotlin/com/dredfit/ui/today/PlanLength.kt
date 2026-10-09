//
//  The one line that says how long a session takes: the full plan and the
//  same plan with every movement on the sets floor — a RANGE, so "will this
//  fit today" gets an answer without asking anyone to decide anything first.
//  Port of ios/Dredfit/Views/Today/PlanLength.swift. The identifier stays with
//  the caller: Today and the next-workout sheet can both be on screen.
//

package com.dredfit.ui.today

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

@Composable
fun PlanLength(floor: Int, full: Int, count: Int, modifier: Modifier = Modifier) {
    val c = Theme.colors
    // One number only when the plan is already on the floor.
    if (floor < full) {
        val spoken = tr("about %lld to %lld minutes · %lld exercises", floor, full, count)
        Text(tr("≈ %lld–%lld min · %lld exercises", floor, full, count), style = dredfitFont(15f), color = c.ink2,
             modifier = modifier.semantics { contentDescription = spoken })
    } else {
        Text(tr("≈ %lld min · %lld exercises", full, count), style = dredfitFont(15f), color = c.ink2, modifier = modifier)
    }
}

/** What the number above is made of at both ends: ten of those minutes are
 *  the two blocks, and their share is largest on the shortest sessions. It
 *  states the fact and stops there. */
@Composable
fun PlanEndsNote(warmupMin: Int, cooldownMin: Int) {
    Text(tr("Includes about %lld min of warm-up and cool-down.", warmupMin + cooldownMin),
         style = dredfitFont(13.5f), color = Theme.colors.ink2)
}
