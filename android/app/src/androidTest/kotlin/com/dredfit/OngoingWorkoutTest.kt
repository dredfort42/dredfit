//
//  The ongoing notification on a device: it comes with the workout, shows
//  what the iOS Live Activity shows, keeps a rest's 3-2-1 on its seconds with
//  the app in the background or the screen off — the go, as on iOS, waits
//  for the person — opens the flow on a tap, and goes — with its service and
//  the wake lock — when the
//  workout is finished or thrown away. Android-only: iOS's tile is drawn by
//  the system, and a backgrounded iOS app plays nothing.
//
//  At real speed: under the fast flag a rest is one second and its 3-2-1
//  never exists.
//

package com.dredfit

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.Stage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

@RunWith(AndroidJUnit4::class)
class OngoingWorkoutTest : OngoingTestCase() {

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
        awaitOngoing { it.text == "Next up" && !it.chronometer }
        assertTrue("released while the rest stands at its end", awaitTrue { !app.ongoing.isAwake })

        // A tap on the notification brings the flow back, and the first tick
        // back hands over the set.
        checkNotNull(ongoing()?.contentIntent).send()
        awaitStage(Stage.RESUMED)
        val next = awaitOngoing { it.text?.startsWith("set 2 of") == true }
        assertEquals("the same movement, its next set", set.title, next.title)
        await(AX.exerciseDone)

        // Finished from a running rest: the lock is held right up to the
        // rating, and the tile's end is what lets it go.
        driver.tapUntilGone(AX.exerciseDone)
        await(AX.skipRest)
        assertTrue(awaitTrue { app.ongoing.isAwake })
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
        assertTrue("released while the rest stands at its end", awaitTrue { !app.ongoing.isAwake })

        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        awaitStage(Stage.RESUMED)
        awaitOngoing { it.text?.startsWith("set 2 of") == true }
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
}
