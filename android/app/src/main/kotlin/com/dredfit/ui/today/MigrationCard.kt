//
//  Shown on Today after an upgrade from a build before v3, until dismissed.
//  Port of ios/Dredfit/Views/Today/MigrationCard.swift: the migration is
//  positional, not to the digit, so the card names the step moves instead of
//  promising "same numbers". (An Android install meets it only through an
//  imported pre-v3 backup.)
//

package com.dredfit.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.dredfit.ui.theme.PairedPrimary
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

@Composable
fun MigrationCard(onDismiss: () -> Unit) {
    val c = Theme.colors
    Column(Modifier.fillMaxWidth().background(c.cardBG, RoundedCornerShape(18.dp)).padding(18.dp)) {
        Text(tr("Your progress carried over"), style = dredfitFont(20f, Weight.heavy, tracking = -0.3f), color = c.ink)
        Text(tr("The exercises were rebuilt: the ladders have more variations, and the plan follows what you actually do. You pick up where you left off."),
             style = dredfitFont(14.5f), color = c.ink2, modifier = Modifier.padding(top = 8.dp))
        Text(tr("Your whole history is here. A few exercises go by new names, and a few numbers moved a step to fit the new ladders."),
             style = dredfitFont(13f), color = c.ink2, modifier = Modifier.padding(top = 8.dp))
        PairedPrimary(tr("Got it"), tag = "migration-dismiss", modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                      onClick = onDismiss)
    }
}
