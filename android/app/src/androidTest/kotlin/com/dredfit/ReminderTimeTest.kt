//
//  The reminder's time row as the phone writes it (`ReminderTime`,
//  ui/settings/SettingsSections.kt). On the device, because the pattern is
//  ICU's: Android's ICU gives zh-TW's 12-hour time a day period ("B"), which
//  java.time on Android cannot format — a formatter built from that pattern
//  threw, and with the reminder on Settings could not open again (skeptic
//  finding, 09.10.2026).
//

package com.dredfit

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.dredfit.ui.settings.ReminderTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

@RunWith(AndroidJUnit4::class)
class ReminderTimeTest {

    @Test
    fun everyLocaleTheAppCanMeetWritesTheTime() {
        val locales = Locale.getAvailableLocales().toList()
        for (locale in locales) {
            for (is24 in listOf(true, false)) {
                val text = ReminderTime.text(hour = 21, minute = 5, is24Hour = is24, locale = locale)
                assertTrue("$locale ${if (is24) 24 else 12}h: \"$text\"", text.isNotBlank())
            }
        }
    }

    @Test
    fun theTimeIsTheSettingsTimeInBothForms() {
        assertEquals("21:05", ReminderTime.text(21, 5, is24Hour = true, locale = Locale.UK))
        val twelve = ReminderTime.text(21, 5, is24Hour = false, locale = Locale.US)
        assertTrue(twelve, twelve.startsWith("9:05") && twelve.contains("PM"))
        val taiwan = ReminderTime.text(9, 0, is24Hour = false, locale = Locale.TAIWAN)
        assertTrue(taiwan, taiwan.contains("9:00"))
    }
}
