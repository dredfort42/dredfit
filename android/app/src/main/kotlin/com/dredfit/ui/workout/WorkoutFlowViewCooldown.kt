//
//  The screens of the cool-down block (issue #28); the block itself is
//  WorkoutSessionCooldown.kt. Port of
//  ios/Dredfit/Views/Workout/WorkoutFlowView+Cooldown.swift.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.dredfit.store.AppStore
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.GetReady
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.beginCooldown
import com.dredfit.workout.cooldownIntroMinutes
import com.dredfit.workout.countIn
import com.dredfit.workout.declineCooldown
import com.dredfit.workout.endBlockReentry
import com.dredfit.workout.finishCooldown
import com.dredfit.workout.rebaseCooldownOnComposition
import com.dredfit.workout.reentering
import com.dredfit.workout.skipPosition
import com.dredfit.workout.toggleBlockPause

/** The cool-down is OFFERED, not started, with no consequence for saying no. */
@Composable
fun CooldownIntroView(observed: Observed<WorkoutSession>) {
    val flow by observed
    val c = Theme.colors
    BlockOffer(
        title = tr("Cool-down"),
        lines = {
            // The third sentence says what the block IS: some positions follow
            // the movements performed today.
            Text(tr("The work is done. A few minutes of stretching helps it settle. Some of the positions follow the movements you did today."),
                 style = dredfitFont(15f), color = c.ink2, modifier = Modifier.padding(top = 8.dp))
            Text(tr("%lld positions · about %lld min", flow.cooldownPositions.size, flow.cooldownIntroMinutes),
                 style = dredfitFont(13.5f), color = c.ink2, modifier = Modifier.padding(top = 6.dp))
        },
        start = tr("Start the cool-down"), startTag = "cooldown-start", onStart = { observed.act { beginCooldown() } },
        decline = tr(GuidedBlock.cooldown.skipTitle), declineTag = "cooldown-intro-skip",
        onDecline = { observed.act { declineCooldown() } },
    )
}

@Composable
fun CooldownView(observed: Observed<WorkoutSession>, observedStore: Observed<AppStore>,
                 openTechnique: (PositionTechnique) -> Unit) {
    val flow by observed
    val store by observedStore
    // A position set aside from its sheet recomposes the block; the slot
    // restarts on its own transition.
    val hidden = store.settings.hiddenBlockMoveIDs
    val previous = remember { arrayOf(hidden) }
    LaunchedEffect(hidden) {
        if (previous[0] != hidden) observed.act { rebaseCooldownOnComposition() }
        previous[0] = hidden
    }
    val position = flow.cooldownPositions[flow.cooldown.index]
    val technique = { openTechnique(PositionTechnique.of(flow.cooldownPositions[flow.cooldown.index])) }
    if (flow.reentering || flow.cooldown.stage == GuidedStage.getReady) {
        GetReadyScreen(
            name = tr(position.name),
            remaining = if (flow.reentering) flow.blockPause.reentryRemaining else flow.cooldown.clock.remaining,
            index = flow.cooldown.index, count = flow.cooldownPositions.size,
            countdownTag = if (flow.reentering) "reentry-countdown" else "getready-countdown",
            block = GuidedBlock.cooldown, paused = flow.blockPause.isHeld,
            countingIn = !flow.reentering && flow.cooldown.clock.remaining <= GetReady.countInSeconds,
            onTechnique = technique,
            onStart = { observed.act { if (reentering) endBlockReentry() else countIn(GuidedBlock.cooldown) } },
            onPauseToggle = { observed.act { toggleBlockPause() } },
            onSkipPosition = { observed.act { skipPosition(GuidedBlock.cooldown) } },
            onSkipBlock = { observed.act { finishCooldown() } },
        )
    } else {
        RunningPositionScreen(
            name = tr(position.name), halves = position.halves, stage = flow.cooldown.stage,
            remaining = flow.cooldown.clock.remaining, index = flow.cooldown.index,
            count = flow.cooldownPositions.size, countdownTag = "cooldown-countdown", block = GuidedBlock.cooldown,
            paused = flow.blockPause.isHeld, onTechnique = technique,
            onPauseToggle = { observed.act { toggleBlockPause() } },
            onSkipPosition = { observed.act { skipPosition(GuidedBlock.cooldown) } },
            onSkipBlock = { observed.act { finishCooldown() } },
        )
    }
}
