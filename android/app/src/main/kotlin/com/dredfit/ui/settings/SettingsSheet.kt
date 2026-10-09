//
//  The settings sheet the gear opens: how it works, the week, the
//  equipment, sounds, the theme, backup and the version. Port of
//  ios/Dredfit/Views/Settings/SettingsSheet.swift, with the grammar every
//  group draws with (kicker, caption, row).
//
//  Not here, and not stubbed: Apple Health's group (Health Connect arrives
//  with phase 3) and the reminder (reminders/, phase 3) — see android/CLAUDE.md.
//

package com.dredfit.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.dredfit.store.AppStore
import com.dredfit.ui.Observed
import com.dredfit.ui.SaveFailureBanner
import com.dredfit.ui.theme.DredfitSheet
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.QuestionGlyph
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

@Composable
fun SettingsSheet(observedStore: Observed<AppStore>, onDismiss: () -> Unit) {
    val c = Theme.colors
    var howItWorksShown by remember { mutableStateOf(false) }
    DredfitSheet(onDismiss) {
        Column(Modifier.fillMaxHeight()) {
            SaveFailureBanner(observedStore, trailingClearance = 0.dp)
            // ONE grammar for the whole screen: every group opens with a
            // kicker, a caption sits 6 dp under the control it explains and
            // 14 dp from the next control, groups stand 28 dp apart.
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 12.dp),
                   verticalArrangement = Arrangement.spacedBy(28.dp)) {
                Text(tr("Settings"), style = dredfitFont(28f, Weight.heavy, tracking = -0.5f), color = c.ink,
                     modifier = Modifier.padding(top = 14.dp))
                SettingsRow({ QuestionGlyph(c.ink, 16.dp) }, tr("How it works"), tag = "how-it-works") { howItWorksShown = true }
                RhythmSection(observedStore)
                EquipmentSection(observedStore)
                SoundsSection(observedStore)
                AppearanceSection(observedStore)
                BackupSection(observedStore)
                AboutSection()
            }
            // Keyed: the same English word as the workout's set button.
            PrimaryButton(tr("settings.done"), tag = "settings-done",
                          modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 16.dp), onClick = onDismiss)
        }
    }
    if (howItWorksShown) HowItWorksView { howItWorksShown = false }
}

// MARK: - The grammar of the screen

/** The name of a group, a heading to TalkBack. The tag is what a UI test
 *  anchors on: the words are localized and uppercased, the tag is neither. */
@Composable
fun SettingsKicker(text: String, tag: String) {
    Kicker(text, Modifier.semantics { heading() }.testTag(tag))
}

/** The one caption style of the screen: 12.5 ink2, wrapping. */
@Composable
fun SettingsCaption(text: String, modifier: Modifier = Modifier) {
    Text(text, style = dredfitFont(12.5f), color = Theme.colors.ink2, modifier = modifier)
}

/** A row that opens or does something: an icon, the words, on cardBG. */
@Composable
fun SettingsRow(icon: @Composable () -> Unit, title: String, tag: String, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.4f).clip(shape).background(Theme.colors.cardBG, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick).testTag(tag)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        icon()
        Text(title, style = dredfitFont(16f, Weight.medium), color = Theme.colors.ink)
    }
}
