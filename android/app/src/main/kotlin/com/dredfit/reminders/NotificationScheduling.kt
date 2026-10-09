//
//  The reminder seam. Port of ios/Dredfit/NotificationScheduling.swift: the
//  store and `ReminderScheduler` talk to this interface, unit tests hand
//  them a spy, and the app hands them `SystemNotificationScheduler`
//  (SystemNotificationScheduler.kt) — AlarmManager and the notification
//  permission, the Android halves of UNUserNotificationCenter.
//

package com.dredfit.reminders

import com.dredfit.workout.Words
import java.time.Instant

interface NotificationScheduling {
    /** True only when granted. May answer later — a system dialog — and
     *  always answers on the main thread. */
    fun requestAuthorization(answer: (Boolean) -> Unit)

    fun removePendingRequests(ids: List<String>)

    /** `body` is resolved when the reminder fires, in the app's language of
     *  that moment. */
    fun addReminder(id: String, title: String, body: Words, fireAt: Instant)

    companion object {
        /** Reminders that go nowhere, for a store whose test is not about
         *  them — iOS's `QuietNotifications` (AppStoreTestCase.swift), which
         *  refuses, as an unasked device does. */
        val none: NotificationScheduling = object : NotificationScheduling {
            override fun requestAuthorization(answer: (Boolean) -> Unit) = answer(false)
            override fun removePendingRequests(ids: List<String>) = Unit
            override fun addReminder(id: String, title: String, body: Words, fireAt: Instant) = Unit
        }
    }
}
