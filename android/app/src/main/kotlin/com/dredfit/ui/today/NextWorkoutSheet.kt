//
//  The next workout, deliberately WITHOUT a Start button — one workout per
//  day. Port of ios/Dredfit/Views/Today/NextWorkoutSheet.swift: the same rows
//  as Today, with the same notes and the same pill, and technique sheets
//  WITHOUT the step below — this preview looks at a session rather than
//  deciding about one.
//

package com.dredfit.ui.today

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.dredfit.store.AppStore
import com.dredfit.store.debutPatterns
import com.dredfit.store.nextSession
import com.dredfit.store.sessionLengthRange
import com.dredfit.ui.Observed
import com.dredfit.ui.technique.TechniqueSheet
import com.dredfit.ui.theme.DredfitSheet
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.TechniqueTarget

@Composable
fun NextWorkoutSheet(observedStore: Observed<AppStore>, onDismiss: () -> Unit) {
    val store by observedStore
    val c = Theme.colors
    var techniqueFor by remember { mutableStateOf<TechniqueTarget?>(null) }
    val session = store.nextSession
    val (floor, full) = store.sessionLengthRange()
    val debuts = store.debutPatterns
    DredfitSheet(onDismiss) {
        Column(Modifier.padding(horizontal = 24.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Kicker(tr("Next · %@", nextTrainingDateLabel(store)))
            Text(tr("Workout %lld", session.sessionNumber), style = dredfitFont(28f, Weight.heavy, tracking = -0.5f),
                 color = c.ink)
            PlanLength(floor, full, session.exercises.size)
            PlanEndsNote(session.warmupMin, session.cooldownMin)
        }
        LazyColumn(Modifier.weight(1f, fill = false).padding(horizontal = 24.dp)) {
            items(session.exercises, key = { it.pattern.rawValue }) { ex ->
                ExerciseRowView(ex, badge = if (ex.pattern in debuts) tr("new variation") else null,
                                notes = planRowNotes(store, ex),
                                modifier = Modifier.clickable(role = Role.Button) { techniqueFor = TechniqueTarget(ex) }
                                    .padding(vertical = 8.dp))
                HorizontalDivider(color = c.hairline)
            }
        }
        PrimaryButton(tr("Got it"), tag = "next-workout-done",
                      modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp), onClick = onDismiss)
    }
    techniqueFor?.let { target ->
        TechniqueSheet(target, planned = false, observedStore = observedStore) { techniqueFor = null }
    }
}
