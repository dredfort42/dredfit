//
//  When the app asks for POST_NOTIFICATIONS (Android 13+). iOS asks nothing —
//  a Live Activity needs no permission — so Android asks as little as it
//  can: ONCE, as the first workout starts, the moment the ongoing
//  notification first appears (owner decision, 09.10.2026). Whatever the
//  answer — allowed, refused, the dialog swiped away — it is never asked
//  again; a person who wants the notification later turns it on in the
//  system settings. Plain Kotlin, so the rule runs in a JVM test
//  (NotificationAskTest); RootScreen keeps the "asked" mark.
//

package com.dredfit.ongoing

object NotificationAsk {
    /** The first API level with a notification permission. */
    const val FIRST_SDK = 33

    /** `opensOnTheRating`: "Rate the workout" or "Finish now" from Today —
     *  a flow that draws no tile, so nothing to ask for, and the one ask is
     *  kept for a start that does. */
    fun shouldAsk(sdk: Int, granted: Boolean, askedBefore: Boolean, opensOnTheRating: Boolean): Boolean =
        sdk >= FIRST_SDK && !granted && !askedBefore && !opensOnTheRating
}
