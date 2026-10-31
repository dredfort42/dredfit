//
//  The question a skip asks before it happens. Port of
//  ios/Dredfit/Views/Workout/SkipConfirmation.swift.
//
//  The two escapes are 44 dp targets 18 dp under the button that logs the
//  set. A workout has no undo: one stray thumb would take a set, or a whole
//  movement with every number already entered for it. The guard therefore
//  stands in FRONT of the state change rather than behind it.
//
//  The same holds for the escape that ends a guided block. It is a 56 dp
//  full-width button under "I'm ready", it fires on contact, and a block
//  left by accident cannot be picked up again: one bump of the phone — a
//  child's hand on the screen — took a cool-down straight to the rating.
//

package com.dredfit.ui.workout

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.tr
import com.dredfit.workout.Words

/** One of the six skips, holding the action it runs if confirmed: the tap
 *  that raised the question is the tap that runs. [perform] comes last so the
 *  set-level calls stay a trailing lambda. [cancel] is what saying no
 *  hands back: a block's question freezes the block while it stands — a
 *  position must not run on, or end, behind an alert nobody has answered yet
 *  — so "Keep going" has to give the clock back. */
class SkipConfirmation(val kind: Kind, val cancel: () -> Unit = {}, val perform: () -> Unit) {

    @Suppress("EnumEntryName")
    enum class Kind {
        probeSet, workingSet, restOfSets, exercise,
        /** The escape that ends a whole guided block. */
        warmup, cooldown,
    }

    val title: Words
        get() = when (kind) {
            Kind.probeSet, Kind.workingSet -> Words.of("Skip this set?")
            Kind.restOfSets -> Words.of("Skip the remaining sets?")
            Kind.exercise -> Words.of("Skip this exercise?")
            Kind.warmup -> Words.of("Skip the warm-up?")
            Kind.cooldown -> Words.of("Skip the cool-down?")
        }

    /** What is actually lost. The set-level sentences are THE SAME KEYS the
     *  controls' accessibility hints use — one wording per rule. */
    val message: Words
        get() = when (kind) {
            Kind.probeSet -> probeHint
            Kind.workingSet -> workingSetHint
            Kind.restOfSets -> Words.of(
                "The movement still counts as trained — the plan keeps those sets off next time.")
            // ONE noun, the title's: "it", rather than a second noun to sew
            // to the first under a running clock.
            // One literal, because the literal is the catalog key.
            Kind.exercise -> Words.of(
                "It counts as not trained, and any number you entered for it is not kept. Its plan stays exactly as it is.")
            // What a block's escape loses is the block itself, and the
            // cool-down's sentence says the one thing nobody can see from the
            // button: there is no way back into it from the rating.
            Kind.warmup -> Words.of(
                "The workout goes straight to the first exercise. The plan does not change.")
            Kind.cooldown -> Words.of(
                "The workout goes straight to the rating, and the cool-down cannot be started again. The plan does not change.")
        }

    /** ONE short verb for all six: per-kind labels would make the layout of
     *  two controls that sit at equal weight differ by language. No
     *  destructive role on any of them — a skipped movement stays where it
     *  was, and a red button would argue with the sentence above it. */
    val confirmTitle: Words get() = Words.of("Skip")

    companion object {
        val workingSetHint: Words = Words.of(
            "The plan keeps this set off next time. Nothing else about the movement changes.")
        val probeHint: Words = Words.of("The probe just comes back next time. The working sets lose nothing.")
    }
}

/** One alert for all six, driven by the pending question.
 *
 *  Answered once, by a button or by back. An alert taken down UNANSWERED —
 *  the activity recreated under it (a theme, font or fold change) while the
 *  flow lives on in the process, and `pendingSkip` with the activity — says
 *  no: a block's question has frozen the block, and with the question gone
 *  nothing else would ever give the clock back. */
@Composable
fun SkipConfirmationAlert(pending: SkipConfirmation, onClose: () -> Unit) {
    val answered = remember(pending) { booleanArrayOf(false) }
    DisposableEffect(pending) {
        onDispose { if (!answered[0]) pending.cancel() }
    }
    DredfitAlert(
        title = tr(pending.title),
        message = tr(pending.message),
        actions = listOf(
            AlertAction(tr("Keep going"), tag = "skip-keep-going", cancel = true) {
                answered[0] = true
                pending.cancel()
            },
            AlertAction(tr(pending.confirmTitle), tag = "skip-confirm") {
                answered[0] = true
                pending.perform()
            },
        ),
        onClose = onClose,
    )
}
