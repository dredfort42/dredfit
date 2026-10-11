//
//  The reduced technique sheet for warm-up and cool-down positions: name,
//  block capsule, steps, and the way to set a position aside. The flow
//  freezes the countdown while it is open. Port of
//  ios/Dredfit/Views/Workout/PositionTechniqueSheet.swift.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.dredfit.store.AppStore
import com.dredfit.store.MAX_HIDDEN_BLOCK_MOVES
import com.dredfit.store.canHideAnotherBlockMove
import com.dredfit.store.setBlockMoveHidden
import com.dredfit.ui.Observed
import com.dredfit.ui.technique.TechniqueSteps
import com.dredfit.ui.theme.DredfitSheet
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.PairedSecondary
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.Cooldown
import com.dredfit.workout.CooldownPosition
import com.dredfit.workout.Warmup
import com.dredfit.workout.WarmupHalves
import com.dredfit.workout.WarmupMove
import com.dredfit.workout.Words

/** Built from a warm-up move or a cool-down position, so the sheet itself
 *  knows about neither. */
data class PositionTechnique(val id: String, val name: Words, val capsule: Words, val steps: List<Words>) {
    companion object {
        /** A split move names the length of ONE half: its slot is two halves
         *  with the switch between, and "warm-up · 30 s" would be the number
         *  of neither. */
        fun of(move: WarmupMove): PositionTechnique {
            val capsule = when (move.halves) {
                WarmupHalves.sides ->
                    Words.keyed("positionSheet.warmupPerSide", "warm-up · %lld s per side", Warmup.halfSeconds)
                WarmupHalves.directions ->
                    Words.keyed("positionSheet.warmupPerDirection", "warm-up · %lld s each way", Warmup.halfSeconds)
                null -> Words.keyed("positionSheet.warmup", "warm-up · %lld s", Warmup.moveSeconds)
            }
            return PositionTechnique(move.id, move.name, capsule, move.steps)
        }

        fun of(position: CooldownPosition): PositionTechnique {
            val capsule = if (position.perSide) {
                Words.keyed("positionSheet.cooldownPerSide", "cool-down · %lld s per side", Cooldown.sideSeconds)
            } else {
                Words.keyed("positionSheet.cooldown", "cool-down · %lld s", Cooldown.positionSeconds)
            }
            return PositionTechnique(position.id, position.name, capsule, position.steps)
        }
    }
}

@Composable
fun PositionTechniqueSheet(technique: PositionTechnique, observedStore: Observed<AppStore>, onDismiss: () -> Unit) {
    val store by observedStore
    val c = Theme.colors
    DredfitSheet(onDismiss) {
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp)) {
            Text(tr(technique.name), style = dredfitFont(28f, Weight.heavy, tracking = -0.5f), color = c.ink,
                 modifier = Modifier.padding(top = 14.dp))
            Text(tr(technique.capsule), style = dredfitFont(13f), color = c.ink2,
                 modifier = Modifier.padding(top = 10.dp).border(1.dp, c.hairline, CircleShape)
                     .padding(horizontal = 12.dp, vertical = 5.dp))
            Kicker(tr("Technique"), Modifier.padding(top = 28.dp))
            TechniqueSteps(technique.steps.map { tr(it) })
            // "Not this one", for good: without it the cheap way out would be
            // to skip the whole block. The tap closes the sheet, because the
            // answer to "don't show me this" is not to go on showing it.
            Column(Modifier.padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val canHide = store.canHideAnotherBlockMove
                PairedSecondary(tr("Don't show this again"), tag = "position-technique-hide",
                                modifier = Modifier.fillMaxWidth().alpha(if (canHide) 1f else 0.4f),
                                enabled = canHide) {
                    observedStore.act { setBlockMoveHidden(technique.id, true) }
                    onDismiss()
                }
                // The cap is named rather than enforced in silence.
                Text(if (canHide) tr("Something else takes its place.")
                     else tr("%lld is the most that can be set aside. Bring one back to make room.",
                             MAX_HIDDEN_BLOCK_MOVES),
                     style = dredfitFont(13f), color = c.ink2)
            }
            SetAsideList(observedStore)
        }
        // Its own name: this sheet opens OVER a running block, so a test that
        // closed the wrong sheet would leave the block running.
        PrimaryButton(tr("Got it"), tag = "position-technique-done",
                      modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp), onClick = onDismiss)
    }
}

/** The way back, and the reason the button above is not a one-way door: a
 *  move set aside never reaches the block again, so its own sheet can no
 *  longer be opened. Sorted by name so the rows do not reshuffle. */
@Composable
private fun SetAsideList(observedStore: Observed<AppStore>) {
    val store by observedStore
    val c = Theme.colors
    val entries = store.settings.hiddenBlockMoveIDs.mapNotNull { id ->
        // An id from a build that knew a move this one does not has nothing
        // to name and nothing to offer.
        (Warmup.nameOfMove(id) ?: Cooldown.nameOfPosition(id))?.let { id to it }
    }.map { (id, name) -> id to tr(name) }.sortedBy { it.second }
    if (entries.isEmpty()) return
    Kicker(tr("Not shown any more"), Modifier.padding(top = 26.dp))
    for ((id, name) in entries) {
        Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(name, style = dredfitFont(15f), color = c.ink, modifier = Modifier.weight(1f))
            val restore = tr("Bring back %@", name)
            Text(tr("Bring back"), style = dredfitFont(14.5f, Weight.medium), color = c.ink2,
                 modifier = Modifier
                     .heightIn(min = MinTarget)
                     .clickable(role = Role.Button) { observedStore.act { setBlockMoveHidden(id, false) } }
                     .semantics { contentDescription = restore }
                     .testTag("position-technique-restore-$id")
                     .padding(start = 8.dp, top = 12.dp))
        }
    }
}
