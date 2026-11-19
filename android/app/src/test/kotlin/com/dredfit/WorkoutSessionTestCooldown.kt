//
//  Port of ios/DredfitTests/WorkoutSessionTests+Cooldown.swift: the cool-down
//  as the flow runs it — a side switched across its pause, and the block picking up
//  where the athlete is when the sheet changes it.
//
//  Every test is ported.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.store.AppStore
import com.dredfit.store.setBlockMoveHidden
import com.dredfit.workout.Cooldown
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.SplitStageWords
import com.dredfit.workout.WarmupHalves
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.beginCooldown
import com.dredfit.workout.completeSet
import com.dredfit.workout.declineWarmup
import com.dredfit.workout.rebaseCooldownOnComposition
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class WorkoutSessionTestCooldown : WorkoutSessionTestCase() {

    /** The warm-up declined and the last set of the last exercise done: the
     *  flow on the first position of its cool-down. */
    private fun inCooldown(store: AppStore): WorkoutSession {
        val flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.size - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        return flow
    }

    /** §41.19, as the flow runs it: the figure-four — switched "on the spot"
     *  with the clock running in 2.6.0, which took the re-set out of the second
     *  side — switches on the tone into a pause, and the second side starts
     *  whole on a go when the pause is over. */
    @Test
    fun theFigureFourSwitchesAcrossThePause() {
        val flow = inCooldown(makeStore())
        val spot = assertNotNull(flow.cooldownPositions.indexOfFirst { it.id == "lying-figure-four" }
                                     .takeIf { it >= 0 })
        run(flow, limit = 1_000) { flow.cooldown.index == spot && flow.cooldown.stage == GuidedStage.firstHalf }
        run(flow) { flow.cooldown.clock.remaining == WorkoutSession.countdownSignalSeconds + 1 }
        signals.events.clear()

        var paused = false
        run(flow) {
            if (flow.cooldown.stage == GuidedStage.switchPause) paused = true
            flow.cooldown.stage == GuidedStage.secondHalf
        }
        assertTrue(paused, "the second side waits for the re-set")
        assertEquals(spot, flow.cooldown.index, "the second side belongs to the same position")
        assertEquals(Cooldown.sideSeconds, flow.cooldown.clock.remaining,
                     "the pause takes nothing from the second side")
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.SwitchSides, Event.Go), signals.tones)
        assertTrue(signals.events.contains(Event.Announce(SplitStageWords(WarmupHalves.sides).switching.english)),
                   "the switch is spoken in the words of a side")
    }

    /** The rebase as the sheet sets it off, through the store and the flow:
     *  kneeling in the side reach with the standing lunge behind them, the
     *  athlete brings the kneeling lunge back. The block carries on where they
     *  kneel — the lunge already done stands for this workout. */
    @Test
    fun bringingTheKneelingLungeBackMidBlockKeepsTheAthleteDown() {
        val store = makeStore()
        store.setBlockMoveHidden("hip-flexors", true)
        val flow = inCooldown(store)
        assertEquals(listOf("chest-opener", "half-fold", "standing-hip-flexors",
                            "child-side-reach", "lying-figure-four", "lying-twist"),
                     flow.cooldownPositions.map { it.id }, "the composition this was measured on")
        run(flow, limit = 1_000) { flow.cooldown.index == 3 }

        store.setBlockMoveHidden("hip-flexors", false)
        flow.rebaseCooldownOnComposition()
        assertEquals(3, flow.cooldown.index)
        assertEquals("child-side-reach", flow.cooldownPositions[flow.cooldown.index].id)
        assertEquals(GuidedStage.getReady, flow.cooldown.stage, "the slot restarts on its own transition")
    }
}
