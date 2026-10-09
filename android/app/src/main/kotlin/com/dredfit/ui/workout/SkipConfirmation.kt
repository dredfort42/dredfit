//
//  The question a skip asks before it happens. Port of
//  ios/Dredfit/Views/Workout/SkipConfirmation.swift.
//
//  The two escapes are 44 dp targets 18 dp under the button that logs the
//  set. A workout has no undo: one stray thumb would take a set, or a whole
//  movement with every number already entered for it. The guard therefore
//  stands in FRONT of the state change rather than behind it.
//

package com.dredfit.ui.workout

import androidx.compose.runtime.Composable
import com.dredfit.ui.theme.AlertAction
import com.dredfit.ui.theme.DredfitAlert
import com.dredfit.ui.tr
import com.dredfit.workout.Words

/** One of the four skips, holding the action it runs if confirmed: the tap
 *  that raised the question is the tap that runs. */
class SkipConfirmation(val kind: Kind, val perform: () -> Unit) {

    @Suppress("EnumEntryName")
    enum class Kind { probeSet, workingSet, restOfSets, exercise }

    val title: Words
        get() = when (kind) {
            Kind.probeSet, Kind.workingSet -> Words.of("Skip this set?")
            Kind.restOfSets -> Words.of("Skip the remaining sets?")
            Kind.exercise -> Words.of("Skip this exercise?")
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
        }

    /** ONE short verb for all four: per-kind labels would make the layout of
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

/** One alert for all four, driven by the pending question. */
@Composable
fun SkipConfirmationAlert(pending: SkipConfirmation, onClose: () -> Unit) {
    DredfitAlert(
        title = tr(pending.title),
        message = tr(pending.message),
        actions = listOf(
            AlertAction(tr("Keep going"), tag = "skip-keep-going", cancel = true) {},
            AlertAction(tr(pending.confirmTitle), tag = "skip-confirm") { pending.perform() },
        ),
        onClose = onClose,
    )
}
