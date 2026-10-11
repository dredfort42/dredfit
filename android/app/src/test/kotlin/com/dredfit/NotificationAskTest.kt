//
//  When POST_NOTIFICATIONS is asked (ongoing/NotificationAsk.kt): once, at
//  the first start that draws a tile, on Android 13+. Android-only suite —
//  iOS asks nothing for a Live Activity. And the reminder's door: asked on its
//  switch, as iOS asks, sharing the one mark.
//

package com.dredfit

import com.dredfit.ongoing.NotificationAsk
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotificationAskTest {

    @Test
    fun theFirstStartOnAndroid13AsksAndNothingElseDoes() {
        assertTrue(NotificationAsk.shouldAsk(sdk = 33, granted = false, askedBefore = false, opensOnTheRating = false))
        assertFalse(NotificationAsk.shouldAsk(sdk = 32, granted = false, askedBefore = false, opensOnTheRating = false),
                    "below 13 there is no permission to ask for")
        assertFalse(NotificationAsk.shouldAsk(sdk = 37, granted = true, askedBefore = false, opensOnTheRating = false),
                    "granted needs no asking")
    }

    @Test
    fun askedOnceIsNeverAskedAgain() {
        assertFalse(NotificationAsk.shouldAsk(sdk = 37, granted = false, askedBefore = true, opensOnTheRating = false),
                    "a refusal is remembered — the owner's once")
    }

    @Test
    fun aFlowThatOpensOnTheRatingDoesNotSpendTheAsk() {
        assertFalse(NotificationAsk.shouldAsk(sdk = 37, granted = false, askedBefore = false, opensOnTheRating = true),
                    "the rating draws no tile: the dialog would cover it for nothing")
    }

    // MARK: - The reminder's door (iOS asks on its switch)

    @Test
    fun theReminderSchedulesWhenNotificationsReachItsChannel() {
        assertEquals(NotificationAsk.ReminderStep.allowed,
                     NotificationAsk.reminderStep(sdk = 37, allowed = true, permissionGranted = true, canAsk = true))
        assertEquals(NotificationAsk.ReminderStep.allowed,
                     NotificationAsk.reminderStep(sdk = 29, allowed = true, permissionGranted = true, canAsk = false),
                     "below 13 nothing is asked, and nothing needs to be")
    }

    @Test
    fun theReminderAsksOnlyWhereADialogCanChangeTheAnswer() {
        assertEquals(NotificationAsk.ReminderStep.ask,
                     NotificationAsk.reminderStep(sdk = 33, allowed = false, permissionGranted = false, canAsk = true),
                     "the switch is the request, whatever the workout's door asked before")
        assertEquals(NotificationAsk.ReminderStep.refused,
                     NotificationAsk.reminderStep(sdk = 33, allowed = false, permissionGranted = false, canAsk = false),
                     "no screen to ask on: refused, never waiting forever")
        assertEquals(NotificationAsk.ReminderStep.refused,
                     NotificationAsk.reminderStep(sdk = 37, allowed = false, permissionGranted = true, canAsk = true),
                     "granted, yet the channel or the app's notifications are off: no dialog reaches that")
        assertEquals(NotificationAsk.ReminderStep.refused,
                     NotificationAsk.reminderStep(sdk = 32, allowed = false, permissionGranted = true, canAsk = true),
                     "below 13 only the settings can turn notifications back on")
    }

    @Test
    fun bothDoorsShareOneMark() {
        val dir = File("/data/user/0/com.dredfit.dredfit/no_backup")
        assertEquals(File(dir, "notifications-asked"), NotificationAsk.mark(dir),
                     "the name the workout's door wrote before the reminder shared it")
    }
}
