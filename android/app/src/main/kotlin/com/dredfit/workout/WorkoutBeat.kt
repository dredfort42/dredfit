//
//  The flow's one-second beat and who keeps it. No Swift twin: on iOS the
//  beat is the flow screen's `Timer.publish(every: 1)`, and a backgrounded
//  iOS app runs no timer — the flow is LEFT (`sceneLeft`) and nothing sounds
//  until the person comes back. Android keeps the workout going behind the
//  ongoing notification instead: its foreground service keeps the process
//  in front, so the beat — and every tone and haptic it fires — runs on with
//  the screen off or another app on top.
//
//  WHO IS PRESENT. The flow is driven while it is on screen OR while the
//  ongoing notification holds it. Only losing both is leaving, and only then
//  is `sceneLeft` stamped: a hands-free hold run that sounded every set with
//  the phone face down was trained, and charging it to an absence would cut
//  it out of the workout's duration. Without the notification (the rating,
//  a forgotten workout, a service the system refused) the iOS rule stands
//  unchanged: off screen, the beat stops and the absence is measured.
//
//  THE CPU. A main-looper timer counts uptime, which stops while the CPU
//  sleeps; with the screen off the device suspends within seconds and a
//  3-2-1 would land whenever something else woke it. So the wake lock is held
//  exactly while a countdown runs — the only time a beat can do anything —
//  and released while the flow waits for a tap, which only comes with the
//  screen on. A workout left mid-set holds nothing.
//
//  Plain Kotlin on an injected timer: the decisions run in a JVM test
//  (WorkoutBeatTest); the main-looper timer is ui/workout/WorkoutFlowView.kt's.
//

package com.dredfit.workout

import com.dredfit.workout.WorkoutSession.Phase

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

    /** The activity started (`true`) or stopped — iOS's scene phase. */
    fun screen(visible: Boolean) {
        this.visible = visible
        settle()
    }

    /** One second of the flow. */
    fun beat() {
        act { if (exitAlertShown) primeComingBack() else tick() }
        retireIfForgotten()
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

    private fun settle() {
        if (closed) return
        val present = visible || ongoing.isShown
        if (present && !isRunning) {
            isRunning = true
            act { sceneCameBack() }
            timer.start(::beat)
        } else if (!present && isRunning) {
            isRunning = false
            timer.stop()
            act { sceneLeft() }
        }
        ongoing.keepAwake(isRunning && !exitAlertShown && flow.clockRunning)
    }

    /**
     * The forgotten-workout rule of the settlement (`settleAbandonedWorkout`,
     * twelve hours without a write) ends the notification too: past it iOS
     * would no longer treat the workout as interrupted, and a service kept
     * that long is a battery nobody is training on. The flow itself stays —
     * it owns its snapshot, and coming back to it is still coming back.
     */
    private fun retireIfForgotten() {
        val shownAt = ongoing.shownAt ?: return
        if (!ongoing.isShown) return
        val saved = flow.store.pendingWorkout?.savedAt
        val lastWrite = if (saved != null && saved > shownAt) saved else shownAt
        if (WorkoutSessionStore.isForgotten(lastWrite, flow.now())) ongoing.end()
    }
}

/** A countdown the beat would move — the dispatch of `tick()`, read without
 *  moving anything. A frozen clock (a sheet open, a block held) is not one. */
val WorkoutSession.clockRunning: Boolean
    get() = when (phase) {
        Phase.Warmup -> if (blockPause.isPaused) blockPause.reentry.isRunning else warmup.clock.isRunning
        is Phase.Rest -> if (blockPause.isPaused) blockPause.reentry.isRunning else restClock.isRunning
        Phase.Cooldown -> if (blockPause.isPaused) blockPause.reentry.isRunning else cooldown.clock.isRunning
        Phase.Work -> holdCountingIn || holdSwitchPausing || holding
        else -> false
    }
