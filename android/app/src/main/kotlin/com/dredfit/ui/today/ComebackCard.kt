//
//  Shown on Today after a break of two weeks or more. Port of
//  ios/Dredfit/Views/Today/ComebackCard.swift: the engine is event-driven, so
//  without this an old plan waits at the old level — and the choice is shown
//  in numbers, not adjectives (#127).
//

package com.dredfit.ui.today

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.dredfit.store.ComebackPreview
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PairedPrimary
import com.dredfit.ui.theme.PairedSecondary
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

@Composable
fun ComebackCard(offersFreshStart: Boolean, preview: ComebackPreview?, alreadyDecayed: Boolean,
                 onAccept: () -> Unit, onDecline: () -> Unit, onFreshStart: () -> Unit) {
    val c = Theme.colors
    Column(Modifier.fillMaxWidth().background(c.cardBG, RoundedCornerShape(18.dp)).padding(18.dp)) {
        Text(tr("Welcome back"), style = dredfitFont(20f, Weight.heavy, tracking = -0.3f), color = c.ink)
        Text(tr("A break is normal. Let's start a few steps easier — the longer the break, the lower the plan meets you, and it catches up quickly."),
             style = dredfitFont(14.5f), color = c.ink2, modifier = Modifier.padding(top = 8.dp))
        if (alreadyDecayed) {
            Text(tr("During the break the plan already came down a step."), style = dredfitFont(13.5f, Weight.medium),
                 color = c.ink2, modifier = Modifier.padding(top = 8.dp))
        }
        if (preview != null) {
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                PreviewRow(tr("Easier:"), tr(preview.easier))
                PreviewRow(tr("As it was:"), tr(preview.was))
            }
        }
        Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PairedPrimary(tr("Start easier"), tag = "comeback-accept", modifier = Modifier.weight(1f), onClick = onAccept)
            PairedSecondary(tr("Leave as it was"), tag = "comeback-decline", modifier = Modifier.weight(1f),
                            onClick = onDecline)
        }
        if (offersFreshStart) {
            // Bordered and set apart: the one control on this card that throws
            // progress away must not read as a quiet extra of the pair. ink3
            // for the stroke — hairline on cardBG is simply not there.
            val shape = RoundedCornerShape(14.dp)
            Box(Modifier.padding(top = 14.dp).fillMaxWidth().heightIn(min = MinTarget).clip(shape)
                    .border(1.5.dp, c.ink3, shape).clickable(role = Role.Button, onClick = onFreshStart)
                    .testTag("comeback-fresh"),
                contentAlignment = Alignment.Center) {
                Text(tr("Start from scratch"), style = dredfitFont(13.5f, Weight.medium), color = c.ink2)
            }
        }
    }
}

@Composable
private fun PreviewRow(label: String, value: String) {
    val c = Theme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = dredfitFont(13f, Weight.semibold), color = c.ink2)
        Text(value, style = dredfitFont(13f), color = c.ink)
    }
}
