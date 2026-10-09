//
//  The plan state of Today: the six rows and everything that asks about
//  them. Port of ios/Dredfit/Views/Today/PlanView.swift — no control stands
//  beside a plan row; the variation one step below lives in the technique
//  sheet the row opens.
//

package com.dredfit.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.Pattern
import com.dredfit.core.SessionExercise
import com.dredfit.store.AppStore
import com.dredfit.store.aSetJustCameBack
import com.dredfit.store.aVariationJustDropped
import com.dredfit.store.canMakeEasier
import com.dredfit.store.canStartWorkout
import com.dredfit.store.debutPatterns
import com.dredfit.store.dismissMigrationNotice
import com.dredfit.store.dismissSuspectPrompt
import com.dredfit.store.easedByHandAhead
import com.dredfit.store.easierStep
import com.dredfit.store.nextSession
import com.dredfit.store.raisedForNextPlan
import com.dredfit.store.sessionLengthRange
import com.dredfit.store.setsJustHeldBackByThePulls
import com.dredfit.store.shouldAskAboutSuspect
import com.dredfit.store.shouldOfferComeback
import com.dredfit.store.showsMigrationNotice
import com.dredfit.store.showsTechniqueHint
import com.dredfit.store.silentDecayAppliedForCurrentBreak
import com.dredfit.store.todayWouldExtendALongRun
import com.dredfit.store.unnamedLessSuspect
import com.dredfit.store.wouldBeConsecutiveDay
import com.dredfit.ui.Observed
import com.dredfit.ui.screenDateText
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.QuietButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.TechniqueTarget

/** What one plan row says, read off the store — Today and the next-workout
 *  sheet ask the same five questions in the same order. */
@Composable
fun planRowNotes(store: AppStore, ex: SessionExercise) = ExerciseRow.notes(
    ex,
    setCameBack = store.aSetJustCameBack(ex),
    easedByHand = ex.pattern in store.easedByHandAhead,
    variationDropped = store.aVariationJustDropped(ex),
    raisedSteps = store.raisedForNextPlan(ex.pattern),
    heldBackByPulls = store.setsJustHeldBackByThePulls(ex))

@Composable
fun PlanView(observedStore: Observed<AppStore>, start: (WorkoutRequest) -> Unit, today: TodayState) {
    val store by observedStore
    val c = Theme.colors
    val session = store.nextSession
    val debuts = store.debutPatterns
    val (floor, full) = store.sessionLengthRange()
    Column {
        Column(Modifier.padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Kicker(screenDateText(store.today, store.zone))
            Text(tr("Workout %lld", session.sessionNumber), style = dredfitFont(32f, Weight.heavy, tracking = -0.5f),
                 color = c.ink)
            PlanLength(floor, full, session.exercises.size, Modifier.testTag("plan-length"))
            PlanEndsNote(session.warmupMin, session.cooldownMin)
        }

        // Six rows, all of them the plan: nothing on this screen sets a
        // movement aside.
        LazyColumn(Modifier.weight(1f).padding(top = 8.dp)) {
            items(session.exercises, key = { it.pattern.rawValue }) { ex ->
                // The whole row is the target: a tap into the gap between the
                // name and the load must not reach nothing, because the sheet
                // is where the handle lives.
                ExerciseRowView(ex, badge = if (ex.pattern in debuts) tr("new variation") else null,
                                notes = planRowNotes(store, ex),
                                modifier = Modifier.clickable(role = Role.Button) {
                                    today.destination = TodayDestination.Technique(TechniqueTarget(ex))
                                }.padding(vertical = 8.dp).testTag("plan-row-${ex.pattern.rawValue}"))
                HorizontalDivider(color = c.hairline)
            }
        }

        PlanNotes(observedStore)

        if (store.showsMigrationNotice) {
            Box(Modifier.padding(top = 10.dp)) { MigrationCard { observedStore.act { dismissMigrationNotice() } } }
        }
        if (store.shouldOfferComeback()) {
            Box(Modifier.padding(top = 10.dp)) { ComebackOffer(observedStore) { today.freshStartConfirmShown = true } }
        }
        // Asked only when there IS a variation below: on the bottom rung the
        // question would offer a tap that changed nothing.
        val suspect = if (store.shouldAskAboutSuspect()) store.unnamedLessSuspect() else null
        val step = suspect?.let { store.easierStep(it) }
        if (suspect != null && step != null) {
            SuspectPrompt(suspect, onEasier = { today.pendingSuspect = SuspectStepDown(suspect, step.name) },
                          onFine = { observedStore.act { dismissSuspectPrompt() } })
        }
        if (store.showsTechniqueHint) {
            // Two sentences: on a first workout no row has a step below, and
            // the one line the app spends on this door must not promise one.
            Text(if (session.exercises.any { store.canMakeEasier(it.pattern) })
                     tr("plan.techniqueHint") else tr("plan.techniqueHintNoStep"),
                 style = dredfitFont(14f), color = c.ink2, textAlign = TextAlign.Center,
                 modifier = Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 16.dp).testTag("technique-hint"))
        }
        val pending = store.pendingWorkoutCard
        when {
            // Nothing to resume either — the snapshot lives in the file that
            // could not be read.
            !store.canStartWorkout -> Box(Modifier.padding(top = 10.dp, bottom = 14.dp)) { FrozenJournalCard(observedStore) }
            pending != null -> Box(Modifier.padding(top = 10.dp, bottom = 14.dp)) {
                ResumeCard(observedStore, pending, start, today.startOverConfirmShown) { today.startOverConfirmShown = it }
            }
            // Quiet while the comeback card is up: its filled "Start easier"
            // must not lose a question about the plan to geometry.
            store.shouldOfferComeback() -> QuietButton(tr("Start"), tag = "start-workout", Modifier.padding(top = 10.dp)) {
                start(WorkoutRequest(store.nextSession))
            }
            else -> PrimaryButton(tr("Start"), tag = "start-workout", modifier = Modifier.padding(top = 10.dp)) {
                start(WorkoutRequest(store.nextSession))
            }
        }
        Box(Modifier.heightIn(min = 14.dp))
    }
}

/** The two quiet sentences the plan says about ITSELF, before any card asks
 *  for a decision. */
@Composable
private fun PlanNotes(observedStore: Observed<AppStore>) {
    val store by observedStore
    val c = Theme.colors
    // Said ONCE: with the comeback card up, the card names the same drop.
    if (store.silentDecayAppliedForCurrentBreak && !store.shouldOfferComeback()) {
        Text(tr("A week without training — the plan starts a step lower. It catches up quickly."),
             style = dredfitFont(14.5f), color = c.ink2, modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
    }
    // An offer of rest, not a warning (#98) — accent fill, ink words.
    if (store.todayWouldExtendALongRun) {
        Text(tr("A workout today would be training day %lld in a row — a rest day lets the load settle.",
                store.wouldBeConsecutiveDay),
             style = dredfitFont(14f, Weight.medium), color = c.ink,
             modifier = Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 8.dp)
                 .background(c.accentSoft, RoundedCornerShape(14.dp)).padding(horizontal = 14.dp, vertical = 12.dp))
    }
}

/** One contextual question — never a questionnaire — routed into the handle. */
@Composable
private fun SuspectPrompt(suspect: Pattern, onEasier: () -> Unit, onFine: () -> Unit) {
    val c = Theme.colors
    Column(Modifier.fillMaxWidth().padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(tr("Tough workouts keep landing on %@.", tr(suspect.displayName)), style = dredfitFont(13.5f), color = c.ink2)
        // 24 apart and each answer 44 tall: the left one is the irreversible
        // of the pair (#193's floor).
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            for ((title, action) in listOf(tr("Make it easier") to onEasier, tr("It's fine") to onFine)) {
                Box(Modifier.heightIn(min = MinTarget).clickable(role = Role.Button, onClick = action),
                    contentAlignment = androidx.compose.ui.Alignment.Center) {
                    Text(title, style = dredfitFont(13.5f, Weight.medium), color = c.accentText)
                }
            }
        }
    }
}
