//
//  The work screen — the one a set is actually performed on. Port of
//  ios/Dredfit/Views/Workout/WorkoutFlowView+Work.swift; what a tap on it does
//  is `WorkoutSession`'s. The three rules the iOS view keeps in its body —
//  what the caption under the big number says, how loud it is, and the
//  set's own number under the dots — are plain Kotlin here (`WorkCaption`),
//  held by WorkCaptionTest.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.LoadUnit
import com.dredfit.store.AppStore
import com.dredfit.store.showsDifferentNumberHint
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.ProbeOutcome
import com.dredfit.workout.SetFacts
import com.dredfit.workout.TechniqueTarget
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.Words
import com.dredfit.workout.commitSetEdit
import com.dredfit.workout.completeSet
import com.dredfit.workout.holdExerciseIntro
import com.dredfit.workout.holdStopRecords
import com.dredfit.workout.holdUnderWay
import com.dredfit.workout.probeOutcome
import com.dredfit.workout.startAdjusting
import com.dredfit.workout.startDeclaringHoldTime
import com.dredfit.workout.startHold
import com.dredfit.workout.startHoldExercise
import com.dredfit.workout.stopHoldEarly
import com.dredfit.workout.targetInForce
import com.dredfit.workout.workNumber

/** The slot under the big number, and how loud it is. */
object WorkCaption {

    /** Three tiers: a STATE accented at the slot's size, "per side" a tier
     *  louder — the one word that changes what the big number means — and
     *  the plain unit. */
    enum class Emphasis(val size: Float, val weight: FontWeight, val accented: Boolean) {
        State(17f, Weight.semibold, true),
        Running(17f, Weight.medium, false),
        PerSide(23f, Weight.semibold, true),
        Plain(17f, Weight.medium, false),
    }

    /** While the number is a countdown the slot names the STATE, not the
     *  unit — the word is read from 1.5-2 m off a phone on the floor. A
     *  running hold names the DIRECTION. Otherwise the unit, with the count
     *  passed so the word agrees with the number it does not print. */
    fun text(flow: WorkoutSession): Words {
        if (flow.holdCountingIn) return Words.of("Get ready")
        if (flow.holdSwitchPausing) return Words.of("Switch sides")
        if (flow.holding) return Words.of("s left")
        val current = flow.current
        return when {
            current.unit == LoadUnit.reps && !current.perSide -> Words.of("%lld reps", flow.workNumber)
            current.unit == LoadUnit.reps -> Words.of("%lld reps per side", flow.workNumber)
            !current.perSide -> Words.of("seconds")
            else -> Words.of("seconds per side")
        }
    }

    fun emphasis(flow: WorkoutSession): Emphasis = when {
        flow.holdCountingIn || flow.holdSwitchPausing -> Emphasis.State
        flow.holding -> Emphasis.Running
        flow.current.perSide -> Emphasis.PerSide
        else -> Emphasis.Plain
    }

    /** This set's own number, nothing when it is the plan — and only for a
     *  set with a number on record: ahead of everything recorded `inForce`
     *  carries a shortfall down, and "actual" would stand over a set nobody
     *  has performed. */
    fun setActual(flow: WorkoutSession): Int? {
        if (flow.setIndex >= (flow.actuals[flow.exercise.pattern]?.size ?: 0)) return null
        return SetFacts.offPlan(flow.actuals, flow.exercise, set = flow.setIndex)
    }

    /** Whether the set's number is worth printing: asked of the plan and the
     *  record, never of a declared time. */
    fun uneven(flow: WorkoutSession): Boolean =
        flow.exercise.loads != null || SetFacts.offPlan(flow.actuals, flow.exercise, set = flow.setIndex) != null
}

@Composable
fun WorkView(observed: Observed<WorkoutSession>, observedStore: Observed<AppStore>,
             openTechnique: (TechniqueTarget) -> Unit, askSkip: (SkipConfirmation) -> Unit) {
    val flow by observed
    val store by observedStore
    val c = Theme.colors
    val current = flow.current
    val underWay = flow.holdUnderWay
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        if (current.isProbe) {
            // The badge is the whole announcement. ink on accentSoft: the
            // accent is the fill, and the word is a word (I-21).
            Text(tr("Probe").uppercase(), style = dredfitFont(11f, Weight.heavy, tracking = 0.6f), color = c.ink,
                 modifier = Modifier.padding(bottom = 8.dp).background(c.accentSoft, CircleShape)
                     .padding(horizontal = 10.dp, vertical = 4.dp).testTag("probe-badge"))
        }
        Text(tr(current.name), style = dredfitFont(23f, Weight.bold), color = c.ink, textAlign = TextAlign.Center,
             modifier = Modifier.widthIn(max = 300.dp))
        // Never while the clock is on the person: the sheet would cost the set
        // it describes. Hidden with its height kept, so nothing jumps.
        TechniqueButton(Modifier.padding(top = 10.dp).alpha(if (underWay) 0f else 1f)
                            .then(if (underWay) Modifier.semantics { hideFromAccessibility() } else Modifier),
                        enabled = !underWay) { openTechnique(current.target) }

        val caption = tr(WorkCaption.text(flow))
        val emphasis = WorkCaption.emphasis(flow)
        val number = flow.workNumber
        val spoken = "$number $caption"
        Column(Modifier.padding(top = 20.dp).clearAndSetSemantics { contentDescription = spoken },
               horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            // Accent during a side switch: the phone is on the floor by then,
            // and colour on a 13 mm digit survives the distance a word does not.
            Text("$number", style = dredfitFont(112f, Weight.heavy, cap = 150f, tracking = -4f, monospacedDigit = true),
                 color = if (flow.holdSwitchPausing) c.accentText else c.ink)
            Text(caption, style = dredfitFont(emphasis.size, emphasis.weight), textAlign = TextAlign.Center,
                 color = if (emphasis.accented) c.accentText else c.ink2)
        }

        SetDots(flow, Modifier.padding(top = 30.dp))

        Box(Modifier.padding(top = 10.dp)) {
            when {
                flow.holdExerciseIntro && flow.exercise.sets > 1 ->
                    Text(tr("%lld sets · %lld s rest between", flow.exercise.sets, flow.exercise.restSetSec),
                         style = dredfitFont(14f, monospacedDigit = true), color = c.ink2,
                         modifier = Modifier.testTag("hold-sets-and-rest"))
                current.isProbe -> ProbeCaption(flow.probeOutcome)
                else -> WorkStatusCaption(secondSide = flow.holdSecondSide, actual = WorkCaption.setActual(flow),
                                          setIndex = flow.setIndex, sets = flow.totalSets,
                                          planned = flow.targetInForce, uneven = WorkCaption.uneven(flow))
            }
        }

        Spacer(Modifier.weight(1f))

        if (flow.editing == null) {
            // The FIRST exercise, reps only, until the control has been used:
            // the door this names is how a movement in reps reports a number.
            if (store.showsDifferentNumberHint && flow.exIndex == 0 && current.unit == LoadUnit.reps) {
                val spent = flow.actuals[flow.exercise.pattern] != null
                val hidden = underWay || spent
                Text(tr("More or fewer than planned? Tap “Went differently” — the next plan starts from your number."),
                     style = dredfitFont(14f), color = c.ink2, textAlign = TextAlign.Center,
                     modifier = Modifier.padding(bottom = 18.dp).alpha(if (hidden) 0f else 1f)
                         .then(if (hidden) Modifier.semantics { hideFromAccessibility() } else Modifier))
            }
            flow.maximumWarning?.let { warning ->
                Text(tr(warning), style = dredfitFont(14f, Weight.medium), color = c.ink,
                     modifier = Modifier.fillMaxWidth().padding(bottom = 18.dp)
                         .background(c.accentSoft, RoundedCornerShape(14.dp))
                         .padding(horizontal = 14.dp, vertical = 12.dp).testTag("maximum-note"))
            }
        }

        // The entry opens IN THE SLOT of the button that opens it.
        when {
            flow.editing != null -> Box(Modifier.padding(bottom = 18.dp)) {
                AdjustPanel(flow.adjustValue, current.unit, range = null,
                            onChange = { v -> observed.act { adjustValue = v } },
                            onConfirm = { observed.act { commitSetEdit() } })
            }
            current.unit == LoadUnit.hold && !flow.holdSettled -> {
                if (flow.holdExerciseIntro) {
                    // What the one tap buys, said before it is taken — and
                    // only the channel that is actually there.
                    Text(if (store.settings.soundsEnabled)
                             tr("Runs on its own from here — sound counts you in and out. Put the phone down.")
                         else tr("Runs on its own from here — the countdown stays on the screen. Sound is off in Settings."),
                         style = dredfitFont(14f), color = c.ink2, textAlign = TextAlign.Center,
                         modifier = Modifier.padding(bottom = 18.dp).testTag("hold-autorun-promise"))
                    Box(Modifier.padding(bottom = 18.dp)) {
                        SetHoldTimeButton { observed.act { startDeclaringHoldTime() } }
                    }
                }
            }
            else -> Box(Modifier.padding(bottom = 18.dp).alpha(if (underWay) 0f else 1f)
                            .then(if (underWay) Modifier.semantics { hideFromAccessibility() } else Modifier)) {
                WentDifferentlyButton(enabled = !underWay) { observed.act { startAdjusting() } }
            }
        }

        PrimaryControl(observed)

        // No adjusting or skipping mid-hold, and none once a settled hold is
        // behind: the set was performed and its number is on the screen.
        val escapesHidden = underWay || flow.holdSettled
        val skipKind = flow.setSkipKind()
        val escape = flow.exerciseEscape()
        ExerciseActionsRow(
            onSkipSet = skipKind?.let { kind -> { askSkip(SkipConfirmation(kind) { observed.act { perform(kind) } }) } },
            skipsProbe = flow.onProbeSet,
            escape = escape?.let { e -> e to { askSkip(SkipConfirmation(e.kind) { observed.act { perform(e.kind) } }) } },
            modifier = Modifier.padding(top = 18.dp, bottom = 10.dp).alpha(if (escapesHidden) 0f else 1f)
                .then(if (escapesHidden) Modifier.semantics { hideFromAccessibility() } else Modifier),
            enabled = !escapesHidden,
        )
    }
}

/** The primary control, by what the set is doing. */
@Composable
private fun PrimaryControl(observed: Observed<WorkoutSession>) {
    val flow by observed
    when {
        flow.current.unit != LoadUnit.hold ->
            PrimaryButton(tr("Done"), tag = "exercise-done") { observed.act { completeSet() } }
        // The control names the figure it will write.
        flow.holding -> HoldStopButton(flow.holdStopRecords) { observed.act { stopHoldEarly() } }
        // A count-in is armed already: a second tap on the slot must land on
        // nothing — the height stays, the control does not.
        flow.holdSwitchPausing || flow.holdCountingIn -> PrimarySpacer()
        // The probe's hold is behind; this tap only logs it.
        flow.holdSettled -> PrimaryButton(tr("Done"), tag = "exercise-done") { observed.act { completeSet() } }
        // ONE set: a Stop inside the grace hands an armed set back, and the
        // probe is a movement the auto-run does not start for you.
        flow.holdAutoRun || flow.current.isProbe ->
            PrimaryButton(tr("Start hold"), tag = "hold-start") { observed.act { startHold() } }
        // One tap for the whole exercise.
        else -> PrimaryButton(tr("Start exercise"), tag = "hold-start-exercise") { observed.act { startHoldExercise() } }
    }
}

/** The set dots: done in ink, under way in accent, ahead in ink2 — and the
 *  probe's dot hollow: the same session, not the same movement. */
@Composable
private fun SetDots(flow: WorkoutSession, modifier: Modifier) {
    val c = Theme.colors
    val dot = scaledDot()
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (i in 0 until flow.totalSets) {
            val probeDot = flow.exercise.probe != null && i == flow.exercise.sets
            if (probeDot) {
                Box(Modifier.size(dot).border(2.dp, c.accent, CircleShape))
            } else {
                val fill = when {
                    i < flow.setIndex -> c.ink
                    i == flow.setIndex -> c.accent
                    else -> c.ink2
                }
                Box(Modifier.size(dot).background(fill, CircleShape))
            }
        }
    }
}

/** What the probe set says under its number. Every outcome but a pass is
 *  NEUTRAL: staying on a movement you can already do is not a failure. */
@Composable
private fun ProbeCaption(outcome: ProbeOutcome?) {
    val c = Theme.colors
    when (outcome) {
        is ProbeOutcome.Passed -> Text(tr("Next time: %@", tr(outcome.name)), style = dredfitFont(14f, Weight.semibold),
                                       color = c.accentText, textAlign = TextAlign.Center,
                                       modifier = Modifier.testTag("probe-passed"))
        is ProbeOutcome.PlanMoves -> Text(tr("Next time: %@", tr(outcome.name)), style = dredfitFont(14f),
                                          color = c.ink2, textAlign = TextAlign.Center,
                                          modifier = Modifier.testTag("probe-plan-moves"))
        ProbeOutcome.Stays -> Text(tr("Not this time — the plan stays as it is."), style = dredfitFont(14f),
                                   color = c.ink2, textAlign = TextAlign.Center,
                                   modifier = Modifier.testTag("probe-stays"))
        null -> Text(tr("One set to try it."), style = dredfitFont(14f), color = c.ink2, textAlign = TextAlign.Center)
    }
}
