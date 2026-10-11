//
//  Whether to ask: the read-only gates of onboarding, the comeback card and
//  the review request. Port of ios/Dredfit/AppStore+Offers.swift.
//

package com.dredfit.store

import com.dredfit.core.EngineConfig
import com.dredfit.core.FeedbackResult
import java.time.Instant
import java.time.temporal.ChronoUnit

/** Genuinely new installs only — a frozen launch knows nothing about the
 *  person and is never mistaken for one. */
val AppStore.shouldShowOnboarding: Boolean
    get() = !journalFrozen && records.isEmpty() && engineState.counter == 0 && !settings.onboardingCompleted

/**
 * Asked once per break: the answer is stamped against the last workout's
 * date, so it goes stale by itself. A break inside the trainee's own rhythm is
 * no break at all (#134). At most ONE extra ask, when the break has since
 * grown the "start from scratch" door the first answer could not have been about.
 */
fun AppStore.shouldOfferComeback(now: Instant = clock.instant()): Boolean {
    val last = records.lastOrNull() ?: return false
    val gap = gapDays(now) ?: return false
    if (gap < EngineConfig.comebackMinGapDays || isRhythmBreak(gap)) return false
    val decided = settings.comebackDecidedFor
    if (decided == null || !sameDay(decided, last.date)) return true
    val answeredAt = settings.comebackDecidedAtGap ?: return false
    return answeredAt < COMEBACK_FRESH_START_DAYS && gap >= COMEBACK_FRESH_START_DAYS
}

/** Drives both the once-per-break guard and the comeback's `alreadyDecayed`:
 *  the two drops must not stack. */
val AppStore.silentDecayAppliedForCurrentBreak: Boolean
    get() {
        val applied = settings.silentDecayAppliedFor ?: return false
        val last = records.lastOrNull()?.date ?: return false
        return sameDay(applied, last)
    }

fun AppStore.offersFreshStart(now: Instant = clock.instant()): Boolean =
    (gapDays(now) ?: 0) >= COMEBACK_FRESH_START_DAYS

/** From 90 days "as it was" can be blind and "from scratch" must be reachable. */
const val COMEBACK_FRESH_START_DAYS = 90

/** A `.less` rating disqualifies the session outright. */
fun AppStore.shouldRequestReview(lastResult: FeedbackResult?, now: Instant = clock.instant()): Boolean {
    if (engineState.counter < REVIEW_MIN_WORKOUTS) return false
    if (lastResult == null || lastResult == FeedbackResult.less) return false
    val previous = settings.lastReviewRequestAt ?: return true
    // Calendar days of wall-clock time, as `dateComponents([.day])` counts them.
    val days = ChronoUnit.DAYS.between(previous.atZone(zone), now.atZone(zone))
    return days >= REVIEW_MIN_DAYS_BETWEEN
}

const val REVIEW_MIN_WORKOUTS = 5
const val REVIEW_MIN_DAYS_BETWEEN = 60
