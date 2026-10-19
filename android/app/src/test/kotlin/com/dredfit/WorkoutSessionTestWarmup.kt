//
//  Port of ios/DredfitTests/WorkoutSessionTests+Warmup.swift: the standing
//  warm-up as the flow runs it — a circle that reverses on a tone with the
//  clock running, and a last move that follows the session.
//
//  Every test is ported.
//

package com.dredfit

import com.dredfit.SignalSpy.Event
import com.dredfit.core.Engine
import com.dredfit.core.EngineState
import com.dredfit.core.Pattern
import com.dredfit.core.generateSession
import com.dredfit.workout.GuidedStage
import com.dredfit.workout.SplitStageWords
import com.dredfit.workout.Warmup
import com.dredfit.workout.WarmupHalves
import com.dredfit.workout.WorkoutSession
import com.dredfit.workout.beginWarmup
import com.dredfit.workout.warmupMove
import com.dredfit.workout.warmupMoves
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class WorkoutSessionTestWarmup : WorkoutSessionTestCase() {

    /** The halfway boundary of a circle is the switch itself: no pause opens,
     *  the first half's 3-2-1 lands on the SWITCH tone rather than on a go, and
     *  the second half starts with its whole fifteen seconds. A go there would
     *  read as a second start in the middle of a movement that never stopped;
     *  a pause would stop it for nothing. */
    @Test
    fun aCircleReversesOnTheSwitchToneWithTheClockRunning() {
        val flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow) { flow.warmup.stage == GuidedStage.firstHalf }
        val index = flow.warmup.index
        assertTrue(flow.warmupMove.reverses, "the premise: the first split move is a circle")
        run(flow) { flow.warmup.clock.remaining == WorkoutSession.countdownSignalSeconds + 1 }
        signals.events.clear()

        var paused = false
        run(flow) {
            if (flow.warmup.stage == GuidedStage.switchPause) paused = true
            flow.warmup.stage == GuidedStage.secondHalf
        }
        assertFalse(paused, "a circle reverses on the move: no switch pause")
        assertEquals(index, flow.warmup.index, "the second half belongs to the same move")
        assertEquals(Warmup.halfSeconds, flow.warmup.clock.remaining)
        assertEquals(listOf(Event.Tick, Event.Tick, Event.Tick, Event.SwitchSides), signals.tones)
        assertTrue(signals.events.contains(Event.Announce(SplitStageWords(WarmupHalves.directions).switching.english)),
                   "the switch is spoken in the words of a direction, not of a side")
    }

    /** The block's one specific part: its last move prepares the first
     *  exercise of THIS session. Asked through the flow, because the wiring —
     *  which session, which exercise — is what this pins; the mapping itself
     *  is `BlockReserveTest`'s.
     *
     *  A session that opens on a HINGE, not the fresh install's squat: squat
     *  and lunge share a lead-in, and a session opening on a squat could not
     *  tell the first exercise from the last, or from a squat hard-coded. */
    @Test
    fun theWarmupEndsOnTheLeadInOfTheFirstExercise() {
        // The rotation's start is `counter × 3 mod 8`; 6 puts it on the hinge,
        // which `Pattern.ordered` then lists before the pull.
        val state = EngineState.initial.apply { counter = 6 }
        val flow = makeFlow(makeStore(), session = Engine.generateSession(state))
        assertEquals(Pattern.hinge, flow.session.exercises.firstOrNull()?.pattern, "the premise")
        assertNotEquals(Pattern.hinge, flow.session.exercises.lastOrNull()?.pattern, "the premise")
        assertEquals("hip-hinges", flow.warmupMoves.last().id)
    }
}
