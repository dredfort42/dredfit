//
//  The card for a workout that was interrupted: carry on, keep it, or start
//  over. Port of ios/Dredfit/Views/Today/ResumeCard.swift — on Android it is
//  also what a process death comes back to: the snapshot written at every
//  transition is the workout, and this card is the way back into it.
//

package com.dredfit.ui.today

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.dredfit.journal.WorkoutSnapshot
import com.dredfit.store.AppStore
import com.dredfit.store.clearWorkoutSnapshot
import com.dredfit.store.nextSession
import com.dredfit.store.resumableWorkout
import com.dredfit.store.unfinishedWorkoutAwaitingAnswer
import com.dredfit.ui.Observed
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.theme.PairedPrimary
import com.dredfit.ui.theme.PairedSecondary
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import java.time.Duration
import java.time.Instant

/** The snapshot Today has to say something about, and WHICH thing: inside
 *  the occasion it offers to carry on; past it — but before the workout
 *  counts as forgotten — it ASKS instead of deciding. */
data class PendingWorkoutCard(val snapshot: WorkoutSnapshot, val awaitingAnswer: Boolean)

val AppStore.pendingWorkoutCard: PendingWorkoutCard?
    get() {
        resumableWorkout()?.let { return PendingWorkoutCard(it, awaitingAnswer = false) }
        unfinishedWorkoutAwaitingAnswer()?.let { return PendingWorkoutCard(it, awaitingAnswer = true) }
        return null
    }

@Composable
fun ResumeCard(observedStore: Observed<AppStore>, card: PendingWorkoutCard, start: (WorkoutRequest) -> Unit,
               startOverConfirmShown: Boolean, setStartOverConfirmShown: (Boolean) -> Unit) {
    val store by observedStore
    val c = Theme.colors
    val snap = card.snapshot
    val total = store.nextSession.exercises.size
    val position = minOf(snap.exIndex + 1, total)
    // A workout that only wants its rating has nothing to restart: "Start
    // over" beside "Continue" would read as "replay" while it means "throw
    // the session away".
    val onlyRatingLeft = snap.atFeedback == true
    Column(Modifier.fillMaxWidth().background(c.cardBG, RoundedCornerShape(18.dp)).padding(18.dp)) {
        Text(if (card.awaitingAnswer) tr("Keep this workout?") else tr("Continue the workout?"),
             style = dredfitFont(20f, Weight.heavy, tracking = -0.3f), color = c.ink)
        Text(if (onlyRatingLeft) tr("The workout is done — only the rating is left.")
             else tr("You stopped at exercise %lld of %lld — everything done so far is still in place.", position, total),
             style = dredfitFont(14.5f), color = c.ink2, modifier = Modifier.padding(top = 8.dp))
        // How long ago, past ten minutes only: below that the relative
        // formatter would answer "now", which says nothing.
        val now = store.clock.instant()
        if (Duration.between(snap.savedAt, now) > Duration.ofMinutes(10)) {
            val ago = DateUtils.getRelativeTimeSpanString(snap.savedAt.toEpochMilli(), now.toEpochMilli(),
                                                          DateUtils.MINUTE_IN_MILLIS).toString()
            Text(tr("The last set was %@.", ago), style = dredfitFont(13f), color = c.ink2,
                 modifier = Modifier.padding(top = 6.dp))
        }
        if (card.awaitingAnswer && !onlyRatingLeft) {
            Text(tr("“Finish now” keeps what you've done and goes to the rating — the remaining exercises are marked as skipped."),
                 style = dredfitFont(13f), color = c.ink2, modifier = Modifier.padding(top = 6.dp))
        }
        Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PairedPrimary(if (onlyRatingLeft) tr("Rate the workout") else tr("resume.continue"), tag = "resume-continue",
                          modifier = Modifier.weight(1f)) {
                start(WorkoutRequest(store.nextSession, resume = snap))
            }
            if (card.awaitingAnswer && !onlyRatingLeft) {
                // The alternative to carrying on is KEEPING it: it opens the
                // rating, and the athlete says how it went.
                PairedSecondary(tr("Finish now"), tag = "resume-keep", modifier = Modifier.weight(1f)) {
                    start(WorkoutRequest(store.nextSession, resume = snap, settleImmediately = true))
                }
            } else if (!onlyRatingLeft) {
                PairedSecondary(tr("Start over"), tag = "resume-restart", modifier = Modifier.weight(1f)) {
                    setStartOverConfirmShown(true)
                }
            }
        }
    }
    if (startOverConfirmShown) {
        // The most expensive tap on the screen asks first: it throws away the
        // only copy of a half-finished workout.
        DredfitAlert(
            title = tr("Start over?"),
            message = tr("Everything done in this workout is dropped — the logged sets and the numbers. It starts from the warm-up."),
            actions = listOf(
                AlertAction(tr("Keep my progress"), tag = null, cancel = true) {},
                AlertAction(tr("Start over"), tag = "resume-restart-confirm", destructive = true) {
                    observedStore.act { clearWorkoutSnapshot() }
                    start(WorkoutRequest(store.nextSession))
                },
            ),
            onClose = { setStartOverConfirmShown(false) },
        )
    }
}
