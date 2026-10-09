//
//  The tile as the workout flow drives it. Port of
//  ios/Dredfit/LiveActivityController.swift: the `WorkoutActivityDriving`
//  protocol, and the controller behind it — ActivityKit there, the ongoing
//  notification here. The controller is plain Kotlin over `OngoingHost`, so
//  the order of start / update / end runs in a JVM test; the notification,
//  its foreground service and the wake lock are ongoing/OngoingNotification.kt.
//

package com.dredfit.workout

import java.time.Instant

interface WorkoutActivityDriving {
    fun start(sessionNumber: Int, state: ActivityState)
    fun update(state: ActivityState)
    fun end()
}

/** The device half: the foreground service with its notification, and the
 *  CPU kept awake while a countdown has to land on its second. */
interface OngoingHost {
    /** Between the first `show` and `hide` — false again when the system
     *  refused the service, so the flow falls back to the iOS rule. */
    val isUp: Boolean
    /** Starts the service on the first call, redraws the notification after. */
    fun show(content: OngoingContent)
    /** Stops the service, takes the notification away, releases the CPU. */
    fun hide()
    /** Holds or releases the partial wake lock; a repeat is a no-op. Only
     *  between `show` and `hide`. */
    fun keepAwake(awake: Boolean)
}

/**
 * `WorkoutActivityController` for Android. As on iOS, an update or an end
 * with no tile up does nothing: the flow ends the tile on the rating, and a
 * late update from a sheet closing must not bring it back.
 */
class OngoingWorkout(private val host: OngoingHost, private val now: () -> Instant) : WorkoutActivityDriving {

    private var started = false

    /** The notification is up and the service with it. */
    val isShown: Boolean get() = started && host.isUp

    /** When this flow put it up — the floor of the forgotten-workout clock,
     *  so an older snapshot on disk cannot retire a tile just shown. */
    var shownAt: Instant? = null
        private set

    private var awake = false

    override fun start(sessionNumber: Int, state: ActivityState) {
        started = true
        shownAt = now()
        host.show(OngoingContent.of(state, now()))
    }

    override fun update(state: ActivityState) {
        if (!isShown) return
        host.show(OngoingContent.of(state, now()))
    }

    override fun end() {
        if (!started) return
        started = false
        awake = false
        host.hide()
    }

    /** The CPU stays up only while the tile is: a lock outliving the
     *  notification would be a workout nobody can see holding the battery. */
    fun keepAwake(awake: Boolean) {
        val wanted = awake && isShown
        if (wanted == this.awake) return
        this.awake = wanted
        host.keepAwake(wanted)
    }
}
