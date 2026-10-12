//
//  When the reminder's alarm is exact and when Settings shows the line about
//  "Alarms & reminders" (reminders/ExactAlarm.kt). Android-only suite — an
//  iOS trigger is on the minute by itself. The device half (the line on
//  screen, the row's intent, the exact alarm in `dumpsys alarm`) is the
//  connected ReminderExactAlarmTest.
//

package com.dredfit

import com.dredfit.reminders.ExactAlarm
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ExactAlarmTest {

    @Test
    fun beforeAndroid12AnAlarmIsExactWithoutAsking() {
        assertTrue(ExactAlarm.allowed(sdk = 29, canScheduleExact = false))
        assertTrue(ExactAlarm.allowed(sdk = 30, canScheduleExact = false))
        assertFalse(ExactAlarm.hintShows(reminderEnabled = true, sdk = 30, canScheduleExact = false),
                    "nothing to turn on")
    }

    @Test
    fun fromAndroid12ItTakesAlarmsAndReminders() {
        for (sdk in listOf(31, 34, 36)) {
            assertTrue(ExactAlarm.allowed(sdk, canScheduleExact = true), "$sdk")
            assertFalse(ExactAlarm.allowed(sdk, canScheduleExact = false), "$sdk")
        }
    }

    @Test
    fun theHintShowsWhileTheReminderIsOnAndItsAlarmWouldBeInexact() {
        assertTrue(ExactAlarm.hintShows(reminderEnabled = true, sdk = 36, canScheduleExact = false))
        assertFalse(ExactAlarm.hintShows(reminderEnabled = true, sdk = 36, canScheduleExact = true),
                    "the person did what it asks")
        assertFalse(ExactAlarm.hintShows(reminderEnabled = false, sdk = 36, canScheduleExact = false),
                    "no reminder, nothing late")
    }
}
