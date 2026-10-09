//
//  What the workout's tile shows outside the app — the rules of
//  ios/DredfitWidgets/RestLiveActivity.swift without its drawing. On iOS the
//  Live Activity's lock-screen view; here the ongoing notification
//  (ongoing/OngoingNotification.kt), which draws exactly this.
//

package com.dredfit.workout

import java.time.Instant

/**
 * The tile's three parts, in the iOS order: `detail` the small line ("Next
 * up", "set 2 of 3"), `title` the bold one (the exercise, or what the rest
 * leads into), and the countdown — or no countdown, where iOS draws its
 * static dot.
 */
data class OngoingContent(val title: Words, val detail: Words?, val countdownTo: Instant?) {
    companion object {
        /**
         * Any phase but `work`, not just the rest: a hold sends its own end
         * date through the same field, and the hold is the phase whose copy
         * asks the athlete to put the phone down. A date already past draws
         * no countdown — iOS checks `end > .now` for the same reason: a
         * system chronometer counting down runs on below zero.
         */
        fun of(state: ActivityState, now: Instant): OngoingContent {
            val end = state.restEndDate?.takeIf { state.phase != ActivityState.Phase.work && it > now }
            return OngoingContent(state.title, state.detail, end)
        }
    }
}
