//
//  The device half of the ongoing-notification suites: what the system
//  shows, what the flow fires, where the activity stands. Shared by
//  OngoingWorkoutTest and NotificationDeniedTest.
//

package com.dredfit

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationManager
import android.os.ParcelFileDescriptor
import android.os.SystemClock
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

abstract class OngoingTestCase : DredfitUITest() {

    protected val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    protected val app get() = instrumentation.targetContext.applicationContext as DredfitApp

    /** Every signal pair that fired, with its uptime and whether the
     *  activity was in front at that moment. */
    protected data class Fired(val tone: Tone, val atMs: Long, val inFront: Boolean)
    protected val fired = mutableListOf<Fired>()

    @After
    fun wakeAndStopListening() {
        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        instrumentation.runOnMainSync { app.signals().firedForTests = null }
    }

    protected data class Shown(val title: String?, val text: String?, val chronometer: Boolean, val countDown: Boolean,
                               val whenMs: Long)

    protected fun ongoing(): Notification? =
        app.getSystemService(NotificationManager::class.java).activeNotifications
            .firstOrNull { it.id == OngoingNotification.NOTIFICATION_ID }?.notification

    protected fun read(n: Notification) = Shown(
        title = n.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
        text = n.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
        chronometer = n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER),
        countDown = n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN),
        whenMs = n.`when`)

    /** Waits for the notification to show what `matches` wants. */
    protected fun awaitOngoing(timeoutMs: Long = 10_000, matches: (Shown) -> Boolean): Shown {
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

    protected fun awaitTrue(timeoutMs: Long = 5_000, condition: () -> Boolean): Boolean {
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return true
            Thread.sleep(100)
        }
        return condition()
    }

    /** No notification, no service, no wake lock. */
    protected fun assertGone(why: String) {
        assertTrue("$why: the notification", awaitTrue { ongoing() == null })
        assertTrue("$why: the service", awaitTrue { !serviceRunning() })
        assertFalse("$why: the wake lock", app.ongoing.isAwake)
        assertFalse("$why: the wake lock, as the system sees it", systemHoldsOurWakeLock())
    }

    /** Our tag among the wake locks held now — the "Wake Locks: size=N"
     *  block of `dumpsys power`, not its history further down, which
     *  remembers every acquire and release. */
    protected fun systemHoldsOurWakeLock(): Boolean {
        val lines = shell("dumpsys power").lines()
        val start = lines.indexOfFirst { it.startsWith("Wake Locks: size=") }
        check(start >= 0) { "dumpsys power has no wake lock block" }
        return lines.drop(start + 1).takeWhile { it.isNotBlank() }.any { OngoingNotification.WAKE_LOCK_TAG in it }
    }

    @Suppress("DEPRECATION") // still returns the caller's own services
    protected fun serviceRunning(): Boolean =
        app.getSystemService(ActivityManager::class.java).getRunningServices(Int.MAX_VALUE)
            .any { it.service.className == OngoingWorkoutService::class.java.name }

    protected fun restSeconds(): Int {
        var seconds = 0
        instrumentation.runOnMainSync {
            seconds = (checkNotNull(app.flows.active).flow.value.phase as Phase.Rest).seconds
        }
        return seconds
    }

    protected fun listen() {
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
    protected fun hearTheCountdown(withinMs: Long) {
        synchronized(fired) { fired.clear() }
        assertTrue("the 3-2-1 never came", awaitTrue(withinMs) { synchronized(fired) { fired.size >= 3 } })
        // The go waits for the person (WorkoutBeat.kt): the rest stands at
        // its end, as a suspended iOS app's would, until somebody is back.
        Thread.sleep(2_500)
        val heard = synchronized(fired) { fired.toList() }
        assertEquals("heard: $heard", listOf(Tone.Tick, Tone.Tick, Tone.Tick), heard.map { it.tone })
        assertTrue("every one with the app out of front: $heard", heard.none { it.inFront })
        for ((a, b) in heard.zipWithNext()) {
            val gap = b.atMs - a.atMs
            assertTrue("a second apart, not $gap ms: $heard", gap in 700..1_300)
        }
    }

    protected fun awaitStage(stage: Stage, timeoutMs: Long = 10_000) {
        assertTrue("the activity never reached $stage", awaitTrue(timeoutMs) {
            var there = false
            instrumentation.runOnMainSync {
                there = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(stage)
                    .any { it is MainActivity }
            }
            there
        })
    }

    protected fun shell(command: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command))
            .bufferedReader().use { it.readText() }
}
