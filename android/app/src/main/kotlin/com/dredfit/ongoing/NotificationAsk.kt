//
//  When the app asks for POST_NOTIFICATIONS (Android 13+). Two doors, one
//  permission:
//
//  - THE WORKOUT. iOS asks nothing — a Live Activity needs no permission —
//    so Android asks as little as it can: ONCE, as the first workout starts,
//    the moment the ongoing notification first appears (owner decision,
//    09.10.2026). Whatever the answer it is never asked again from there; a
//    person who wants the notification later turns it on in the system
//    settings.
//  - THE REMINDER. iOS asks on the switch, because a reminder IS a
//    notification: turning it on is the request. So does Android, whatever
//    the workout's door already asked — the system itself decides whether a
//    dialog still appears (after two refusals it answers "no" at once), and
//    a refusal of either kind ends in the denied note with its way to the
//    app's notification settings. The reminder's ask writes the same mark:
//    the app has asked, and the workout's door does not ask a second time.
//
//  Plain Kotlin, so the rules run in a JVM test (NotificationAskTest).
//

package com.dredfit.ongoing

import java.io.File

object NotificationAsk {
    /** The first API level with a notification permission. */
    const val FIRST_SDK = 33

    /** The "asked" mark, a file in `noBackupFilesDir`: a permission belongs
     *  to the device, and a mark restored onto a new phone would leave it
     *  never asked there. A mark that cannot be written only means asking
     *  again. */
    fun mark(noBackupFilesDir: File): File = File(noBackupFilesDir, "notifications-asked")

    /** `opensOnTheRating`: "Rate the workout" or "Finish now" from Today —
     *  a flow that draws no tile, so nothing to ask for, and the one ask is
     *  kept for a start that does. */
    fun shouldAsk(sdk: Int, granted: Boolean, askedBefore: Boolean, opensOnTheRating: Boolean): Boolean =
        sdk >= FIRST_SDK && !granted && !askedBefore && !opensOnTheRating

    /** What turning the reminder on does with the permission. */
    enum class ReminderStep {
        /** Notifications reach the reminder's channel: schedule. */
        allowed,
        /** Show the system's question first. */
        ask,
        /** Nothing in the app can change it: the denied note. */
        refused,
    }

    /**
     * `allowed` — notifications are on for the app AND the reminder's
     * channel is not blocked (a person can switch off that one channel and
     * keep the workout's). The question can only be asked on Android 13+,
     * for a permission not yet granted, with a screen to show it on; a
     * permission granted while the app's notifications are off (below 13,
     * or a channel blocked) has no dialog that could change it.
     */
    fun reminderStep(sdk: Int, allowed: Boolean, permissionGranted: Boolean, canAsk: Boolean): ReminderStep = when {
        allowed -> ReminderStep.allowed
        sdk >= FIRST_SDK && !permissionGranted && canAsk -> ReminderStep.ask
        else -> ReminderStep.refused
    }
}
