//
//  The notes under a plan row — the statics of `ExerciseRow` in
//  ios/Dredfit/Views/Today/ExerciseRow.swift, where they live on the SwiftUI
//  view. Here they are plain Kotlin returning `Words` (no Compose import), so a
//  JVM unit test reaches the rules; the row composable, when it is written,
//  resolves them with `tr`. Which facts hold is the store's
//  (`aSetJustCameBack`, `setsJustHeldBackByThePulls`); these own the words.
//

package com.dredfit.ui.today

import com.dredfit.core.LoadUnit
import com.dredfit.core.SessionExercise
import com.dredfit.workout.RaiseLabel
import com.dredfit.workout.Words

object ExerciseRow {

    fun note(setCameBack: Boolean): Words? = if (setCameBack) Words.of("A set is back.") else null

    /** A probing row's `sets` is already one lower — the probe replaces the
     *  last of them — so the row names the set standing after it, and the
     *  movement it is. */
    fun probeNote(exercise: SessionExercise): Words? {
        val probe = exercise.probe ?: return null
        return Words.keyed("plan.probeNote", "Then a probe: one set of %@ · %@",
                           Words.name(probe.name), Words.display(probe))
    }

    /** About the NAME: the athlete's own handle stands alone; the other
     *  movers are not named, since a guess at one would be wrong about the rest. */
    fun variationNote(easedByHand: Boolean, dropped: Boolean): Words? = when {
        easedByHand -> Words.keyed("plan.easedByHand", "You made this one easier.")
        dropped -> Words.keyed("plan.variationDropped", "An easier variation than last time.")
        else -> null
    }

    /** The part of this plan the person asked for on the last summary. */
    fun raisedNote(steps: Int, unit: LoadUnit): Words? =
        if (steps > 0) Words.keyed("plan.raised", "%@ — your addition", RaiseLabel.text(steps, unit)) else null

    /** A push the pull slot's cap took sets from: names the pulls, never a
     *  row on screen, and "fewer" — the cap can take more than one set. */
    fun pullsNote(heldBack: Boolean): Words? =
        if (heldBack) Words.keyed("plan.heldBackByPulls", "Fewer sets for now — pushes keep pace with your pulls.")
        else null

    /** All of them, in reading order: the name, the number, what stands after
     *  both. The defaults mean "no claim", as on iOS. */
    fun notes(exercise: SessionExercise, setCameBack: Boolean, easedByHand: Boolean = false,
              variationDropped: Boolean = false, raisedSteps: Int = 0,
              heldBackByPulls: Boolean = false): List<Words> =
        listOfNotNull(variationNote(easedByHand, variationDropped),
                      raisedNote(raisedSteps, exercise.unit),
                      note(setCameBack),
                      pullsNote(heldBackByPulls),
                      probeNote(exercise))
}
