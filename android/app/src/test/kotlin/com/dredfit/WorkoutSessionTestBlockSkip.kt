//
//  Port of ios/DredfitTests/WorkoutSessionTests+BlockSkip.swift: what the flow
//  does around the question a block's escape asks (`askToSkip`) — the block
//  stands still while it is up, and "Skip" ends it without billing the wait
//  as stretching.
//
//  Every Swift test is ported; they go through `askToSkip` itself rather than
//  the calls it makes, so the wiring of both answers is under test too.
//

package com.dredfit

import com.dredfit.ui.Observed
import com.dredfit.ui.workout.askToSkip
import com.dredfit.workout.GuidedBlock
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.WorkoutSession.Phase
import com.dredfit.workout.beginCooldown
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.finish
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WorkoutSessionTestBlockSkip : WorkoutSessionTestCase() {

    /** A cool-down on its first position, past the count-in. */
    private fun cooldownRunning(): WorkoutSession {
        val flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow) { flow.cooldown.stage != GuidedStage.getReady }
        return flow
    }

    /** A stray tap answered minutes later finds the stretch where it was, and
     *  "Keep going" picks it up from the same second. */
    @Test
    fun theBlockStandsStillWhileItsSkipIsAsked() {
        val flow = cooldownRunning()
        run(flow, 3)
        val index = flow.cooldown.index
        val stage = flow.cooldown.stage
        val remaining = flow.cooldown.clock.remaining

        val question = assertNotNull(Observed(flow).askToSkip(GuidedBlock.cooldown))   // the question goes up
        // A minute of ticks with the app in front, as the view's timer runs
        // them: one jump would read as an absence and pause the block on its
        // own, hiding a question that froze nothing.
        run(flow, 60)
        assertEquals(index, flow.cooldown.index, "the block moved on behind the question")
        assertEquals(stage, flow.cooldown.stage)
        assertEquals(remaining, flow.cooldown.clock.remaining)

        question.cancel()                                               // "Keep going"
        assertEquals(Phase.Cooldown, flow.phase)
        assertEquals(remaining, flow.cooldown.clock.remaining,
                     "saying no must hand back the second the question froze")
        run(flow, 1)
        assertEquals(remaining - 1, flow.cooldown.clock.remaining, "the clock did not run again after \"Keep going\"")
    }

    /** "Skip" ends the block, and the minutes the question stood up are not
     *  stretching: the energy Health is told about reads this figure. */
    @Test
    fun theSecondsTheQuestionStoodAreNotBilledAsStretching() {
        val flow = cooldownRunning()
        run(flow, 10)
        val question = assertNotNull(Observed(flow).askToSkip(GuidedBlock.cooldown))   // the question goes up
        advance(300)
        question.perform()                                              // "Skip"
        assertEquals(Phase.Feedback, flow.phase)
        val billed = assertNotNull(flow.cooldownSec)
        assertTrue(billed < 60, "the $billed s billed include the question's 300")
    }

    /** A tap on the escape of a block that ended in the same instant asks
     *  nothing: no question over the rating, and nothing frozen behind it. */
    @Test
    fun aBlockThatHasEndedAsksNothing() {
        val flow = cooldownRunning()
        flow.finish(GuidedBlock.cooldown)
        assertNull(Observed(flow).askToSkip(GuidedBlock.cooldown))
        assertNull(flow.blockFrozenAt, "a question that was never asked froze the block")
        assertNull(Observed(flow).askToSkip(GuidedBlock.warmup), "the warm-up is long over")
    }
}
