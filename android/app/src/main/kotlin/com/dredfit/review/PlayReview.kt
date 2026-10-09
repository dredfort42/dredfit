//
//  The Play half of the review ask — iOS's `@Environment(\.requestReview)`.
//  WHEN to ask is decided in plain Kotlin (`askForReviewIfEarned`,
//  WorkoutFlowView.kt) against the `ReviewPrompt` interface, so the rule runs
//  in a JVM test and only this file knows about Play.
//
//  Play In-App Review is the one third-party SDK the app carries (owner
//  decision 09.10.2026, android/README.md). The card is Play's to show or
//  not — a quota it never discloses, as StoreKit's — and neither call tells
//  the app whether it appeared, so nothing here reports back.
//

package com.dredfit.review

import android.app.Activity
import com.dredfit.ui.workout.ReviewPrompt
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.ReviewManagerFactory

class PlayReviewPrompt(
    private val activity: Activity,
    private val manager: ReviewManager = ReviewManagerFactory.create(activity),
) : ReviewPrompt {

    override fun request() {
        manager.requestReviewFlow().addOnCompleteListener { asked ->
            // Refused when Play cannot serve one — a phone without the Play
            // Store, among others. There is nothing to tell the athlete (the
            // card was never promised), and `asked.result` would throw.
            if (!asked.isSuccessful) return@addOnCompleteListener
            // The answer comes back asynchronously; the activity it would
            // launch over may be gone by then (closed, recreated).
            if (activity.isFinishing || activity.isDestroyed) return@addOnCompleteListener
            manager.launchReviewFlow(activity, asked.result)
        }
    }
}
