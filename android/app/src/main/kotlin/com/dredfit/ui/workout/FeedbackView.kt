//
//  One tap to rate the workout. Port of
//  ios/Dredfit/Views/Workout/FeedbackView.swift: three EQUAL cards (a
//  highlighted "On plan" would read as the correct answer), captions that
//  promise a direction and never an amount, and "Easy, could do more" only
//  for a plan finished in full (`SetFacts.didFullPlan`) — with the sentence
//  that says why when it is spent. The rows under the cards say what the
//  rating does NOT reach; which rows there are is `FeedbackSummary`, plain
//  Kotlin, so a JVM test holds it.
//

package com.dredfit.ui.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.FeedbackResult
import com.dredfit.core.Pattern
import com.dredfit.core.Session
import com.dredfit.core.SessionExercise
import com.dredfit.core.roundedAwayFromZero
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.RaiseLabel
import com.dredfit.workout.SetFacts

/** What the rows under the rating cards are made of — the scope of the
 *  rating stated once, and every movement it does not govern named. */
class FeedbackSummary(
    private val session: Session,
    val overrides: Map<Pattern, Double>,
    private val setsSkipped: Map<Pattern, Int>,
    val skipped: Set<Pattern>,
    private val raised: Map<Pattern, Int>,
) {
    /** Adjusted movements follow their own number, not the rating, so they
     *  are outside its scope too. */
    val adjusted: Int get() = session.exercises.count { overrides[it.pattern] != null && it.pattern !in skipped }

    val applies: Int get() = session.exercises.size - skipped.size - adjusted

    val total: Int get() = session.exercises.size

    fun setsLost(ex: SessionExercise): Int = setsSkipped[ex.pattern] ?: 0

    /** Movements trained short of their sets. A movement that was LEFT is
     *  excluded rather than trusted to be absent. */
    val trainedShort: List<SessionExercise> get() = session.exercises.filter { setsLost(it) > 0 && it.pattern !in skipped }

    /** Movements with an addition standing, in session order. */
    val raisedRows: List<SessionExercise>
        get() = session.exercises.filter { (raised[it.pattern] ?: 0) > 0 && it.pattern !in skipped }

    fun raisedSteps(ex: SessionExercise): Int = raised[ex.pattern] ?: 0

    val withOwnNumber: List<SessionExercise> get() = session.exercises.filter { overrides[it.pattern] != null }

    val skippedRows: List<SessionExercise> get() = session.exercises.filter { it.pattern in skipped }

    /** Whether there is anything to say under the cards at all. */
    val shows: Boolean get() = overrides.isNotEmpty() || skipped.isNotEmpty() || trainedShort.isNotEmpty() ||
        raisedRows.isNotEmpty()
}

@Composable
fun FeedbackView(session: Session, facts: Map<Pattern, List<Int>>, overrides: Map<Pattern, Double>,
                 actualSets: Map<Pattern, List<Int>>, setsSkipped: Map<Pattern, Int>, skipped: Set<Pattern>,
                 raised: Map<Pattern, Int>, interrupted: Pattern?, onComplete: (FeedbackResult) -> Unit) {
    val c = Theme.colors
    val didFullPlan = SetFacts.didFullPlan(facts, skips = setsSkipped, skipped = skipped, exercises = session.exercises)
    val summary = FeedbackSummary(session, overrides, setsSkipped, skipped, raised)
    val gateReason = tr("“Easy, could do more” is for a workout done in full.")
    // Centred while it fits, scrollable once it does not: a fixed column
    // would clip the mandatory rating step at the largest text sizes. Three
    // groups spaced apart — the headline, the cards, the rows — at least 20
    // apart, as SwiftUI's two `Spacer(minLength: 20)`.
    BoxWithConstraints(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight),
               verticalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Kicker(tr("Workout %lld", session.sessionNumber))
                Text(tr("How did it go?"), style = dredfitFont(32f, Weight.heavy, tracking = -0.5f), color = c.ink)
                Text(tr("One tap — the next workout adapts"), style = dredfitFont(15f), color = c.ink2)
            }
            Column(Modifier.padding(vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                OptionCard(tr("Tough, did less"), tr("the next one eases off where it's hardest"),
                           FeedbackResult.less, enabled = true, gateReason, onComplete)
                OptionCard(tr("On plan"), tr("the next one adds a step where there's room"),
                           FeedbackResult.plan, enabled = true, gateReason, onComplete)
                OptionCard(tr("Easy, could do more"), tr("the next one adds as much as each movement allows"),
                           FeedbackResult.more, enabled = didFullPlan, gateReason, onComplete)
                if (!didFullPlan) {
                    // Centred under the cards: a caption for the group.
                    Text(gateReason, style = dredfitFont(13f), color = c.ink2, textAlign = TextAlign.Center,
                         modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp))
                }
            }
            Column {
                if (summary.shows) {
                    AdjustedSummary(summary, actualSets, interrupted)
                    Spacer(Modifier.height(24.dp))
                }
            }
        }
    }
}

/** The three cards share one look; `enabled` is passed at every call site —
 *  an omitted gate argument is a known defect class in this project. */
@Composable
private fun OptionCard(title: String, caption: String, result: FeedbackResult, enabled: Boolean, gateReason: String,
                       onComplete: (FeedbackResult) -> Unit) {
    val c = Theme.colors
    val shape = RoundedCornerShape(20.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.35f)
            .background(c.bg, shape)
            // The border is the ONLY thing marking the card as a control.
            .border(1.5.dp, c.targetStroke, shape)
            .clickable(enabled = enabled, role = Role.Button) { onComplete(result) }
            .then(if (!enabled) Modifier.semantics { stateDescription = gateReason } else Modifier)
            .testTag("rating-${result.name}")
            .padding(horizontal = 22.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(title, style = dredfitFont(18f, Weight.semibold), color = c.ink)
        // Two lines held open, so one wrapping caption does not make its card
        // taller than the other two.
        Text(caption, style = dredfitFont(13f), color = c.ink2, minLines = 2)
    }
}

@Composable
private fun AdjustedSummary(summary: FeedbackSummary, actualSets: Map<Pattern, List<Int>>, interrupted: Pattern?) {
    val c = Theme.colors
    Column(
        Modifier.fillMaxWidth().background(c.cardBG, RoundedCornerShape(16.dp)).padding(horizontal = 18.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(tr("Your rating applies to %lld of %lld", summary.applies, summary.total),
             style = dredfitFont(13f, Weight.semibold), color = c.ink2)
        for (ex in summary.withOwnNumber) {
            Row {
                Text(tr(ex.name), style = dredfitFont(14f, Weight.medium), color = c.ink, modifier = Modifier.weight(1f))
                SetFactsLabel(actualSets[ex.pattern] ?: emptyList(),
                              reported = roundedAwayFromZero(summary.overrides[ex.pattern] ?: 0.0).toInt())
            }
        }
        if (summary.trainedShort.isNotEmpty()) Kicker(tr("Sets skipped"), Modifier.padding(top = 8.dp))
        for (ex in summary.trainedShort) {
            val name = tr(ex.name)
            val spoken = tr("%@, %lld of %lld sets skipped", name, summary.setsLost(ex), ex.sets)
            Row(Modifier.semantics(mergeDescendants = true) { contentDescription = spoken }) {
                Text(name, style = dredfitFont(14f, Weight.medium), color = c.ink, modifier = Modifier.weight(1f))
                Text(tr("feedback.setsSkipped.count", summary.setsLost(ex), ex.sets),
                     style = dredfitFont(14f, Weight.semibold, monospacedDigit = true), color = c.accentText)
            }
        }
        if (summary.raisedRows.isNotEmpty()) Kicker(tr("Your additions"), Modifier.padding(top = 8.dp))
        for (ex in summary.raisedRows) {
            Row(Modifier.testTag("feedback-raised-${ex.pattern.rawValue}")) {
                Text(tr(ex.name), style = dredfitFont(14f, Weight.medium), color = c.ink, modifier = Modifier.weight(1f))
                Text(tr(RaiseLabel.text(summary.raisedSteps(ex), ex.unit)),
                     style = dredfitFont(14f, Weight.semibold, monospacedDigit = true), color = c.accentText)
            }
        }
        if (summary.skipped.isNotEmpty()) Kicker(tr("feedback.skipped"), Modifier.padding(top = 8.dp))
        for (ex in summary.skippedRows) {
            val name = tr(ex.name)
            val spoken = if (ex.pattern == interrupted) tr("%@, not finished", name) else tr("%@, skipped", name)
            Row(Modifier.semantics(mergeDescendants = true) { contentDescription = spoken }) {
                // ink2, not ink3: a set-aside movement reads quieter, but is
                // never the one name a person has to squint at.
                Text(name, style = dredfitFont(14f, Weight.medium), color = c.ink2, modifier = Modifier.weight(1f))
                if (ex.pattern == interrupted) {
                    Text(tr("not finished"), style = dredfitFont(14f, Weight.semibold), color = c.ink2)
                }
            }
        }
        if (summary.skipped.isNotEmpty()) {
            Text(tr("The rating doesn't apply to these movements — they stay as they were."),
                 style = dredfitFont(12.5f), color = c.ink2)
        }
    }
}

/** "actual 8 · 7 · 6" when the sets differ, "actual 8" when they do not —
 *  both carry the word: a bare list does not say it is the fact. Port of
 *  `SetFactsLabel` (ios/Dredfit/SetFacts.swift). */
@Composable
fun SetFactsLabel(values: List<Int>, reported: Int, size: Float = 14f) {
    val c = Theme.colors
    val varying = values.size > 1 && values.any { it != values[0] }
    val style = dredfitFont(size, Weight.semibold, monospacedDigit = true)
    if (varying) {
        val spoken = tr("actual %@", values.joinToString(", "))
        Text(tr("actual %@", values.joinToString(" · ")), style = style, color = c.accentText,
             modifier = Modifier.semantics { contentDescription = spoken })
    } else {
        Text(tr("actual %lld", reported), style = style, color = c.accentText)
    }
}
