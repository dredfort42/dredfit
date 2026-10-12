//
//  The reminder's exact alarm on a device (reminders/ExactAlarm.kt): without
//  "Alarms & reminders" the window is inexact and Settings says how to fix
//  it; the grant alone rebuilds the window with exact alarms (the manifest
//  receiver, no return to the app needed); the row opens the permission's
//  own page, and the hint is gone on the return.
//
//  ONE test, and it runs only on a fresh install: Android 14+ installs the
//  app without the permission, and the way back is a revocation, which
//  kills the app's process — this one, with the test in it (probed on the
//  API 37 emulator, 12.10.2026). So nothing here revokes; a rerun on an
//  install that already holds the permission is skipped, not passed.
//

package com.dredfit

import android.app.AlarmManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.espresso.intent.Intents
import androidx.test.espresso.intent.Intents.intended
import androidx.test.espresso.intent.matcher.IntentMatchers.hasAction
import androidx.test.espresso.intent.matcher.IntentMatchers.hasData
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.Stage
import com.dredfit.ReminderTest.Companion.TAG_TIME
import com.dredfit.store.setReminderEnabled
import org.hamcrest.Matchers.allOf
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReminderExactAlarmTest : ReminderTestCase() {

    @After
    fun leaveNothingBehind() = clearReminders()

    @Test
    fun withoutThePermissionTheHintLeadsToItAndTheGrantMakesEveryAlarmExact() {
        assumeTrue("Android 12+: before it every app's alarm is exact", Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
        val alarms = app.getSystemService(AlarmManager::class.java)
        assumeFalse("the install may already set exact alarms (the permission, or the battery exemption); " +
                    "only a fresh, restricted one can run this", alarms.canScheduleExactAlarms())
        launch(Seed.Clean, fast = false)
        onStore { setReminderEnabled(true) }
        val inexact = systemAlarmWindows()
        assertTrue("the window is drawn", inexact.isNotEmpty())
        assertTrue("without the permission no alarm is exact: $inexact", inexact.none { it == "0" })

        tap(AX.settings)
        await(TAG_HINT)
        compose.onNodeWithTag(TAG_HINT)
            .assertTextEquals("To have the reminder arrive on time rather than up to an hour late, " +
                              "allow Dredfit to set alarms and reminders.")
        assertTrue(exists(TAG_TIME))

        // Granted from outside while the app stays on screen: no resume, so
        // only the manifest receiver can rebuild the window.
        shell("appops set ${app.packageName} SCHEDULE_EXACT_ALARM allow")
        assertTrue("the grant rebuilt the window with exact alarms",
                   awaitTrue(timeoutMs = 90_000) { systemAlarmWindows().let { it.isNotEmpty() && it.all { w -> w == "0" } } })
        assertTrue("as many as before", systemAlarmWindows().size == inexact.size)

        // Recorded, not stubbed: the permission's page really opens.
        Intents.init()
        try {
            tapOnce(TAG_ROW)
            intended(allOf(hasAction(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM),
                           hasData(Uri.fromParts("package", app.packageName, null))))
        } finally {
            Intents.release()
        }
        awaitStage(Stage.STOPPED)
        shell("input keyevent KEYCODE_BACK")
        awaitStage(Stage.RESUMED)
        compose.waitUntil(10_000) { !exists(TAG_HINT) }
        assertFalse(exists(TAG_ROW))
        assertTrue("the reminder itself stays as it was", exists(TAG_TIME))
    }

    private companion object {
        const val TAG_HINT = "reminder-exact"
        const val TAG_ROW = "reminder-exact-settings"
    }
}
