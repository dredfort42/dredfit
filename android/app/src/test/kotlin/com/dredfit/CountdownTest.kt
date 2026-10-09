//
//  Port of ios/DredfitTests/CountdownTests.swift: the one countdown every
//  clock of the workout flow runs on. What each clock does when it ends is
//  the flow's; these pin what a tick reads.
//
//  An end is compared by its overshoot as a NUMBER (`assertEnded`): Swift's
//  `==` holds -0.0 equal to 0.0, a Kotlin data class does not, and a tick on
//  the end date itself reads `-0.0`.
//

package com.dredfit

import com.dredfit.workout.Countdown
import com.dredfit.workout.Countdown.Reading
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CountdownTest {

    private val start: Instant = Instant.ofEpochSecond(1_000)

    /** Swift's `start + seconds`. */
    private fun at(seconds: Double): Instant = start.plusNanos((seconds * 1e9).toLong())

    private fun at(seconds: Int): Instant = start.plusSeconds(seconds.toLong())

    private fun assertEnded(overshoot: Double, reading: Reading, message: String? = null, accuracy: Double = 0.0) {
        val ended = assertIs<Reading.Ended>(reading, message)
        assertEquals(overshoot, ended.overshoot, accuracy, message)
    }

    // MARK: - Reading

    @Test
    fun aStartedCountdownRunsFromItsLength() {
        val clock = Countdown()
        assertFalse(clock.isRunning)
        val end = clock.start(30, now = start)
        assertTrue(clock.isRunning)
        assertEquals(at(30), end)
        assertEquals(at(30), clock.endDate)
        assertEquals(30, clock.remaining)
        assertEquals(Reading.Unchanged, clock.read(start), "the second already shown is not news")
    }

    @Test
    fun readingChangesNothingUntilTheSecondIsShown() {
        val clock = Countdown()
        clock.start(30, now = start)
        assertEquals(Reading.Second(26), clock.read(at(4)))
        assertEquals(30, clock.remaining, "the owner decides when, and how animated")
        assertEquals(Reading.Second(26), clock.read(at(4)))
        clock.show(26)
        assertEquals(Reading.Unchanged, clock.read(at(4)))
    }

    @Test
    fun secondsRoundToTheNearestSoZeroIsTheEnd() {
        val clock = Countdown()
        clock.start(2, now = start)
        assertEquals(Reading.Second(1), clock.read(at(1.4)), "0.6 s left still shows 1")
        assertEnded(-0.4, clock.read(at(1.6)),
                    "a tick just before the end date reads a negative overshoot", accuracy = 0.000_1)
    }

    @Test
    fun theEndCarriesHowLateTheTickCame() {
        // The length of an absence is how a clock tells a beat the person was
        // there for from one that went off in a pocket.
        val clock = Countdown()
        clock.start(60, now = start)
        assertEnded(90.0, clock.read(at(60 + 90)))
    }

    @Test
    fun aStoppedCountdownReadsNothingHoweverLongItStands() {
        val clock = Countdown()
        assertEquals(Reading.Unchanged, clock.read(at(3_600)))
        clock.start(10, now = start)
        clock.freeze()
        assertEquals(Reading.Unchanged, clock.read(at(3_600)), "with no end date there is nothing to run out")
    }

    // MARK: - Freezing and resuming

    @Test
    fun aFrozenCountdownResumesFromTheSecondItShowed() {
        val clock = Countdown()
        clock.start(30, now = start)
        clock.show(21)
        clock.freeze()
        assertFalse(clock.isRunning)
        assertEquals(21, clock.remaining)

        clock.resume(now = at(600))
        assertEquals(at(621), clock.endDate, "the 21 s it froze with, not its whole length")
        assertEnded(0.0, clock.read(at(621)))
    }

    @Test
    fun aCountdownThatAlreadyShowsZeroStillEnds() {
        // Restored 0.3 s before its end: 0 is on screen with the date still
        // set, and there is no new second to show.
        val restored = Countdown()
        restored.run(until = at(0.3), now = start)
        assertEquals(0, restored.remaining)
        assertTrue(restored.isRunning)
        assertEnded(0.7, restored.read(at(1)), "a countdown on 0 must end, not hang there", accuracy = 0.000_1)

        val empty = Countdown()
        empty.start(0, now = start)
        assertEnded(0.0, empty.read(start))
    }

    @Test
    fun standingStopsTheClockOnTheSecondGiven() {
        // A hold handed back inside the mis-tap grace stands on its full
        // length again; a rest that is skipped stands on 0.
        val clock = Countdown()
        clock.start(30, now = start)
        clock.show(28)
        clock.stand(at = 30)
        assertFalse(clock.isRunning)
        assertEquals(30, clock.remaining)
        clock.stand(at = 0)
        assertEquals(0, clock.remaining)
    }

    @Test
    fun resettingKeepsARunningClockRunningAndAFrozenOneFrozen() {
        val running = Countdown()
        running.start(30, now = start)
        running.reset(to = 8, now = at(5))
        assertEquals(8, running.remaining)
        assertEquals(at(13), running.endDate)

        val frozen = Countdown()
        frozen.start(30, now = start)
        frozen.freeze()
        frozen.reset(to = 8, now = at(5))
        assertEquals(8, frozen.remaining)
        assertNull(frozen.endDate, "a paused block waits for Resume")
    }

    // MARK: - Moving the end

    @Test
    fun extendingMovesTheEndAndTheSecondOnScreen() {
        val clock = Countdown()
        clock.start(60, now = start)
        clock.extend(by = 15, now = at(50))
        assertEquals(at(75), clock.endDate)
        assertEquals(25, clock.remaining)
    }

    @Test
    fun extendingAStoppedClockStartsNothing() {
        val clock = Countdown()
        clock.extend(by = 15, now = start)
        assertFalse(clock.isRunning)
        assertEquals(0, clock.remaining)
    }

    @Test
    fun runningUntilARestoredDateShowsWhatIsLeftOfIt() {
        val clock = Countdown()
        clock.run(until = at(42.6), now = start)
        assertEquals(at(42.6), clock.endDate)
        assertEquals(43, clock.remaining)
    }

    // MARK: - The 3-2-1

    @Test
    fun onlyTheLastSecondsOnTheWayDownSignal() {
        val clock = Countdown()
        clock.start(10, now = start)
        clock.show(5)
        assertFalse(clock.signals(4, within = 3), "4 is before the window")
        clock.show(4)
        assertTrue(clock.signals(3, within = 3))
        clock.show(3)
        assertFalse(clock.signals(3, within = 3), "the same second twice is one signal")
    }

    @Test
    fun aBackgroundedClockSignalsOnlyTheSecondItLandsOn() {
        // No tick spam after backgrounding: from 30 straight to 2 is one tick.
        val clock = Countdown()
        clock.start(30, now = start)
        val second = assertIs<Reading.Second>(clock.read(at(28)), "two seconds are left").second
        assertEquals(2, second)
        assertTrue(clock.signals(second, within = 3))
    }

    @Test
    fun anExtendedClockSignalsAgainOnItsNewWayDown() {
        val clock = Countdown()
        clock.start(60, now = start)
        clock.show(2)
        clock.extend(by = 15, now = at(58))
        assertEquals(17, clock.remaining)
        clock.show(4)
        assertTrue(clock.signals(3, within = 3))
    }
}
