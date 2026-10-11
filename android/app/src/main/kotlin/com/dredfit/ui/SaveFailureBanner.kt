//
//  The line that says a write failed, on every screen the person can be on.
//  Port of ios/Dredfit/Views/SaveFailureBanner.swift: the store keeps a failed
//  change in memory and keeps working, so without this nothing on screen
//  would change when the disk refuses a write, and a quit would lose the
//  change without a word.
//

package com.dredfit.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.dredfit.store.AppStore
import com.dredfit.store.retryPersist
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont

/** Shown only while a write has failed. `trailingClearance` keeps the
 *  settings gear's corner free on Today. The appearance is announced (a
 *  polite live region), because the banner comes without anything touched. */
@Composable
fun SaveFailureBanner(observedStore: Observed<AppStore>, trailingClearance: Dp) {
    val store by observedStore
    if (store.lastPersistError == null) return
    val c = Theme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(top = 4.dp)
            // The accent fill and ink words, as the other notes that block
            // nothing: accentText on accentSoft is under 4.5:1 in dark (I-21).
            .background(c.accentSoft, RoundedCornerShape(14.dp))
            .padding(start = 14.dp, end = 14.dp + trailingClearance, top = 4.dp, bottom = 4.dp)
            .semantics(mergeDescendants = false) { liveRegion = LiveRegionMode.Polite }
            .testTag("save-failed-banner"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(tr("Couldn't save your latest changes. They'll be lost if the app closes before a save works."),
             style = dredfitFont(13.5f, Weight.medium), color = c.ink, modifier = Modifier.weight(1f))
        Box(Modifier.heightIn(min = MinTarget).clickable(role = Role.Button) { observedStore.act { retryPersist() } }
                .testTag("save-retry"),
            contentAlignment = Alignment.Center) {
            Text(tr("Try again"), style = dredfitFont(13.5f, Weight.semibold).copy(textDecoration = TextDecoration.Underline),
                 color = c.ink)
        }
    }
}
