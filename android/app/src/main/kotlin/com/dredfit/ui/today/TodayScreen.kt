//
//  Today: plan + Start, rest day, or completed with a door to the next
//  workout under its honest date. Port of ios/Dredfit/Views/Today/TodayView.swift
//  (the file keeps the name the Android scaffold gave it).
//

package com.dredfit.ui.today

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.journal.WorkoutRecord
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.doneToday
import com.dredfit.store.nextSession
import com.dredfit.store.restAppliesToday
import com.dredfit.ui.Observed
import com.dredfit.ui.progress.HistorySheet
import com.dredfit.ui.technique.TechniqueSheet
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.tr
import com.dredfit.workout.TechniqueTarget

/** The session is snapshotted at the tap, not read live: the rating advances
 *  the engine before the flow closes, and a live read would flip the rating
 *  screen to the NEXT session. */
data class WorkoutRequest(val session: Session, val resume: WorkoutSnapshot? = null,
                          val settleImmediately: Boolean = false)

/** The movement the suspect question is about and the name of what sits
 *  below it — the alert has to NAME the movement. */
data class SuspectStepDown(val pattern: Pattern, val name: String)

/** Every sheet this screen raises, behind one slot. */
sealed interface TodayDestination {
    data class Technique(val target: TechniqueTarget) : TodayDestination
    data object NextWorkout : TodayDestination
    /** Today's own record, from the screen that is about today. */
    data class History(val record: WorkoutRecord) : TodayDestination
}

/** The questions Today asks before it acts. They live here, not in the views
 *  that ask them: those come and go as the day moves between plan, rest and
 *  completed, and a question raised across that switch must not be lost. */
@Stable
class TodayState {
    var destination by mutableStateOf<TodayDestination?>(null)
    var freshStartConfirmShown by mutableStateOf(false)
    var startOverConfirmShown by mutableStateOf(false)
    var pendingSuspect by mutableStateOf<SuspectStepDown?>(null)
    var ratingChangeShown by mutableStateOf(false)
}

@Composable
fun TodayScreen(observedStore: Observed<AppStore>, start: (WorkoutRequest) -> Unit, modifier: Modifier = Modifier) {
    val store by observedStore
    val today = remember { TodayState() }
    val done = store.doneToday
    // `restApplies`, not `isRestDay`: rest is rest FROM something.
    val resting = !done && store.restAppliesToday
    val planShowing = if (!done && !resting) store.nextSession else null

    Box(modifier.fillMaxSize().padding(horizontal = 24.dp)) {
        when {
            done -> DoneView(observedStore, today)
            resting -> RestView(observedStore, start, today)
            else -> PlanView(observedStore, start, today)
        }
    }

    // The plan reached a pair of eyes — the engine is told, once per showing:
    // keyed on the plan, so a redraw is the same showing and costs nothing.
    LaunchedEffect(planShowing) {
        planShowing?.let { observedStore.act { recordPlanShown(it) } }
    }

    when (val destination = today.destination) {
        // `planned`: these are the movements of the workout about to be done.
        is TodayDestination.Technique ->
            TechniqueSheet(destination.target, planned = true, observedStore = observedStore) { today.destination = null }
        TodayDestination.NextWorkout -> NextWorkoutSheet(observedStore) { today.destination = null }
        is TodayDestination.History -> HistorySheet(observedStore, destination.record) { today.destination = null }
        null -> Unit
    }
    if (today.freshStartConfirmShown) {
        DredfitAlert(
            title = tr("Start from scratch?"),
            message = tr("Every movement goes back to the beginning. Your history stays."),
            actions = listOf(
                AlertAction(tr("Keep my progress"), tag = null, cancel = true) {},
                AlertAction(tr("Reset progress"), tag = "fresh-start-confirm", destructive = true) {
                    observedStore.act { resetProgress() }
                },
            ),
            onClose = { today.freshStartConfirmShown = false },
        )
    }
    today.pendingSuspect?.let { pending ->
        // The same alert the technique sheet raises before the SAME engine
        // call, with its translated keys.
        DredfitAlert(
            title = tr("technique.stepDown.confirmTitle", tr(pending.name)),
            message = tr("technique.stepDown.confirmBody"),
            actions = listOf(
                AlertAction(tr("Keep going"), tag = null, cancel = true) {},
                AlertAction(tr("technique.stepDown.switch"), tag = "suspect-switch") {
                    observedStore.act { makeSuspectEasier(pending.pattern) }
                },
            ),
            onClose = { today.pendingSuspect = null },
        )
    }
}
