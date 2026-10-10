//
//  The reminder's battery hint (owner decision, 10.10.2026). Android-only:
//  iOS keeps no app's notification from its time.
//
//  WHY. Samsung's app freezer (Freecess) freezes Dredfit about two minutes
//  after it leaves the screen, and the system then holds the
//  reminder's alarm back until the screen is next woken: on a Galaxy A16
//  (Android 16) a 19:25 reminder arrived at 19:35, the moment the screen went
//  on (logcat "Deferring alarm … due to freecess"). With Dredfit exempt from
//  battery optimisation ("Unrestricted" in the app's battery settings, which
//  put it on `dumpsys deviceidle whitelist`) there was no freeze, and a 19:48
//  reminder fired at 19:53 with the screen off. Stock Android's Doze lets a
//  `setAndAllowWhileIdle` alarm through, so the hint is not shown there.
//
//  WHICH PHONES. Samsung only — the one make checked. dontkillmyapp.com
//  ranks Huawei, Xiaomi and OnePlus above Samsung, and OPPO, vivo and realme
//  further down, but it was NOT checked on any of them whether their own
//  switches are what `isIgnoringBatteryOptimizations` reads. Xiaomi's page
//  there names Autostart, the app's battery saver and a lock in Recents —
//  none of them the standard exemption. A hint whose condition the phone's
//  own switch does not clear would stay after the person did what it asks,
//  so each make waits for a phone of that make.
//
//  Plain Kotlin, so the rule runs in a JVM test (BatteryHintTest). Settings
//  reads the phone and re-reads the exemption on every resume
//  (ui/settings/SettingsSections.kt).
//

package com.dredfit.reminders

import java.util.Locale

object BatteryHint {

    /** `Build.MANUFACTURER`, lowercased, of the phones that hold a reminder
     *  back until the screen is woken. */
    val freezingMakers: Set<String> = setOf("samsung")

    /** `ignoringBatteryOptimizations`: `PowerManager.isIgnoringBatteryOptimizations`
     *  for the app — true once the person set it to Unrestricted. */
    fun shows(reminderEnabled: Boolean, ignoringBatteryOptimizations: Boolean, manufacturer: String): Boolean =
        reminderEnabled && !ignoringBatteryOptimizations && manufacturer.lowercase(Locale.ROOT) in freezingMakers

    /** The UI suite's stand-in for `Build.MANUFACTURER`, so the emulator can
     *  play a Samsung. Nothing in the app writes it — only androidTest does
     *  (ReminderBatteryHintTest) — so a release build reads the phone's. */
    @Volatile
    var manufacturerForTests: String? = null
}
