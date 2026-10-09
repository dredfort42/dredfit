//
//  One screen for everything a workout earned. Port of
//  ios/Dredfit/Views/Workout/MilestoneView.swift: the headline steps down as
//  rows are added, the whole thing scrolls, and the accent rule sweeps in
//  unless the system asks for no animation. Share sends the card
//  (ui/progress/ShareCard.kt) with the curve up to this workout.
//

package com.dredfit.ui.workout

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import com.dredfit.ui.currentLocale
import com.dredfit.ui.progress.ShareCardFactory
import com.dredfit.ui.progress.shareCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.format.DateTimeFormatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.dredfit.core.Dose
import com.dredfit.core.EngineConfig
import com.dredfit.core.Library
import com.dredfit.core.LoadUnit
import com.dredfit.core.Pattern
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.LifeBenefit
import com.dredfit.workout.Milestone
import com.dredfit.workout.Retrospective

@Composable
fun MilestoneView(milestones: List<Milestone>, steps: List<Int>, retrospective: Retrospective?, onDone: () -> Unit) {
    val c = Theme.colors
    val headline = tr(ShareCardFactory.headline(milestones))
    val card = rememberMilestoneCard(milestones, steps, retrospective, headline)
    val headlineSize = when (milestones.size) {
        1 -> 34f
        2 -> 28f
        else -> 23f
    }
    // Drawn, not swept, when the system turns animations off — Reduce
    // Motion's Android counterpart. The rule ends in the same place either way.
    val context = LocalContext.current
    val sweep = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        val scale = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        if (scale == 0f) sweep.snapTo(1f) else sweep.animateTo(1f, tween(550, delayMillis = 100, easing = FastOutSlowInEasing))
    }
    Column(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight),
                   verticalArrangement = Arrangement.Center) {
                Box(Modifier.width(56.dp).height(3.dp).drawWithContent {
                    drawRect(c.accent, size = size.copy(width = size.width * sweep.value))
                })
                for (milestone in milestones) {
                    MilestoneRow(milestone, headlineSize, retrospective,
                        Modifier.padding(top = if (milestones.size > 2) 26.dp else 34.dp))
                }
            }
        }
        card?.let { ready ->
            // The outline is the whole button, so it owes 3:1 — targetStroke,
            // the Progress header's share ring's role.
            val shape = RoundedCornerShape(18.dp)
            Box(Modifier.fillMaxWidth().padding(bottom = 10.dp).heightIn(min = 52.dp).clip(shape)
                    .border(1.5.dp, c.targetStroke, shape)
                    .clickable(role = Role.Button) { shareCard(context, ready, headline) }.testTag("milestone-share"),
                contentAlignment = Alignment.Center) {
                Text(tr("Share"), style = dredfitFont(17f, Weight.semibold), color = c.ink)
            }
        }
        // Keyed, not literal: "Done" is taken by the workout's set button.
        PrimaryButton(tr("milestone.done"), tag = "milestone-done", modifier = Modifier.padding(bottom = 16.dp),
                      onClick = onDone)
    }
}

/** The card is rendered and written before the button appears, so the
 *  share sheet's preview shows what is about to be sent. The subline only
 *  when this workout IS an anniversary. Shared by the render and the
 *  preview, so they cannot drift. */
@Composable
private fun rememberMilestoneCard(milestones: List<Milestone>, steps: List<Int>, retrospective: Retrospective?,
                                  headline: String): ShareCardFactory.Card? {
    val context = LocalContext.current
    val locale = currentLocale()
    val date = DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(locale, "dMMMMy"), locale)
        .format(java.time.ZonedDateTime.now())
    val subline = if (milestones.any { it is Milestone.Jubilee }) {
        retrospective?.let { tr(it.comparisonLine) + "\n" + tr(it.sinceLine) }
    } else null
    var card by remember { mutableStateOf<ShareCardFactory.Card?>(null) }
    LaunchedEffect(headline, subline, steps, date) {
        if (milestones.isEmpty()) return@LaunchedEffect
        card = withContext(Dispatchers.Default) {
            ShareCardFactory.card(context, headline, ShareCardFactory.Slot.milestone, date, subline, steps)
        }
    }
    return card
}

@Composable
private fun MilestoneRow(milestone: Milestone, headlineSize: Float, retrospective: Retrospective?, modifier: Modifier) {
    val c = Theme.colors
    // The kicker labels the headline; it is not a separate thought.
    Column(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Kicker(kicker(milestone))
        Text(headline(milestone), style = dredfitFont(headlineSize, Weight.heavy, tracking = -0.5f), color = c.ink)
        caption(milestone)?.let { Text(it, style = dredfitFont(15f), color = c.ink2) }
        if (milestone is Milestone.SetBand) {
            // Both halves are true at every band transition: a set is added,
            // and the dose per set lands below the one already shown.
            Text(tr("Each set asks a little less — there's one more of them."), style = dredfitFont(15f),
                 color = c.ink2, modifier = Modifier.testTag("milestone-note"))
        }
        if (milestone is Milestone.VariationUp) {
            Text(tr(LifeBenefit.text(milestone.pattern, milestone.variation)), style = dredfitFont(15f),
                 color = c.ink2, modifier = Modifier.testTag("milestone-life"))
        }
        if (milestone is Milestone.Jubilee && retrospective != null) {
            Text(tr(retrospective.comparisonLine), style = dredfitFont(15f), color = c.ink2,
                 modifier = Modifier.testTag("jubilee-retro"))
            Text(tr(retrospective.sinceLine), style = dredfitFont(15f), color = c.ink2)
        }
    }
}

@Composable
private fun kicker(milestone: Milestone): String = when (milestone) {
    is Milestone.VariationUp -> tr("New variation")
    // The same movement grown, not a new one — and not "more volume": the
    // axis that moves is the sets.
    is Milestone.SetBand -> tr("More sets")
    is Milestone.Jubilee -> tr("Workout #%lld", milestone.workouts)
}

@Composable
private fun headline(milestone: Milestone): String = when (milestone) {
    is Milestone.VariationUp -> tr(milestone.exercise)
    is Milestone.SetBand -> tr("Now %lld sets", milestone.sets)
    is Milestone.Jubilee -> tr("%lld workouts behind you", milestone.workouts)
}

@Composable
private fun caption(milestone: Milestone): String? = when (milestone) {
    is Milestone.VariationUp -> tr(milestone.pattern.displayName) + " · " +
        tr("variation %lld of %lld", milestone.variation, Library.count(milestone.pattern)) + " · " +
        entryPlan(milestone.pattern, milestone.variation)
    is Milestone.SetBand -> tr(milestone.pattern.displayName) + " · " + tr(milestone.exercise)
    is Milestone.Jubilee -> null
}

/** What entering a variation costs, said where it is celebrated: a passed
 *  probe enters at three sets of the grid's floor and nothing else. */
@Composable
private fun entryPlan(pattern: Pattern, variation: Int): String {
    val unit = Library.unit(pattern, variation)
    val dose = Dose.grid(unit).min
    val sets = EngineConfig.setsBase
    val side = if (Library.sides(pattern, variation) > 1) tr(" /side") else ""
    return when (unit) {
        LoadUnit.reps -> tr("we start at %lld × %lld%@", sets, dose, side)
        LoadUnit.hold -> tr("we start at %lld × %lld s%@", sets, dose, side)
    }
}
