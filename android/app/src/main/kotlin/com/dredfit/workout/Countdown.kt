//
//  One countdown of the workout flow. Port of ios/Dredfit/Countdown.swift.
//
//  The clock is an end DATE, never a tick count, so a backgrounded app — or
//  one Android killed and restored — loses nothing: every tick re-reads the
//  date. A mutable class standing in for a Swift struct: the flow owns each
//  countdown and never shares one; `copy()` is the Swift `var b = a`.
//

package com.dredfit.workout

import com.dredfit.core.roundedAwayFromZero
import java.time.Duration
import java.time.Instant

class Countdown {
    var endDate: Instant? = null
        private set
    var remaining: Int = 0
        private set

    val isRunning: Boolean get() = endDate != null

    /** Runs `seconds` from `now`, and returns the end date for whatever has
     *  to count down to the same moment (the ongoing notification). */
    fun start(seconds: Int, now: Instant): Instant {
        val end = now.plusSeconds(seconds.toLong())
        remaining = seconds
        endDate = end
        return end
    }

    /** Runs until `end`, showing what is left of it — a countdown restored
     *  from a date written before the process died. */
    fun run(until: Instant, now: Instant) {
        endDate = until
        remaining = maxOf(0, roundedAwayFromZero(seconds(now, until)).toInt())
    }

    /** Runs on from the second on screen — the way out of a freeze. NOT a
     *  floor for a count: see `WorkoutSession.restartFrozenStage`. */
    fun resume(now: Instant) {
        endDate = now.plusSeconds(remaining.toLong())
    }

    /** Stops the clock; the second on screen stays, ready for `resume`. */
    fun freeze() {
        endDate = null
    }

    /** Stops the clock and shows `seconds`. */
    fun stand(at: Int) {
        endDate = null
        remaining = at
    }

    /** A running countdown runs `seconds` from `now`; a frozen one stays
     *  frozen on them. */
    fun reset(to: Int, now: Instant) {
        if (isRunning) start(to, now) else remaining = to
    }

    /** Moves a running end date, and the second on screen with it. */
    fun extend(by: Int, now: Instant) {
        val end = endDate ?: return
        run(until = end.plusSeconds(by.toLong()), now = now)
    }

    /** What a tick found. */
    sealed interface Reading {
        /** Not running, or still above zero on the second already shown. */
        data object Unchanged : Reading
        /** A new second to show; nothing has been shown yet — see `show`. */
        data class Second(val second: Int) : Reading
        /** Ran out, `overshoot` seconds past the end date: near zero in front
         *  of the person, the length of the absence after one. */
        data class Ended(val overshoot: Double) : Reading
    }

    /**
     * Reads the clock without changing anything. Rounded to the nearest
     * second, so a running countdown reaches 0 half a second before its end.
     * ZERO ALWAYS ENDS IT, even with 0 already on screen — a rest restored in
     * its last half-second has no new second to show and would otherwise never
     * end (fix/countdown-ends-at-zero on iOS). And the second a countdown was
     * started on is never reported: `Second` only when it differs from the one
     * shown, which is why a prime keyed on a second is asked from the start
     * too (`primeBeforeTheCount`).
     */
    fun read(now: Instant): Reading {
        val end = endDate ?: return Reading.Unchanged
        val left = seconds(now, end)
        val second = maxOf(0, roundedAwayFromZero(left).toInt())
        if (second == 0) return Reading.Ended(overshoot = -left)
        return if (second == remaining) Reading.Unchanged else Reading.Second(second)
    }

    /** Shows a second `read` returned. */
    fun show(second: Int) {
        remaining = second
    }

    /** The 3-2-1: one of the last `signalSeconds`, reached on the way DOWN. */
    fun signals(second: Int, within: Int): Boolean = second <= within && second < remaining

    fun copy(): Countdown = Countdown().also { it.endDate = endDate; it.remaining = remaining }

    override fun equals(other: Any?): Boolean =
        other is Countdown && endDate == other.endDate && remaining == other.remaining

    override fun hashCode(): Int = 31 * (endDate?.hashCode() ?: 0) + remaining

    override fun toString(): String = "Countdown(endDate=$endDate, remaining=$remaining)"

    companion object {
        /** Swift's `timeIntervalSince`: a signed Double of seconds. Not
         *  `toNanos()`, which overflows past 292 years — a date off disk can
         *  be anything. */
        fun seconds(from: Instant, to: Instant): Double {
            val d = Duration.between(from, to)
            return d.seconds.toDouble() + d.nano / 1e9
        }
    }
}
