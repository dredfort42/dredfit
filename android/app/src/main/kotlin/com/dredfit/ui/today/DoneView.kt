//
//  The completed state of Today. Port of ios/Dredfit/Views/Today/DoneView.swift:
//  the one sentence about what the rating moved, and the way to give a
//  different one — they are one thought.
//
//  Not here yet: "What you did today", the door to the history sheet — that
//  sheet arrives with Progress (phase 2c-2), and a door to nothing would be a
//  control that lies.
//

package com.dredfit.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dredfit.core.FeedbackResult
import com.dredfit.journal.WorkoutRecord
import com.dredfit.store.AppStore
import com.dredfit.store.canChangeLastRating
import com.dredfit.store.easedByRating
import com.dredfit.store.lastRecord
import com.dredfit.ui.Observed
import com.dredfit.ui.listFormatted
import com.dredfit.ui.screenDateText
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.CheckGlyph
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.Kicker
import com.dredfit.ui.theme.MinTarget
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.SetFacts

/** `SetFacts.didFullPlan` over the journal entry — the same rule, so the
 *  "easy" gate of a changed rating cannot drift from the rating screen's. A
 *  record that does not carry its exercises answers NO, not a vacuous yes. */
val WorkoutRecord.didFullPlan: Boolean
    get() {
        val exercises = exercises
        if (exercises.isNullOrEmpty()) return false
        return SetFacts.didFullPlan(setActuals ?: emptyMap(), skips = setsSkipped ?: emptyMap(),
                                    skipped = skipped ?: emptySet(), exercises = exercises)
    }

@Composable
fun DoneView(observedStore: Observed<AppStore>, today: TodayState) {
    val store by observedStore
    val c = Theme.colors
    val record = store.lastRecord
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().padding(top = 18.dp)) { Kicker(screenDateText(store.today, store.zone)) }
        Spacer(Modifier.weight(1f))
        Box(Modifier.size(120.dp).background(c.cardBG, CircleShape), contentAlignment = Alignment.Center) {
            CheckGlyph(c.ink, 44.dp)
        }
        Text(tr("Workout %lld completed", record?.sessionNumber ?: 0),
             style = dredfitFont(24f, Weight.heavy, tracking = -0.4f), color = c.ink, modifier = Modifier.padding(top = 24.dp))
        if (record != null) {
            Text(resultCaption(store, record), style = dredfitFont(15f), color = c.ink2, textAlign = TextAlign.Center,
                 modifier = Modifier.padding(top = 6.dp))
        }
        // Quiet, and last: correcting a rating is the rarest thing anyone does
        // here — and the way back from a rating nobody gave (an unrated
        // workout is settled "on plan").
        if (store.canChangeLastRating && record != null) {
            Box(Modifier.heightIn(min = MinTarget).clickable(role = Role.Button) { today.ratingChangeShown = true }
                    .testTag("change-rating"),
                contentAlignment = Alignment.Center) {
                Text(tr("today.changeRating"), style = dredfitFont(14f), color = c.accentText)
            }
        }
        Spacer(Modifier.weight(1f))
        Box(Modifier.padding(bottom = 24.dp)) {
            NextWorkoutCard(observedStore) { today.destination = TodayDestination.NextWorkout }
        }
    }
    if (today.ratingChangeShown && record != null) {
        RatingChangeAlert(observedStore, record) { today.ratingChangeShown = false }
    }
}

/** After a "tough" it NAMES the movements the descent landed on — the card
 *  promised "where it's hardest", and an unnamed promise cannot be checked. */
@Composable
private fun resultCaption(store: AppStore, record: WorkoutRecord): String = when (record.result) {
    FeedbackResult.less -> {
        val eased = store.easedByRating(record)
        if (eased.isEmpty()) tr("Rating: tough — the next one will be easier")
        else tr("today.ratingLessNamed", listFormatted(eased.map { tr(it.displayName) }))
    }
    FeedbackResult.plan -> tr("Rating: on plan — the next one adds a step to the movements that have room for one")
    FeedbackResult.more -> tr("Rating: easy — progressing as fast as each movement allows")
}

/** The other two answers, in the rating screen's own words. The milestones a
 *  new answer earns are dropped on purpose: that screen is a moment INSIDE a
 *  workout, not a correction made later. */
@Composable
private fun RatingChangeAlert(observedStore: Observed<AppStore>, record: WorkoutRecord, onClose: () -> Unit) {
    val actions = buildList {
        if (record.result != FeedbackResult.less) {
            add(AlertAction(tr("Tough, did less"), tag = "change-rating-less") {
                observedStore.act { changeLastRating(FeedbackResult.less) }
            })
        }
        if (record.result != FeedbackResult.plan) {
            add(AlertAction(tr("On plan"), tag = "change-rating-plan") {
                observedStore.act { changeLastRating(FeedbackResult.plan) }
            })
        }
        // The same gate the rating screen puts on "easy".
        if (record.result != FeedbackResult.more && record.didFullPlan) {
            add(AlertAction(tr("Easy, could do more"), tag = "change-rating-more") {
                observedStore.act { changeLastRating(FeedbackResult.more) }
            })
        }
        add(AlertAction(tr("today.changeRating.keep"), tag = null, cancel = true) {})
    }
    DredfitAlert(tr("today.changeRating.title"), tr("today.changeRating.body"), actions, onClose)
}
