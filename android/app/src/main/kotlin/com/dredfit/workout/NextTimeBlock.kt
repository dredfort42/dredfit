//
//  The rules of the summary's "Next time" block that the flow itself reads.
//  They live on the view in ios/Dredfit/Views/Workout/ExerciseSummary.swift
//  (`NextTimeBlock`); the flow trims a raise by them after a correction
//  (`WorkoutSession.trimRaiseToWhatStillMoves`), so they are here, and the
//  block's screen of phase 2c reads them from here.
//

package com.dredfit.workout

import com.dredfit.core.SessionExercise

object NextTimeBlock {

    /** Whether two previews promise one plan — compared on what is printed. */
    fun samePlan(a: SessionExercise, b: SessionExercise): Boolean =
        a.display == b.display && a.variation == b.variation && a.probe == b.probe

    /** How many of `steps` still change the plan, walked down from the count
     *  while the step below promises the same plan; a preview that cannot be
     *  had leaves the count alone. */
    fun stepsThatStillMove(steps: Int, preview: (Int) -> SessionExercise?): Int {
        var k = maxOf(0, steps)
        while (k > 0) {
            val now = preview(k) ?: break
            val below = preview(k - 1) ?: break
            if (!samePlan(now, below)) break
            k -= 1
        }
        return k
    }

    /** The plan as the block's sentence names it, probe included: on a
     *  probing plan the probe has taken a working set, and "2×45 s" alone
     *  would read as a set taken off. A name only when the variation changes
     *  — a passed probe lands the plan on another exercise, and "3×15 s" with
     *  no name would read as a collapse rather than a promotion. */
    fun planWords(planned: SessionExercise, after: SessionExercise): Words {
        val plan = if (planned.variation == after.variation) Words.display(planned)
                   else Words.join("%@ · %@", Words.name(planned.name), Words.display(planned))
        val probe = planned.probe ?: return plan
        return Words.of("%@ + probe: %@ · %@", plan, Words.name(probe.name), Words.display(probe))
    }
}
