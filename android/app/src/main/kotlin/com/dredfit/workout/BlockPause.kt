//
//  The pause of the guided blocks (issue #61) and of a hands-free hold run's
//  rest. Port of ios/Dredfit/BlockPause.swift, where the reasoning lives.
//  Orthogonal to the blocks' stage machine: the frozen seconds stay with the
//  block; this owns only the fact that they are frozen and how far the way
//  back in has got.
//

package com.dredfit.workout

import java.time.Instant

object BlockPause {

    /** The way back into a frozen position: the COUNT-IN, so the two cannot
     *  drift apart. */
    val reentrySeconds: Int get() = GetReady.countInSeconds

    /** How far past a stage boundary a block may run and still just carry on;
     *  beyond it the phone was somewhere else and the block freezes. The
     *  rest's hands-free run reads the same threshold. Under the UI suite's
     *  fast flag a whole stage is one second, so the real threshold would read
     *  an ordinary late tick on a loaded runner as an absence (BlockPause.swift). */
    val absenceSeconds: Int get() = if (UITestFlags.fast) 60 else GetReady.countInSeconds

    /** The seconds a REST picks up after a pause or a closed sheet: floored at
     *  the count-in, capped by the rest's own total. */
    fun restAfterPause(remaining: Int, total: Int): Int = maxOf(remaining, minOf(reentrySeconds, total))

    /** A transition never picks up less than the count-in; a position takes
     *  the re-entry instead and keeps exactly the seconds it froze with. */
    fun stageAfterPause(remaining: Int, stage: GuidedStage): Int =
        if (needsReentry(stage)) remaining else maxOf(remaining, reentrySeconds)

    /** A frozen transition — the side switch included — resumes straight
     *  into itself: it already IS the way back in. */
    fun needsReentry(stage: GuidedStage): Boolean = stage != GuidedStage.getReady && stage != GuidedStage.switchPause

    /** What a tick asks of the flow. */
    @Suppress("EnumEntryName")
    enum class Tick { nothing, redraw, signal, over }

    /** Swift's `BlockPause.State`, a value: `copy()` is `var b = a`. */
    class State {
        var isPaused: Boolean = false
            private set
        var reentry: Countdown = Countdown()
            private set

        val reentryRemaining: Int get() = reentry.remaining
        val reentryEndDate: Instant? get() = reentry.endDate

        /** Frozen and standing still. */
        val isHeld: Boolean get() = isPaused && reentryRemaining == 0

        /** Counting the user back in. */
        val isReentering: Boolean get() = isPaused && reentryRemaining > 0

        /** Freezes; on a running way back in too — the lead-in starts over on
         *  the next resume. */
        fun hold() {
            isPaused = true
            reentry.stand(at = 0)
        }

        /** A zero-length way back in would be a go with no count: hold. */
        fun beginReentry(seconds: Int, now: Instant) {
            if (seconds <= 0) return hold()
            isPaused = true
            reentry.start(seconds, now)
        }

        fun clear() {
            isPaused = false
            reentry = Countdown()
        }

        /** The technique sheet freezes the way back in like it freezes a
         *  position. */
        fun freezeForSheet() = reentry.freeze()

        /** …and hands back exactly what it froze. A held block stays held. */
        fun thawAfterSheet(now: Instant) {
            if (!isReentering) return
            reentry.resume(now)
        }

        fun tick(now: Instant, signalSeconds: Int): Tick =
            when (val reading = reentry.read(now)) {
                Countdown.Reading.Unchanged -> Tick.nothing
                is Countdown.Reading.Ended -> Tick.over
                is Countdown.Reading.Second -> {
                    val audible = reentry.signals(reading.second, within = signalSeconds)
                    reentry.show(reading.second)
                    if (audible) Tick.signal else Tick.redraw
                }
            }

        fun copy(): State = State().also { it.isPaused = isPaused; it.reentry = reentry.copy() }

        override fun equals(other: Any?): Boolean =
            other is State && isPaused == other.isPaused && reentry == other.reentry

        override fun hashCode(): Int = 31 * isPaused.hashCode() + reentry.hashCode()
    }
}
