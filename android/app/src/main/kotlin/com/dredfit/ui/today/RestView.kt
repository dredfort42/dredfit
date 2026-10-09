//
//  The rest-day state of Today. Port of ios/Dredfit/Views/Today/RestView.swift:
//  rest is a plan, not a lockout — training anyway stays available, and an
//  interrupted "train anyway" session comes back here too.
//

package com.dredfit.ui.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.dredfit.store.AppStore
import com.dredfit.store.nextSession
import com.dredfit.store.shouldOfferComeback
import com.dredfit.ui.Observed
import com.dredfit.ui.screenDateText
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.QuietButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr

@Composable
fun RestView(observedStore: Observed<AppStore>, start: (WorkoutRequest) -> Unit, today: TodayState) {
    val store by observedStore
    val c = Theme.colors
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Kicker(screenDateText(store.today, store.zone))
            Text(tr("Rest day"), style = dredfitFont(32f, Weight.heavy, tracking = -0.5f), color = c.ink)
            Text(tr("Next workout %@", nextTrainingDateLabel(store)), style = dredfitFont(15f), color = c.ink2)
        }
        // ink2, not ink3: this sentence is the rest day's whole argument.
        Text(tr("Recovery is part of the plan — you get stronger between workouts, not during them."),
             style = dredfitFont(15.5f), color = c.ink2, modifier = Modifier.padding(top = 22.dp))
        Spacer(Modifier.weight(1f))
        // The door to the plan: "Train anyway" must not be answered without
        // seeing what it starts.
        Box(Modifier.padding(bottom = 12.dp)) {
            NextWorkoutCard(observedStore) { today.destination = TodayDestination.NextWorkout }
        }
        // A return that lands on a rest day still gets its offer.
        if (store.shouldOfferComeback()) {
            Box(Modifier.padding(bottom = 12.dp)) { ComebackOffer(observedStore) { today.freshStartConfirmShown = true } }
        }
        val pending = store.pendingWorkoutCard
        if (pending != null) {
            Box(Modifier.padding(bottom = 14.dp)) {
                ResumeCard(observedStore, pending, start, today.startOverConfirmShown) { today.startOverConfirmShown = it }
            }
        } else {
            QuietButton(tr("Train anyway"), tag = "train-anyway", Modifier.padding(bottom = 14.dp)) {
                start(WorkoutRequest(store.nextSession))
            }
        }
    }
}
