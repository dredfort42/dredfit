//
//  The reminder's battery hint on a device (reminders/BatteryHint.kt): the
//  line under the reminder, its row to the app's page in the phone's
//  settings, and the hint gone on the return once the app is unrestricted.
//
//  The emulator is a Google phone, so the make is played through
//  `BatteryHint.manufacturerForTests`. The exemption is the REAL one: `cmd
//  deviceidle whitelist +pkg` puts the app on the list the person's
//  "Unrestricted" puts it on (`dumpsys deviceidle whitelist` showed
//  `User,com.dredfit.dredfit` on the Galaxy A16), and PowerManager reads it
//  as it would on the phone.
//

package com.dredfit

import android.net.Uri
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
import com.dredfit.ReminderTest.Companion.TAG_TOGGLE
import com.dredfit.reminders.BatteryHint
import com.dredfit.store.setReminderEnabled
import org.hamcrest.Matchers.allOf
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReminderBatteryHintTest : ReminderTestCase() {

    private fun unrestricted(on: Boolean) {
        shell("cmd deviceidle whitelist ${if (on) "+" else "-"}${app.packageName}")
    }

    @After
    fun restoreThePhone() {
        BatteryHint.manufacturerForTests = null
        unrestricted(false)
        clearReminders()
    }

    @Test
    fun onASamsungTheRowOpensTheAppsPageAndTheHintGoesOnceTheAppIsUnrestricted() {
        BatteryHint.manufacturerForTests = "samsung"
        unrestricted(false)
        launch(Seed.Clean, fast = false)
        onStore { setReminderEnabled(true) }
        tap(AX.settings)
        await(TAG_HINT)
        compose.onNodeWithTag(TAG_HINT)
            .assertTextEquals("For the reminder to arrive on time, let Dredfit run without battery restrictions.")

        // Recorded, not stubbed: the phone's settings really open, as for the person.
        Intents.init()
        try {
            tapOnce(TAG_ROW)
            intended(allOf(hasAction(Settings.ACTION_APPLICATION_DETAILS_SETTINGS),
                           hasData(Uri.fromParts("package", app.packageName, null))))
        } finally {
            Intents.release()
        }
        awaitStage(Stage.STOPPED)
        val top = shell("dumpsys activity activities").lines().firstOrNull { it.contains("topResumedActivity") }.orEmpty()
        assertTrue("the phone's settings are on top: $top", top.contains("com.android.settings"))

        // What the person's Unrestricted does, then back to Dredfit.
        unrestricted(true)
        shell("input keyevent KEYCODE_BACK")
        awaitStage(Stage.RESUMED)
        compose.waitUntil(10_000) { !exists(TAG_HINT) }
        assertFalse(exists(TAG_ROW))
        assertTrue("the reminder itself stays as it was", exists(TAG_TIME))
    }

    @Test
    fun theHintWaitsForAPhoneThatHoldsTheReminderBackAndForTheReminder() {
        unrestricted(false)
        launch(Seed.Clean, fast = false)
        onStore { setReminderEnabled(true) }
        // The emulator as it is: a Google phone, whose Doze lets the alarm through.
        tap(AX.settings)
        await(TAG_TIME)
        assertFalse("no hint on a phone that is not listed", exists(TAG_HINT))
        tap(AX.settingsDone)

        BatteryHint.manufacturerForTests = "samsung"
        onStore { setReminderEnabled(false) }
        tap(AX.settings)
        await(TAG_TOGGLE)
        assertFalse("no hint while the reminder is off", exists(TAG_HINT))
        tap(TAG_TOGGLE)
        await(TAG_HINT)
        assertTrue(exists(TAG_ROW))
    }

    private companion object {
        const val TAG_HINT = "reminder-battery"
        const val TAG_ROW = "reminder-battery-settings"
    }
}
