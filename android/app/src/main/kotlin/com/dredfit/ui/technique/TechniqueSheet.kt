//
//  Technique sheet: name, variation tag, the step below, three steps, two
//  common mistakes, "in life". Port of ios/Dredfit/Views/TechniqueSheet.swift
//  — addressed by (pattern, variation) because the probe offers a movement
//  that is not in the plan, and the easier-variation handle lives here,
//  offered ONLY where the sheet describes the upcoming workout (`planned`):
//  inside a running session a switch would move the state under the plan in
//  flight, and the rating would land on the pair.
//

package com.dredfit.ui.technique

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.store.AppStore
import com.dredfit.store.EasierStep
import com.dredfit.store.canMakeEasier
import com.dredfit.store.easierStep
import com.dredfit.store.markTechniqueOpened
import com.dredfit.store.nextSession
import com.dredfit.ui.Observed
import com.dredfit.ui.displayOf
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.DredfitSheet
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.LifeBenefit
import com.dredfit.workout.TechniqueTarget

@Composable
fun TechniqueSheet(target: TechniqueTarget, planned: Boolean, observedStore: Observed<AppStore>,
                   onDismiss: () -> Unit) {
    val store by observedStore
    val c = Theme.colors
    // Read from the STATE on the planned door, so "Switch" redraws this sheet
    // onto the movement it just chose; frozen to the target otherwise.
    val shownVariation = if (planned) store.engineState.position(target.pattern).variation else target.variation
    val variation = Library.at(target.pattern, shownVariation)
    val unit = if (planned) Library.unit(target.pattern, shownVariation) else target.unit
    val stepBelow = if (planned) store.easierStep(target.pattern) else null
    var pendingStepDown by remember { mutableStateOf<EasierStep?>(null) }

    // Spends Today's hint only when this sheet delivered what the SHOWN line
    // promised (TechniqueSheet.swift).
    LaunchedEffect(target) {
        val promisedARungBelow = store.nextSession.exercises.any { store.canMakeEasier(it.pattern) }
        if (stepBelow != null || !promisedARungBelow) observedStore.act { markTechniqueOpened() }
    }

    DredfitSheet(onDismiss) {
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp)) {
            Text(tr(variation.name), style = dredfitFont(28f, Weight.heavy, tracking = -0.5f), color = c.ink,
                 modifier = Modifier.padding(top = 14.dp).testTag("technique-title"))
            val range = if (unit == LoadUnit.reps) tr("4–15 reps") else tr("15–45 s")
            Text(tr("variation %lld of %lld · %@ · %@", shownVariation, Library.count(target.pattern),
                    tr(target.pattern.displayName), range),
                 style = dredfitFont(13f), color = c.ink2,
                 modifier = Modifier.padding(top = 10.dp).border(1.dp, c.hairline, CircleShape)
                     .padding(horizontal = 12.dp, vertical = 5.dp))
            if (stepBelow != null) {
                StepDown(stepBelow, unit, nowLine(store, target)) { pendingStepDown = stepBelow }
            }
            Kicker(tr("Technique"), Modifier.padding(top = 28.dp))
            TechniqueSteps(variation.steps.map { tr(it) })
            Kicker(tr("Common mistakes"), Modifier.padding(top = 18.dp))
            for (mistake in variation.mistakes) {
                Row(Modifier.padding(vertical = 13.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Box(Modifier.size(26.dp).background(c.accentSoft, CircleShape), contentAlignment = Alignment.Center) {
                        Text("✕", style = dredfitFont(11f, Weight.bold), color = c.accent)
                    }
                    Text(tr(mistake), style = dredfitFont(16.5f), color = c.ink2)
                }
            }
            Kicker(tr("life.kicker"), Modifier.padding(top = 18.dp))
            Text(tr(LifeBenefit.text(target.pattern, shownVariation)), style = dredfitFont(16.5f), color = c.ink2,
                 modifier = Modifier.padding(vertical = 11.dp).testTag("technique-life"))
        }
        PrimaryButton(tr("Got it"), tag = "technique-done",
                      modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp), onClick = onDismiss)
    }

    pendingStepDown?.let { step ->
        // The same guard the four skips carry: this plan has no undo. No
        // destructive role — a rung down is an ordinary answer to a day.
        DredfitAlert(
            title = tr("technique.stepDown.confirmTitle", tr(step.name)),
            message = tr("technique.stepDown.confirmBody"),
            actions = listOf(
                AlertAction(tr("Keep going"), tag = null, cancel = true) {},
                AlertAction(tr("technique.stepDown.switch"), tag = "technique-step-down-confirm") {
                    observedStore.act { makeEasier(target.pattern) }
                },
            ),
            onClose = { pendingStepDown = null },
        )
    }
}

/** The numbered steps both technique sheets draw. */
@Composable
fun TechniqueSteps(steps: List<String>) {
    val c = Theme.colors
    steps.forEachIndexed { index, step ->
        Row(Modifier.padding(vertical = 13.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(26.dp).background(c.ink, CircleShape), contentAlignment = Alignment.Center) {
                Text("${index + 1}", style = dredfitFont(13f, Weight.semibold), color = c.bg)
            }
            Text(step, style = dredfitFont(16.5f), color = c.ink)
        }
    }
}

/** "Now: 3×12" — today's dose of the movement the sheet describes, so the
 *  rung below is read against it. Null when the pattern is not in the
 *  session, which the planned door cannot produce. */
@Composable
private fun nowLine(store: AppStore, target: TechniqueTarget): String? {
    val ex = store.nextSession.exercises.firstOrNull { it.pattern == target.pattern } ?: return null
    return tr("technique.stepDown.now", displayOf(ex))
}

/** The handle: the block is NOT a button and the capsule is — a step down is
 *  one-way, so the target of the tap is the word, never the card. */
@Composable
private fun StepDown(step: EasierStep, unit: LoadUnit, now: String?, onSwitch: () -> Unit) {
    val c = Theme.colors
    val shown = displayOf(step.exercise)
    val dose = if (!step.unitChanged) shown
               else shown + " · " + (if (unit == LoadUnit.reps) tr("technique.stepDown.unitToHold")
                                         else tr("technique.stepDown.unitToReps"))
    val name = tr(step.name)
    val switchLabel = tr("technique.stepDown.a11ySwitch", name)
    Row(
        Modifier.padding(top = 18.dp).fillMaxWidth()
            .border(1.5.dp, c.hairline, RoundedCornerShape(16.dp))
            .padding(horizontal = 15.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (now != null) Text(now, style = dredfitFont(13f), color = c.ink2, modifier = Modifier.padding(bottom = 2.dp))
            Kicker(tr("technique.stepDown.kicker"))
            Text(name, style = dredfitFont(15.5f, Weight.semibold), color = c.ink)
            Text(dose, style = dredfitFont(13f), color = c.ink2)
        }
        Box(
            Modifier.heightIn(min = MinTarget).border(1.5.dp, c.hairline, CircleShape)
                .clickable(role = Role.Button, onClick = onSwitch)
                .semantics { contentDescription = switchLabel }
                .testTag("technique-step-down")
                .padding(horizontal = 18.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(tr("technique.stepDown.switch"), style = dredfitFont(14.5f, Weight.medium), color = c.accentText)
        }
    }
}
