//
//  Twelve things worth knowing about the regulator. Port of
//  ios/Dredfit/Views/Settings/HowItWorksView.swift — every number here is a
//  fact from the engine (the Swift file says which constant each one is), so
//  if the engine changes, this screen changes with it.
//

package com.dredfit.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dredfit.ui.theme.DredfitSheet
import com.dredfit.ui.theme.PrimaryButton
import com.dredfit.ui.theme.Theme
import com.dredfit.ui.theme.Weight
import com.dredfit.ui.theme.dredfitFont
import com.dredfit.ui.tr
import com.dredfit.workout.Words

object HowItWorksView {
    /** Title and body keys, in the order the screen numbers them. */
    val sections: List<Pair<Words, Words>> = listOf(
        Words.of("Variation and dose") to Words.of("Two facts per movement, not one number: WHICH variation you do, and HOW MUCH of it. Every movement has a ladder of four to seven variations, and neighbouring rungs stand close enough together that the next one is never a leap. The dose is reps per set — or seconds for a hold — and it grows only to what you have already shown."),
        Words.of("What your answer does") to Words.of("“On plan” adds a step, “more” adds two, “less” steps back the movement that made it hard. An exact number for a single exercise outweighs the overall rating — and when your sets show more than the plan, the next plan starts from what you showed. Nothing is estimated: whatever you are given, you have already done. The plan climbs at most two steps per workout — and only one wherever the tissue doing the work needs the slower pace: tendons remodel on a longer clock than muscle. A step lands on one set, not on all of them."),
        Words.of("Deload") to Words.of("Three shortfalls in a row and the dose rolls back three steps. Not a punishment — a breather, so you come back with something in reserve."),
        Words.of("Rotation") to Words.of("Pull is in every workout — that is what keeps your shoulders balanced. The rest come round in a cycle: over eight workouts each one turns up five times. With the pull-up bar switched on, the pull alternates between horizontal and vertical."),
        Words.of("Weekly rhythm") to Words.of("3–4 workouts a week is the sweet spot: strength grows while joints and tendons keep up. Muscle adapts in weeks, tendons in months — rest days protect the slower half."),
        Words.of("Breaks") to Words.of("After two weeks away the plan meets you a couple of steps lower — further down the longer the break. It never drops below something you have actually done. Nothing is lost: it climbs back quickly, and coming back is the only thing that matters."),
        Words.of("Skips") to Words.of("A skipped exercise simply doesn't count: it stays exactly where it was. No penalty, no rollback. A skipped SET is a different answer: the movement still counts as done, and the next plan comes back with one set fewer — until you earn it back."),
        Words.of("Too much today") to Words.of("Muscles giving out and a joint hurting are different things, and the app does not ask which. When a movement is too much today, you answer with the plan and not with a diagnosis: take the same movement in an easier variation, or skip a set while you are doing it. Nothing has to be decided in advance — the plan says how long the full workout takes and how short it can get, and the rest you settle set by set. Sharp pain is always a reason to stop."),
        Words.of("One set at a time") to Words.of("Getting harder does not mean every set at once. A step adds a rep to ONE set: 3×8 becomes 9-8-8, then 9-9-8, then 3×9. The plan settles where you actually are, and overshooting costs one rep in one set instead of a whole variation."),
        Words.of("Trying the next variation") to Words.of("A harder variation is never handed to you on a guess. When you top out the reps, the LAST set of that exercise becomes a probe: one set of the next variation, four reps or fifteen seconds. Manage it and the next workout starts you there, at three sets of four. Fall short and nothing moves — the working sets stand as they were, and the probe is offered again while the movement stays at the top of its range and the last answer was not “tough”. The volume of the workout does not change either way."),
        Words.of("Why there are no questionnaires") to Words.of("A questionnaire can be wrong; what you actually did cannot. Dredfit learns what you can do from real workouts and keeps the load right at the edge of it."),
        Words.of("Cardio and strength") to Words.of("If you also run, swim or cycle, try to put that and your strength work in different halves of the day. A couple of hours apart and they barely get in each other's way. Back to back, the interference shows. If splitting them is not an option, no harm done: at home volumes the difference is small."),
    )
}

@Composable
fun HowItWorksView(onDismiss: () -> Unit) {
    val c = Theme.colors
    DredfitSheet(onDismiss) {
        Column(Modifier.fillMaxHeight()) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 12.dp)) {
                Text(tr("How it works"), style = dredfitFont(28f, Weight.heavy, tracking = -0.5f), color = c.ink,
                     modifier = Modifier.padding(top = 18.dp))
                Text(tr("Twelve things worth knowing about the regulator."), style = dredfitFont(15f), color = c.ink2,
                     modifier = Modifier.padding(top = 8.dp))
                for ((i, section) in HowItWorksView.sections.withIndex()) {
                    Row(Modifier.padding(top = 26.dp), horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.Top) {
                        // Decorative ordering — hidden from TalkBack.
                        Box(Modifier.size(26.dp).background(c.ink, CircleShape).clearAndSetSemantics {},
                            contentAlignment = Alignment.Center) {
                            Text("${i + 1}", style = dredfitFont(13f, Weight.semibold), color = c.bg)
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            // A heading, so the titles stay skimmable.
                            Text(tr(section.first), style = dredfitFont(17f, Weight.semibold), color = c.ink,
                                 modifier = Modifier.semantics { heading() })
                            Text(tr(section.second), style = dredfitFont(15.5f).copy(lineHeight = 22.sp), color = c.ink2)
                        }
                    }
                }
            }
            // Its own tag: Settings sits underneath with a Done of its own.
            PrimaryButton(tr("Got it"), tag = "how-it-works-done",
                          modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 16.dp), onClick = onDismiss)
        }
    }
}
