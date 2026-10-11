//
//  The three screens of a guided block: the "Get ready" transition, a running
//  warm-up move and a running cool-down position. Port of
//  ios/Dredfit/Views/Workout/BlockScreens.swift — layout only, each a pure
//  function of what it is handed; the flow keeps the state and the clocks.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.SplitStageWords
import com.dredfit.workout.WarmupHalves
import com.dredfit.workout.Words

/** The block-level escape's words and name, ONE definition for the three
 *  places it appears. The identifier is stated: the title is localized. */
val GuidedBlock.skipTitle: Words
    get() = when (this) {
        GuidedBlock.warmup -> Words.of("Skip warm-up")
        GuidedBlock.cooldown -> Words.keyed("cooldown.skip", "Skip cool-down")
    }

val GuidedBlock.skipIdentifier: String
    get() = when (this) {
        GuidedBlock.warmup -> "skip-warmup"
        GuidedBlock.cooldown -> "skip-cooldown"
    }

@Composable
fun GetReadyScreen(name: String, remaining: Int, index: Int, count: Int, countdownTag: String, block: GuidedBlock,
                   paused: Boolean, countingIn: Boolean, onTechnique: () -> Unit, onStart: () -> Unit,
                   onPauseToggle: () -> Unit, onSkipPosition: () -> Unit, onSkipBlock: () -> Unit) {
    val spoken = tr("Get ready: %@", name)
    BlockLayout(
        content = {
            BlockPositionName(name, Modifier.semantics { contentDescription = spoken })
            TechniqueButton(Modifier.padding(top = 10.dp), onClick = onTechnique)
            Box(Modifier.padding(top = 20.dp)) {
                CountdownNumber(remaining, countdownTag, paused, caption = tr("Get ready"))
            }
            Box(Modifier.padding(top = 12.dp)) { BlockPauseButton(paused, onPauseToggle) }
            Box(Modifier.padding(top = 22.dp)) { BlockDots(count, index, upcoming = true) }
            Box(Modifier.padding(top = 8.dp)) { PositionSkipButton(onSkipPosition) }
        },
        footer = {
            // Frozen, "I'm ready" would run a position the person just
            // stopped; inside the count-in it is spent. Hidden, not removed:
            // the escapes must not jump up under the thumb.
            if (paused || countingIn) {
                Spacer(Modifier.fillMaxWidth().height(56.dp))
            } else {
                PrimaryButton(tr("I'm ready"), tag = "get-ready-start", onClick = onStart)
            }
            // 20, not less: under "I'm ready" stands a button of the same width
            // and height that ends the whole block.
            Spacer(Modifier.height(20.dp))
            BlockSkipButton(tr(block.skipTitle), tag = block.skipIdentifier, modifier = Modifier.fillMaxWidth(),
                            onClick = onSkipBlock)
            Spacer(Modifier.height(20.dp))
        },
    )
}

/** A running warm-up move or cool-down position: one screen, two blocks. */
@Composable
fun RunningPositionScreen(name: String, halves: WarmupHalves?, stage: GuidedStage, remaining: Int, index: Int,
                          count: Int, countdownTag: String, block: GuidedBlock, paused: Boolean,
                          onTechnique: () -> Unit, onPauseToggle: () -> Unit, onSkipPosition: () -> Unit,
                          onSkipBlock: () -> Unit) {
    BlockLayout(
        content = {
            BlockPositionName(name)
            if (halves != null) Box(Modifier.padding(top = 6.dp)) { SplitStageLine(stage, halves) }
            TechniqueButton(Modifier.padding(top = 10.dp), onClick = onTechnique)
            Box(Modifier.padding(top = 20.dp)) { CountdownNumber(remaining, countdownTag, paused) }
            Box(Modifier.padding(top = 12.dp)) { BlockPauseButton(paused, onPauseToggle) }
            Box(Modifier.padding(top = 22.dp)) { BlockDots(count, index) }
            Box(Modifier.padding(top = 8.dp)) { PositionSkipButton(onSkipPosition) }
        },
        footer = {
            BlockSkipButton(tr(block.skipTitle), tag = block.skipIdentifier, modifier = Modifier.fillMaxWidth(),
                            onClick = onSkipBlock)
            Spacer(Modifier.height(20.dp))
        },
    )
}

/**
 * The line a split position shows over its countdown. The switch is a TIER
 * LOUDER than the second half after it — 17 against 14 — because it is the
 * one moment a split position asks for something new.
 */
@Composable
private fun SplitStageLine(stage: GuidedStage, halves: WarmupHalves) {
    val c = Theme.colors
    val words = SplitStageWords(halves)
    when (stage) {
        GuidedStage.switchPause -> Text(tr(words.switching), style = dredfitFont(17f, Weight.semibold), color = c.accentText)
        GuidedStage.secondHalf -> Text(tr(words.secondHalf), style = dredfitFont(14f, Weight.semibold), color = c.accentText)
        GuidedStage.getReady, GuidedStage.whole, GuidedStage.firstHalf ->
            Text(tr(words.everyHalf), style = dredfitFont(14f), color = c.ink2)
    }
}

/** Content centred in whatever room is left, escapes pinned under it; it
 *  scrolls rather than clips at the largest text sizes. */
@Composable
private fun BlockLayout(content: @Composable ColumnScope.() -> Unit, footer: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight),
                   horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                content()
            }
        }
        footer()
    }
}

/** The long es/pt-BR names wrap to three lines at the largest sizes; let them. */
@Composable
private fun BlockPositionName(name: String, modifier: Modifier = Modifier) {
    Text(name, style = dredfitFont(23f, Weight.bold), color = Theme.colors.ink, textAlign = TextAlign.Center,
         modifier = modifier.widthIn(max = 300.dp))
}
