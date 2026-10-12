//
//  When the reminder's alarm is exact, and when Settings says how to make it
//  so (owner decision, 12.10.2026). Android-only: an iOS calendar trigger is
//  on the minute by itself.
//
//  WHY. The inexact alarm the reminder used alone came an hour late: on the
//  owner's Galaxy A16 (Android 16) a 14:00 reminder posted at 15:00:00.4 —
//  the end of its `window=+1h` in `dumpsys alarm` — with the app unfrozen and
//  exempt from battery optimisation. So the reminder is exact where the
//  phone allows it: Android 10–11 always; Android 12+ while "Alarms &
//  reminders" (SCHEDULE_EXACT_ALARM) is on for the app, OR while the app is
//  exempt from battery optimisation — `canScheduleExactAlarms` counts the
//  power-save exemption list too (AlarmManager's javadoc, API 37). Android
//  12–13 grant the permission at install; from 14 a fresh install starts
//  without it, and the person can take it back on any version — then the
//  alarm falls back to the inexact one, and the hint says how to get the
//  minute back. On a Samsung, the battery hint's Unrestricted clears this
//  hint as well.
//
//  Plain Kotlin, so the rule runs in a JVM test (ExactAlarmTest). The phone
//  is read by SystemNotificationScheduler and Settings
//  (ui/settings/SettingsSections.kt), which re-reads it on every resume.
//

package com.dredfit.reminders

object ExactAlarm {

    /** Android 12 (S): the first that asks for the permission. */
    const val FIRST_ASKING_SDK = 31

    /** `canScheduleExact`: `AlarmManager.canScheduleExactAlarms()` — the
     *  permission or the battery exemption — read only where it exists
     *  (API 31+). */
    fun allowed(sdk: Int, canScheduleExact: Boolean): Boolean = sdk < FIRST_ASKING_SDK || canScheduleExact

    /** The line under the reminder: only while the reminder is on and its
     *  alarm would be the inexact one. */
    fun hintShows(reminderEnabled: Boolean, sdk: Int, canScheduleExact: Boolean): Boolean =
        reminderEnabled && !allowed(sdk, canScheduleExact)
}
