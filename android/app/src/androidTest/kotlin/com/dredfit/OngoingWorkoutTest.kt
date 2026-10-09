//
//  The ongoing notification on a device: it comes with the workout, shows
//  what the iOS Live Activity shows, keeps the flow's tones and haptics on
//  their seconds with the app in the background or the screen off, opens the
//  flow on a tap, and goes — with its service and the wake lock — when the
//  workout is finished or thrown away. Android-only: iOS's tile is drawn by
//  the system, and a backgrounded iOS app plays nothing.
//
//  At real speed: under the fast flag a rest is one second and its 3-2-1
//  never exists.
//

package com.dredfit

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationManager
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.dredfit.ongoing.OngoingNotification
import com.dredfit.ongoing.OngoingWorkoutService
import com.dredfit.signals.CountdownSounds.Tone
import com.dredfit.workout.WorkoutSession.Phase
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

@RunWith(AndroidJUnit4::class)
class OngoingWorkoutTest : DredfitUITest() {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as DredfitApp

    /** Every signal pair that fired, with its uptime and whether the
     *  activity was in front at that moment. */
    private data class Fired(val tone: Tone, val atMs: Long, val inFront: Boolean)
    private val fired = mutableListOf<Fired>()

    @After
    fun wakeAndStopListening() {
        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        instrumentation.runOnMainSync { app.signals().firedForTests = null }
    }

    /** The countdown of a rest, heard with the app behind the launcher; the
     *  notification shows the rest and follows the flow onto the next set;
     *  a tap on it opens the flow; Finish now takes it away. */
    @Test
    fun aRestInTheBackgroundStillCountsDownOnItsSecondsAndTheTileFollowsIt() {
        launch(Seed.Clean, fast = false)
        listen()
        val driver = WorkoutDriver(this)
        driver.tapUntilGone(AX.startWorkout)
        await(AX.warmupIntroSkip)
        val offer = awaitOngoing { it.title == "WARM-UP" }
        assertFalse("nothing counts down on the warm-up's offer", offer.chronometer)
        assertFalse("and nothing holds the CPU for it", app.ongoing.isAwake)

        driver.tapUntilGone(AX.warmupIntroSkip)
        val set = awaitOngoing { it.text?.startsWith("set 1 of") == true }
        assertFalse(set.chronometer)
        driver.tapUntilGone(AX.exerciseDone)
        await(AX.skipRest)
        val rest = awaitOngoing { it.text == "Next up" }
        val seconds = restSeconds()
        assertTrue("the rest counts down", rest.chronometer && rest.countDown)
        assertTrue("to the rest's own end (${rest.whenMs - System.currentTimeMillis()} ms away)",
                   abs(rest.whenMs - System.currentTimeMillis() - seconds * 1000L) < 3_000)
        assertTrue("a running rest holds the CPU", awaitTrue { app.ongoing.isAwake })
        assertTrue("and the system sees the lock", systemHoldsOurWakeLock())

        shell("input keyevent KEYCODE_HOME")
        awaitStage(Stage.STOPPED)
        hearTheCountdown(withinMs = seconds * 1000L + 10_000)
        val next = awaitOngoing { it.text?.startsWith("set 2 of") == true }
        assertEquals("the same movement, its next set", set.title, next.title)
        assertTrue("released once the rest handed over the set", awaitTrue { !app.ongoing.isAwake })

        // A tap on the notification brings the flow back where it is.
        checkNotNull(ongoing()?.contentIntent).send()
        awaitStage(Stage.RESUMED)
        await(AX.exerciseDone)

        driver.tapUntilGone(AX.workoutExit) { exists(AX.exitFinishNow) }
        driver.tapUntilGone(AX.exitFinishNow)
        await(AX.ratingPlan)
        assertGone("the rating has nothing for the tile to describe")
        driver.tapUntilGone(AX.ratingPlan)
    }

    /** With the screen off, the same; then discarding the workout takes the
     *  notification, the service and the wake lock with it. */
    @Test
    fun withTheScreenOffTheCountdownStillSoundsAndDiscardingEndsEverything() {
        launch(Seed.Clean, fast = false)
        listen()
        val driver = WorkoutDriver(this)
        driver.tapUntilGone(AX.startWorkout)
        driver.tapUntilGone(AX.warmupIntroSkip)
        driver.tapUntilGone(AX.exerciseDone)
        await(AX.skipRest)
        awaitOngoing { it.text == "Next up" }
        val seconds = restSeconds()

        shell("input keyevent KEYCODE_SLEEP")
        awaitStage(Stage.STOPPED)
        hearTheCountdown(withinMs = seconds * 1000L + 10_000)

        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        awaitStage(Stage.RESUMED)
        driver.tapUntilGone(AX.exerciseDone)
        await(AX.skipRest)
        assertTrue(awaitTrue { app.ongoing.isAwake })
        driver.tapUntilGone(AX.workoutExit) { exists(AX.exitDiscard) }
        driver.tapUntilGone(AX.exitDiscard)
        await(AX.startWorkout)
        assertGone("a discarded workout leaves nothing behind")
    }

    /** "Finish later" closes the flow too, and with it everything. */
    @Test
    fun finishingLaterEndsTheNotification() {
        launch(Seed.Clean, fast = false)
        val driver = WorkoutDriver(this)
        driver.tapUntilGone(AX.startWorkout)
        driver.tapUntilGone(AX.warmupIntroSkip)
        driver.tapUntilGone(AX.exerciseDone)
        await(AX.skipRest)
        awaitOngoing { it.text == "Next up" }
        driver.tapUntilGone(AX.workoutExit) { exists(AX.exitFinishLater) }
        driver.tapUntilGone(AX.exitFinishLater)
        await(AX.resumeContinue)
        assertGone("Today keeps the workout; nothing is running")
    }

    // MARK: - Helpers

    private data class Shown(val title: String?, val text: String?, val chronometer: Boolean, val countDown: Boolean,
                             val whenMs: Long)

    private fun ongoing(): Notification? =
        app.getSystemService(NotificationManager::class.java).activeNotifications
            .firstOrNull { it.id == OngoingNotification.NOTIFICATION_ID }?.notification

    private fun read(n: Notification) = Shown(
        title = n.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
        text = n.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
        chronometer = n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER),
        countDown = n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN),
        whenMs = n.`when`)

    /** Waits for the notification to show what `matches` wants. */
    private fun awaitOngoing(timeoutMs: Long = 10_000, matches: (Shown) -> Boolean): Shown {
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        var last: Shown? = null
        while (SystemClock.uptimeMillis() < deadline) {
            last = ongoing()?.let(::read)
            if (last != null && matches(last)) {
                val n = checkNotNull(ongoing())
                assertTrue("the notification carries the foreground service",
                           n.flags and Notification.FLAG_FOREGROUND_SERVICE != 0)
                return last
            }
            Thread.sleep(100)
        }
        throw AssertionError("the ongoing notification never showed it; last: $last")
    }

    private fun awaitTrue(timeoutMs: Long = 5_000, condition: () -> Boolean): Boolean {
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return true
            Thread.sleep(100)
        }
        return condition()
    }

    /** No notification, no service, no wake lock. */
    private fun assertGone(why: String) {
        assertTrue("$why: the notification", awaitTrue { ongoing() == null })
        assertTrue("$why: the service", awaitTrue { !serviceRunning() })
        assertFalse("$why: the wake lock", app.ongoing.isAwake)
        assertFalse("$why: the wake lock, as the system sees it", systemHoldsOurWakeLock())
    }

    /** Our tag among the wake locks held now — the "Wake Locks: size=N"
     *  block of `dumpsys power`, not its history further down, which
     *  remembers every acquire and release. */
    private fun systemHoldsOurWakeLock(): Boolean {
        val lines = shell("dumpsys power").lines()
        val start = lines.indexOfFirst { it.startsWith("Wake Locks: size=") }
        check(start >= 0) { "dumpsys power has no wake lock block" }
        return lines.drop(start + 1).takeWhile { it.isNotBlank() }.any { OngoingNotification.WAKE_LOCK_TAG in it }
    }

    @Suppress("DEPRECATION") // still returns the caller's own services
    private fun serviceRunning(): Boolean =
        app.getSystemService(ActivityManager::class.java).getRunningServices(Int.MAX_VALUE)
            .any { it.service.className == OngoingWorkoutService::class.java.name }

    private fun restSeconds(): Int {
        var seconds = 0
        instrumentation.runOnMainSync {
            seconds = (checkNotNull(app.flows.active).flow.value.phase as Phase.Rest).seconds
        }
        return seconds
    }

    private fun listen() {
        instrumentation.runOnMainSync {
            app.signals().firedForTests = { tone ->
                val inFront = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).isNotEmpty()
                synchronized(fired) { fired += Fired(tone, SystemClock.uptimeMillis(), inFront) }
            }
        }
    }

    /** The rest's 3-2-1 and its go, every one fired with the activity out of
     *  front, a second apart — on the second, not whenever something woke
     *  the CPU. */
    private fun hearTheCountdown(withinMs: Long) {
        synchronized(fired) { fired.clear() }
        assertTrue("the go never came", awaitTrue(withinMs) { synchronized(fired) { fired.any { it.tone == Tone.Go } } })
        val heard = synchronized(fired) { fired.toList() }
        assertEquals("heard: $heard", listOf(Tone.Tick, Tone.Tick, Tone.Tick, Tone.Go), heard.map { it.tone })
        assertTrue("every one with the app out of front: $heard", heard.none { it.inFront })
        for ((a, b) in heard.zipWithNext()) {
            val gap = b.atMs - a.atMs
            assertTrue("a second apart, not $gap ms: $heard", gap in 700..1_300)
        }
    }

    private fun awaitStage(stage: Stage, timeoutMs: Long = 10_000) {
        assertTrue("the activity never reached $stage", awaitTrue(timeoutMs) {
            var there = false
            instrumentation.runOnMainSync {
                there = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(stage)
                    .any { it is MainActivity }
            }
            there
        })
    }

    private fun shell(command: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command))
            .bufferedReader().use { it.readText() }
}
