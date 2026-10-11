//
//  The screens of the warm-up block; the block itself is
//  WorkoutSessionWarmup.kt. Port of
//  ios/Dredfit/Views/Workout/WorkoutFlowView+Warmup.swift.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.dredfit.ui.Observed
import com.dredfit.ui.listFormatted
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.beginWarmup
import com.dredfit.workout.countIn
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.endBlockReentry
import com.dredfit.workout.finishWarmup
import com.dredfit.workout.rebaseWarmupOnComposition
import com.dredfit.workout.reentering
import com.dredfit.workout.skipPosition
import com.dredfit.workout.toggleBlockPause
import com.dredfit.workout.warmupIntroMinutes
import com.dredfit.workout.warmupMove
import com.dredfit.workout.warmupMoves

/** The warm-up is OFFERED, not started — and the offer says what it offers:
 *  the composition changes from session to session. */
@Composable
fun WarmupIntroView(observed: Observed<WorkoutSession>) {
    val flow by observed
    val c = Theme.colors
    BlockOffer(
        title = tr("Warm-up"),
        lines = {
            Text(tr("A few easy minutes to get the body ready. Skip it if you are already warm."),
                 style = dredfitFont(15f), color = c.ink2, modifier = Modifier.padding(top = 8.dp))
            Text(tr("%lld positions · about %lld min", flow.warmupMoves.size, flow.warmupIntroMinutes),
                 style = dredfitFont(13.5f), color = c.ink2, modifier = Modifier.padding(top = 6.dp))
            Text(listFormatted(flow.warmupMoves.map { tr(it.name) }), style = dredfitFont(13.5f), color = c.ink2,
                 modifier = Modifier.padding(top = 10.dp))
            Text(tr("Any position can be skipped as you go."), style = dredfitFont(13.5f), color = c.ink2,
                 modifier = Modifier.padding(top = 6.dp))
        },
        start = tr("Start the warm-up"), startTag = "warmup-start", onStart = { observed.act { beginWarmup() } },
        decline = tr(GuidedBlock.warmup.skipTitle), declineTag = "warmup-intro-skip",
        onDecline = { observed.act { declineWarmup() } },
    )
}

/** The offer screen both blocks share: centred while it fits, scrolling at
 *  the largest text sizes so the decline never leaves the bottom. */
@Composable
fun BlockOffer(title: String, lines: @Composable ColumnScope.() -> Unit, start: String, startTag: String,
               onStart: () -> Unit, decline: String, declineTag: String, onDecline: () -> Unit) {
    val c = Theme.colors
    BoxWithConstraints(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight)
                   .padding(horizontal = 20.dp),
               verticalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.padding(top = 40.dp)) {
                Text(title, style = dredfitFont(32f, Weight.heavy, tracking = -0.5f), color = c.ink)
                lines()
            }
            Column(Modifier.padding(top = 24.dp)) {
                PrimaryButton(start, tag = startTag, onClick = onStart)
                // No question on this one: the offer's own "no" is the answer
                // it asked for.
                Box(Modifier.fillMaxWidth().heightIn(min = MinTarget).padding(top = 4.dp)
                        .clickable(role = Role.Button, onClick = onDecline).testTag(declineTag),
                    contentAlignment = Alignment.Center) {
                    Text(decline, style = dredfitFont(14.5f), color = c.ink2)
                }
            }
        }
    }
}

/** The way back in from a pause wears the transition's screen: it is the
 *  same beat — the name, the 3-2-1, then the position. */
@Composable
fun WarmupView(observed: Observed<WorkoutSession>, openTechnique: (PositionTechnique) -> Unit) {
    val flow by observed
    // The OLD list is what the rebase needs: `warmupMoves` is computed, so
    // by the time a change is seen it already answers with the new one.
    val ids = flow.warmupMoves.map { it.id }
    val previous = remember { arrayOf(ids) }
    LaunchedEffect(ids) {
        if (previous[0] != ids) observed.act { rebaseWarmupOnComposition(previous[0]) }
        previous[0] = ids
    }
    val move = flow.warmupMove
    val technique = { openTechnique(PositionTechnique.of(flow.warmupMove)) }
    if (flow.reentering || flow.warmup.stage == com.dredfit.workout.GuidedStage.getReady) {
        GetReadyScreen(
            name = tr(move.name),
            remaining = if (flow.reentering) flow.blockPause.reentryRemaining else flow.warmup.clock.remaining,
            index = flow.warmup.index, count = flow.warmupMoves.size,
            countdownTag = if (flow.reentering) "reentry-countdown" else "getready-countdown",
            block = GuidedBlock.warmup, paused = flow.blockPause.isHeld,
            // The way back in is not a transition to cut: its "I'm ready"
            // ends it outright, so it keeps one.
            countingIn = !flow.reentering && flow.warmup.clock.remaining <= GetReady.countInSeconds,
            onTechnique = technique,
            onStart = { observed.act { if (reentering) endBlockReentry() else countIn(GuidedBlock.warmup) } },
            onPauseToggle = { observed.act { toggleBlockPause() } },
            onSkipPosition = { observed.act { skipPosition(GuidedBlock.warmup) } },
            onSkipBlock = { observed.act { finishWarmup() } },
        )
    } else {
        RunningPositionScreen(
            name = tr(move.name), halves = move.halves, stage = flow.warmup.stage,
            remaining = flow.warmup.clock.remaining, index = flow.warmup.index, count = flow.warmupMoves.size,
            countdownTag = "warmup-countdown", block = GuidedBlock.warmup, paused = flow.blockPause.isHeld,
            onTechnique = technique,
            onPauseToggle = { observed.act { toggleBlockPause() } },
            onSkipPosition = { observed.act { skipPosition(GuidedBlock.warmup) } },
            onSkipBlock = { observed.act { finishWarmup() } },
        )
    }
}
