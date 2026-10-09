//
//  The pieces more than one state of Today draws. Port of
//  ios/Dredfit/Views/Today/TodayCards.swift ("Train anyway"'s quiet label is
//  `QuietButton` in ui/theme, beside the other buttons).
//

package com.dredfit.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
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
import com.dredfit.store.AppStore
import com.dredfit.store.comebackPreview
import com.dredfit.store.declineComeback
import com.dredfit.store.nextSession
import com.dredfit.store.offersFreshStart
import com.dredfit.store.silentDecayAppliedForCurrentBreak
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.ChevronGlyph
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

/** The door to the next plan, on the completed day and on the rest day
 *  alike: as plain text it would leave rest the one screen with no way to
 *  the plan. */
@Composable
fun NextWorkoutCard(observedStore: Observed<AppStore>, onClick: () -> Unit) {
    val store by observedStore
    val c = Theme.colors
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(c.cardBG, shape)
            .clickable(role = Role.Button, onClick = onClick).testTag("next-workout")
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Kicker(tr("Next"))
            Text(tr("Workout %lld · %@", store.nextSession.sessionNumber, nextTrainingDateLabel(store)),
                 style = dredfitFont(16.5f, Weight.semibold), color = c.ink)
        }
        ChevronGlyph(c.ink3, 14.dp)
    }
}

/** One card, two screens: a break that ends on a rest day is still a break,
 *  and the offer has to be where the person is. */
@Composable
fun ComebackOffer(observedStore: Observed<AppStore>, onFreshStart: () -> Unit) {
    val store by observedStore
    ComebackCard(offersFreshStart = store.offersFreshStart(), preview = store.comebackPreview(),
                 alreadyDecayed = store.silentDecayAppliedForCurrentBreak,
                 onAccept = { observedStore.act { acceptComeback() } },
                 onDecline = { observedStore.act { declineComeback() } },
                 onFreshStart = onFreshStart)
}
