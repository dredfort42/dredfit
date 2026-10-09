//
//  The reminder against a permission never granted. The switch asks, as iOS
//  asks: refused, it flips back off and the denied note says why, with its
//  way to the app's notification settings. An imported backup that carries
//  the reminder ON is re-checked the same way (owner decision, 09.10.2026)
//  and lands in the same note. Refused twice, the system answers "no"
//  without a dialog — the note again, at once. Android's own restore (the
//  state back, the device mark not) is re-checked on the first launch and
//  lands in the same note. Granted at last (from the shell, as from the
//  system settings), the switch draws the window.
//
//  ONE method, in order, because the order is the subject: Android shows the
//  dialog twice at most, and a revoke would kill the process the
//  instrumentation runs in. RUNS ALONE, on a fresh install, like
//  NotificationDeniedTest (@RunsAlone):
//
//    ./gradlew :app:connectedDebugAndroidTest \
//      -Pandroid.testInstrumentationRunnerArguments.class=com.dredfit.ReminderDeniedTest \
//      -Pandroid.testInstrumentationRunnerArguments.notAnnotation=org.junit.Ignore
//

package com.dredfit

import android.Manifest
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.Stage
import com.dredfit.ReminderTest.Companion.TAG_DENIED
import com.dredfit.ReminderTest.Companion.TAG_OPEN_SETTINGS
import com.dredfit.ReminderTest.Companion.TAG_TIME
import com.dredfit.ReminderTest.Companion.TAG_TOGGLE
import com.dredfit.store.AppStore
import com.dredfit.store.DeviceMark
import com.dredfit.store.exportBackup
import com.dredfit.store.importBackup
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.file.Files

@RunsAlone
@RunWith(AndroidJUnit4::class)
class ReminderDeniedTest : ReminderTestCase() {

    private fun granted() =
        app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    @After
    fun leaveNothingBehind() = clearReminders()

    @Test
    fun refusedTheSwitchSaysWhyAndGrantedItDrawsTheWindow() {
        launch(Seed.Clean, fast = false, notificationsAllowed = false)
        check(!granted()) { "POST_NOTIFICATIONS is already granted: run this class alone on a fresh install (header)" }

        // 1. The switch asks; "Don't allow".
        tap(AX.settings)
        tapOnce(TAG_TOGGLE)
        awaitStage(Stage.PAUSED)
        tapDialogButton(DENY)
        awaitStage(Stage.RESUMED)
        await(TAG_DENIED)
        compose.onNodeWithTag(TAG_TOGGLE).assertIsOff()
        assertFalse("the time row goes with the switch", exists(TAG_TIME))
        assertTrue("nothing scheduled", pendingIds().isEmpty())

        // 2. The note's way out: the app's notification settings, and back.
        tapOnce(TAG_OPEN_SETTINGS)
        awaitStage(Stage.STOPPED)
        val top = shell("dumpsys activity activities").lines().firstOrNull { it.contains("topResumedActivity") }.orEmpty()
        assertTrue("the system's settings are on top: $top", top.contains("com.android.settings"))
        shell("input keyevent KEYCODE_BACK")
        awaitStage(Stage.RESUMED)

        // 3. A backup that carries the reminder ON, imported from Settings
        //    (closed and reopened first, so no note is left on screen): the
        //    import asks again — the second and last dialog — and a refusal
        //    lands in the note, never a switch that went quietly off.
        tap(AX.settingsDone)
        tap(AX.settings)
        await(TAG_TOGGLE)
        assertFalse("the note goes with the screen that showed it", exists(TAG_DENIED))
        val scratch = Files.createTempFile(app.cacheDir.toPath(), "source", ".json")
        val backup = AppStore(scratch).run {
            update { it.copy(settings = it.settings.copy(reminderEnabled = true, onboardingCompleted = true,
                                                         restWeekdays = emptySet())) }
            exportBackup()
        }
        Files.deleteIfExists(scratch)
        onStore { importBackup(backup) }
        awaitStage(Stage.PAUSED)
        tapDialogButton(DENY)
        awaitStage(Stage.RESUMED)
        await(TAG_DENIED)
        compose.onNodeWithTag(TAG_TOGGLE).assertIsOff()
        assertFalse("the imported flag does not survive a refusal", readStore { settings.reminderEnabled })
        assertTrue(pendingIds().isEmpty())

        // 4. Refused twice: the system answers without a dialog, and the note
        //    is back at once.
        tap(AX.settingsDone)
        tap(AX.settings)
        await(TAG_TOGGLE)
        tapOnce(TAG_TOGGLE)
        await(TAG_DENIED)
        compose.onNodeWithTag(TAG_TOGGLE).assertIsOff()
        assertFalse(granted())

        // 5. Android's own restore: the state file comes back with the
        //    reminder ON, the device mark (noBackupFilesDir) does not. The
        //    first launch re-checks — refused here — and the switch is off
        //    with the note, never on with nothing to post.
        tap(AX.settingsDone)
        onStore { update { it.copy(settings = it.settings.copy(reminderEnabled = true)) } }
        val mark = DeviceMark.file(app.noBackupFilesDir)
        assertTrue("the device mark of the earlier launches", mark.exists())
        assertTrue(mark.delete())
        relaunchFromDisk()
        assertTrue("re-checked and turned off", awaitTrue(timeoutMs = 10_000) { !readStore { settings.reminderEnabled } })
        assertTrue("the check is marked done", mark.exists())
        tap(AX.settings)
        await(TAG_DENIED)
        compose.onNodeWithTag(TAG_TOGGLE).assertIsOff()
        assertTrue(pendingIds().isEmpty())

        // 6. Granted in the system's settings (here, the shell's grant): the
        //    switch stays on and draws the window.
        instrumentation.uiAutomation.grantRuntimePermission(app.packageName, Manifest.permission.POST_NOTIFICATIONS)
        tapOnce(TAG_TOGGLE)
        await(TAG_TIME)
        compose.onNodeWithTag(TAG_TOGGLE).assertIsOn()
        assertFalse("a granted ask clears the note", exists(TAG_DENIED))
        assertTrue("the window is drawn", awaitTrue { pendingIds().size == expectedSlots(9, 0) })
        assertTrue(readStore { settings.reminderEnabled })
    }

    /** One tap, no confirm-by-gone loop: under the system's dialog there is
     *  no screen to read. */
    private fun tapOnce(tag: String) {
        await(tag)
        val node = compose.onAllNodesWithTag(tag)[0]
        runCatching { node.performScrollTo() }
        node.performClick()
    }

    /** The permission controller's button, found through the
     *  instrumentation's own accessibility connection (NotificationDeniedTest). */
    private fun tapDialogButton(ids: List<String>) {
        check(awaitTrue(timeoutMs = 10_000) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            val button = ids.firstNotNullOfOrNull { root?.findAccessibilityNodeInfosByViewId(it)?.firstOrNull() }
            button?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
        }) { "no permission dialog with $ids on screen" }
    }

    private companion object {
        /** "Don't allow" — on the second ask the button that also means
         *  "don't ask again" carries an id of its own. */
        val DENY = listOf("com.android.permissioncontroller:id/permission_deny_button",
                          "com.android.permissioncontroller:id/permission_deny_and_dont_ask_again_button")
    }
}
