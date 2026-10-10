//
//  When Settings shows the reminder's battery hint (reminders/BatteryHint.kt).
//  Android-only suite — iOS holds no reminder back. The device half (the
//  line on screen, the row's intent, the re-read on resume) is the connected
//  ReminderBatteryHintTest.
//

package com.dredfit

import com.dredfit.reminders.BatteryHint
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BatteryHintTest {

    @Test
    fun aSamsungThatStillRestrictsTheAppGetsTheHintWhileTheReminderIsOn() {
        assertTrue(BatteryHint.shows(reminderEnabled = true, ignoringBatteryOptimizations = false, manufacturer = "samsung"))
        // Build.MANUFACTURER is "samsung" on the A16; the case is not a promise.
        assertTrue(BatteryHint.shows(reminderEnabled = true, ignoringBatteryOptimizations = false, manufacturer = "Samsung"))
    }

    @Test
    fun noReminderNoHint() {
        assertFalse(BatteryHint.shows(reminderEnabled = false, ignoringBatteryOptimizations = false, manufacturer = "samsung"),
                    "nothing to hold back")
    }

    @Test
    fun unrestrictedTheHintGoes() {
        assertFalse(BatteryHint.shows(reminderEnabled = true, ignoringBatteryOptimizations = true, manufacturer = "samsung"),
                    "the person did what it asks")
    }

    @Test
    fun aPhoneWhoseDozeLetsTheAlarmThroughGetsNoHint() {
        assertFalse(BatteryHint.shows(reminderEnabled = true, ignoringBatteryOptimizations = false, manufacturer = "Google"),
                    "a Pixel: setAndAllowWhileIdle fires in Doze")
    }

    /** Unverified makes stay out until a phone of that make is checked: their
     *  own switches may not be what clears the hint (BatteryHint.kt). */
    @Test
    fun onlyTheVerifiedMakeIsListed() {
        for (make in listOf("Xiaomi", "HUAWEI", "HONOR", "OPPO", "realme", "OnePlus", "vivo", "motorola", "")) {
            assertFalse(BatteryHint.shows(reminderEnabled = true, ignoringBatteryOptimizations = false, manufacturer = make), make)
        }
    }
}
