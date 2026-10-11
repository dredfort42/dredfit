//
//  The flow's one-second beat and who keeps it. No Swift twin: on iOS the
//  beat is the flow screen's `Timer.publish(every: 1)`, and a backgrounded
//  iOS app runs no timer. Android keeps the beat going behind the ongoing
//  notification — its foreground service keeps the process in front — so a
//  countdown's 3-2-1 still sounds with the screen off or another app on top.
//
//  THE ACCOUNTING IS iOS'S (owner decision, 09.10.2026). Leaving the screen
//  is leaving, notification or not: `sceneLeft` is stamped on every stop and
//  the time away is charged exactly as on iOS. And a countdown that runs out
//  while the person is away STANDS at its end — no go, no next stage — until
//  they come back: the first tick on return reads the real overshoot, which
//  is the very tick a resumed iOS app runs. So everything iOS decides from an
//  absence (a hands-free run dropped past `BlockPause.absenceSeconds`, a
//  guided block frozen, the count-in a late rest earns, the time away) is
//  decided the same here; the beat only adds the seconds before the end.
//
//  THE CPU. A main-looper timer counts uptime, which stops while the CPU
//  sleeps; with the screen off the device suspends within seconds and a
//  3-2-1 would land whenever something else woke it. So the wake lock is held
//  exactly while a countdown runs toward an end the beat may still reach,
//  and released while the flow waits for a tap or stands at an end away from
//  the screen — both wait for someone to come back.
//
//  Plain Kotlin on an injected timer: the decisions run in a JVM test
//  (WorkoutBeatTest); the main-looper timer is ui/workout/WorkoutFlowView.kt's.
//

package com.dredfit.workout

import com.dredfit.workout.WorkoutSession.Phase
import java.time.Duration

/** Calls `beat` once a second until stopped. */
interface BeatTimer {
    fun start(beat: () -> Unit)
    fun stop()
}

class WorkoutBeat(
    private val flow: WorkoutSession,
    private val ongoing: OngoingWorkout,
    private val timer: BeatTimer,
    /** `Observed.act`: the change, then the redraw. */
    private val act: (WorkoutSession.() -> Unit) -> Unit,
) {
    /** "Leave the workout?" is up: nothing the clocks drive happens behind
     *  it — the clocks run on and are only primed. */
    var exitAlertShown: Boolean = false

    private var visible = false
    private var closed = false

    /** The beat is running. */
    var isRunning: Boolean = false
        private set

    /** The activity started (`true`) or stopped — iOS's scene phase, with
     *  iOS's consequences either way. */
    fun screen(visible: Boolean) {
        if (closed) return
        if (visible != this.visible) {
            this.visible = visible
            act { if (visible) sceneCameBack() else sceneLeft() }
        }
        settle()
    }

    /** One second of the flow. */
    fun beat() {
        act {
            when {
                exitAlertShown -> primeComingBack()
                !standingAtAnEnd -> tick()
            }
        }
        retireIfLeftBehind()
        ongoing.refresh()
        settle()
    }

    /** The flow is gone (rated, finished later, discarded): nothing beats
     *  for it again. */
    fun close() {
        closed = true
        if (isRunning) timer.stop()
        isRunning = false
        ongoing.keepAwake(false)
    }

    /** Away, with the countdown run out: the tick that would end it is the
     *  one iOS runs on return, and only then. */
    private val standingAtAnEnd: Boolean
        get() = flow.absence.isAway && flow.runningClock?.read(flow.now()) is Countdown.Reading.Ended

    private fun settle() {
        if (closed) return
        // Off screen the beat runs only for the notification's sake.
        val wanted = visible || ongoing.isShown
        if (wanted && !isRunning) {
            isRunning = true
            timer.start(::beat)
        } else if (!wanted && isRunning) {
            isRunning = false
            timer.stop()
        }
        ongoing.keepAwake(isRunning && !exitAlertShown && flow.runningClock != null && !standingAtAnEnd)
    }

    /**
     * Past the resume window (`WorkoutSessionStore.resumeWindow`, three
     * hours without a write) Today no longer offers to continue the workout
     * as the same occasion; the notification ends there too — a service kept
     * longer is a battery nobody is training on. The flow itself stays: it
     * owns its snapshot, and coming back to it is still coming back.
     */
    private fun retireIfLeftBehind() {
        val shownAt = ongoing.shownAt ?: return
        if (!ongoing.isShown) return
        val saved = flow.store.pendingWorkout?.savedAt
        val lastWrite = if (saved != null && saved > shownAt) saved else shownAt
        if (Duration.between(lastWrite, flow.now()) >= WorkoutSessionStore.resumeWindow) ongoing.end()
    }
}

/** The countdown the beat would move — the dispatch of `tick()`, read
 *  without moving anything. A frozen clock (a sheet open, a block held) is
 *  none. */
val WorkoutSession.runningClock: Countdown?
    get() {
        val clock = when (phase) {
            Phase.Warmup -> if (blockPause.isPaused) blockPause.reentry else warmup.clock
            is Phase.Rest -> if (blockPause.isPaused) blockPause.reentry else restClock
            Phase.Cooldown -> if (blockPause.isPaused) blockPause.reentry else cooldown.clock
            Phase.Work -> when {
                holdCountingIn -> holdCountInClock
                holdSwitchPausing -> holdSwitchClock
                holding -> holdClock
                else -> null
            }
            else -> null
        }
        return clock?.takeIf { it.isRunning }
    }
