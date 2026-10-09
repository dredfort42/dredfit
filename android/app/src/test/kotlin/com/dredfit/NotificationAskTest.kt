//
//  When POST_NOTIFICATIONS is asked (ongoing/NotificationAsk.kt): once, at
//  the first start that draws a tile, on Android 13+. Android-only suite —
//  iOS asks nothing for a Live Activity.
//

package com.dredfit

import com.dredfit.ongoing.NotificationAsk
import kotlin.test.Test
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
}
