//
//  A workout with POST_NOTIFICATIONS refused: asked once at the start, and
//  nothing else changes — the foreground service still runs (Android lists
//  it in Task Manager instead of the shade), and the rest's 3-2-1 still
//  sounds with the app in the background.
//
//  RUNS ALONE, on a fresh install, so the permission has never been granted:
//  every other suite grants it (DredfitUITest.launch), and revoking it kills
//  the process the instrumentation runs in. Excluded from the suite by
//  `notClass` in build.gradle.kts, like ScreenshotWalk; run it with
//
//    ./gradlew :app:connectedDebugAndroidTest \
//      -Pandroid.testInstrumentationRunnerArguments.class=com.dredfit.NotificationDeniedTest \
//      -Pandroid.testInstrumentationRunnerArguments.notClass=com.dredfit.ScreenshotWalk
//

package com.dredfit

import android.Manifest
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.Stage
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NotificationDeniedTest : OngoingTestCase() {

    private fun granted() =
        app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    @Test
    fun refusedTheWorkoutStillRunsAndSoundsInTheBackground() {
        launch(Seed.Clean, fast = false, notificationsAllowed = false)
        check(!granted()) { "POST_NOTIFICATIONS is already granted: run this class alone on a fresh install (header)" }
        listen()
        val driver = WorkoutDriver(this)
        // One plain tap: the driver's confirm-by-gone loop reads the screen,
        // and under the system's dialog there is no screen to read.
        await(AX.startWorkout)
        compose.onAllNodesWithTag(AX.startWorkout)[0].performClick()
        // The ask: the system's dialog over the warm-up offer — our activity
        // paused under it. "Don't allow", tapped where the dialog draws it.
        awaitStage(Stage.PAUSED)
        tapDontAllow()
        awaitStage(Stage.RESUMED)
        assertTrue("still refused", !granted())

        driver.tapUntilGone(AX.warmupIntroSkip)
        driver.tapUntilGone(AX.exerciseDone)
        await(AX.skipRest)
        val seconds = restSeconds()
        assertTrue("the service runs without the permission", awaitTrue { serviceRunning() && app.ongoing.isUp })
        assertTrue("and holds the CPU for the rest", awaitTrue { app.ongoing.isAwake })

        shell("input keyevent KEYCODE_HOME")
        awaitStage(Stage.STOPPED)
        hearTheCountdown(withinMs = seconds * 1000L + 10_000)

        shell("am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n ${app.packageName}/${MainActivity::class.java.name}")
        awaitStage(Stage.RESUMED)
        driver.tapUntilGone(AX.workoutExit) { exists(AX.exitDiscard) }
        driver.tapUntilGone(AX.exitDiscard)
        await(AX.startWorkout)
        assertGone("a discarded workout leaves nothing behind")
    }

    /** The permission controller's deny button, found through the
     *  instrumentation's own accessibility connection — the suite carries no
     *  UiAutomator, and the dialog is not ours to tag. */
    private fun tapDontAllow() {
        val id = "com.android.permissioncontroller:id/permission_deny_button"
        check(awaitTrue(timeoutMs = 10_000) {
            val button = instrumentation.uiAutomation.rootInActiveWindow
                ?.findAccessibilityNodeInfosByViewId(id)?.firstOrNull()
            button?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
        }) { "no permission dialog with a deny button on screen" }
    }
}
