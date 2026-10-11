//
//  The exercise summary as the phase shows it. Port of
//  ios/Dredfit/Views/Workout/WorkoutFlowView+Summary.swift; which cards there
//  are, what a tap on one writes and what the "next time" block asks the
//  engine are WorkoutSessionSummary.kt's, the leaves ExerciseSummary.kt's.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.LoadUnit
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.SetFacts
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.commitSummaryEdit
import com.dredfit.workout.heldSets
import com.dredfit.workout.leaveExerciseSummary
import com.dredfit.workout.leftOutHere
import com.dredfit.workout.nextPlan
import com.dredfit.workout.setRaise
import com.dredfit.workout.startSummaryAdjusting
import com.dredfit.workout.summaryPanelLine
import com.dredfit.workout.summaryRange

@Composable
fun ExerciseSummaryView(observed: Observed<WorkoutSession>) {
    val flow by observed
    val c = Theme.colors
    Column(Modifier.fillMaxSize()) {
        // Centred while it fits, scrollable once it does not: five cards, a
        // large text size and a small phone are all real at once.
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight),
                   horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                // Named: the uppercase fold makes the word unfindable by its spelling.
                Text(tr("Held").uppercase(), style = dredfitFont(11f, Weight.heavy, tracking = 0.6f), color = c.accentText,
                     modifier = Modifier.testTag("summary-held"))
                Text(tr(flow.exercise.name), style = dredfitFont(23f, Weight.bold), color = c.ink,
                     textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp).widthIn(max = 300.dp))
                Box(Modifier.padding(top = 22.dp)) {
                    HeldSetsRow(flow.heldSets) { set -> observed.act { startSummaryAdjusting(set) } }
                }
                // ONE sentence, about the past, in the words the app already
                // uses for this act. It names the LAST set because only the last
                // set can be corrected.
                Text(if (flow.exercise.perSide)
                         tr("Went differently? Tap the last set and correct — the numbers are per side, and the others stand as they ran.")
                     else tr("Went differently? Tap the last set and correct — the others stand as they ran."),
                     style = dredfitFont(14f), color = c.ink2, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(top = 18.dp).padding(horizontal = 8.dp).testTag("summary-counted"))
            }
        }

        // ONE SLOT above the button, two occupants: the panel while a number
        // is being entered, the "next time" block otherwise.
        val editing = flow.editing
        if (editing is WorkoutSession.EditTarget.SummaryCard) {
            val index = editing.index
            Text(tr(flow.summaryPanelLine(index)), style = dredfitFont(14f, monospacedDigit = true), color = c.ink2,
                 textAlign = TextAlign.Center,
                 modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp).testTag("summary-panel-line"))
            Box(Modifier.padding(bottom = 18.dp)) {
                AdjustPanel(flow.adjustValue, LoadUnit.hold, range = flow.summaryRange(index),
                            onChange = { v -> observed.act { adjustValue = v } },
                            onConfirm = { observed.act { commitSummaryEdit(index) } })
            }
        } else {
            Box(Modifier.padding(bottom = 18.dp)) {
                NextTimeBlockCard(
                    exercise = flow.exercise,
                    steps = flow.raisedSteps[flow.exercise.pattern] ?: 0,
                    factEntered = SetFacts.override(flow.actuals, flow.exercise, skipping = flow.leftOutHere) != null,
                    preview = { flow.nextPlan(withAdditions = it) },
                    onChange = { steps -> observed.act { setRaise(steps) } })
            }
        }
        // "Done", the same act as every other tap that logs work. NO escapes:
        // the movement is behind, and an escape would offer to throw away the
        // numbers the screen asks you to confirm.
        PrimaryButton(tr("Done"), tag = "exercise-done", modifier = Modifier.padding(bottom = 10.dp)) {
            observed.act { leaveExerciseSummary() }
        }
    }
}
