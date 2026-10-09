//
//  Stands where "Start" would, while the journal could not be read. Port of
//  ios/Dredfit/Views/Today/FrozenJournalCard.swift: a workout done on a
//  frozen launch is kept in memory only, so starting one would lose it. Try
//  again is the whole of the activation, not just its read, and the words
//  promise neither it nor the relaunch.
//

package com.dredfit.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.dredfit.store.AppStore
import com.dredfit.store.activate
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.PairedPrimary
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

@Composable
fun FrozenJournalCard(observedStore: Observed<AppStore>) {
    val c = Theme.colors
    Column(Modifier.fillMaxWidth().background(c.cardBG, RoundedCornerShape(18.dp)).padding(18.dp).testTag("frozen-card")) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("frozen-card-text")) {
            Text(tr("Your history couldn't be read"), style = dredfitFont(20f, Weight.heavy, tracking = -0.3f), color = c.ink)
            Text(tr("Your saved history can't be read right now, so a workout started now can't be saved. Try again, or close Dredfit and open it again."),
                 style = dredfitFont(14.5f), color = c.ink2)
        }
        PairedPrimary(tr("Try again"), tag = "frozen-retry", modifier = Modifier.fillMaxWidth().padding(top = 16.dp)) {
            observedStore.act { activate() }
        }
    }
}
