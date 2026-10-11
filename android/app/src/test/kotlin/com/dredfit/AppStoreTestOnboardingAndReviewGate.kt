//
//  Port of ios/DredfitTests/AppStoreTests+OnboardingAndReviewGate.swift. Both
//  are one-time gates keyed on persisted flags and counters (a completed-
//  onboarding bit, a workout count, a cooldown window), not on workout data.
//

package com.dredfit

import com.dredfit.core.FeedbackResult
import com.dredfit.store.REVIEW_MIN_DAYS_BETWEEN
import com.dredfit.store.REVIEW_MIN_WORKOUTS
import com.dredfit.store.completeOnboarding
import com.dredfit.store.nextSession
import com.dredfit.store.recordReviewRequest
import com.dredfit.store.shouldRequestReview
import com.dredfit.store.shouldShowOnboarding
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppStoreTestOnboardingAndReviewGate : AppStoreTestCase() {

    @Test
    fun onboardingShowsOnceOnAFreshInstall() {
        val store = makeStore()
        assertTrue(store.shouldShowOnboarding, "a fresh install must see it")

        store.completeOnboarding()
        assertFalse(store.shouldShowOnboarding, "not twice in the same run")
        assertFalse(makeStore().shouldShowOnboarding, "and not after a relaunch either")
    }

    @Test
    fun onboardingIsSkippedForUsersWithHistory() {
        val store = makeStore()
        store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan)
        // an upgrading user has history but no flag — still no onboarding
        assertFalse(store.settings.onboardingCompleted)
        assertFalse(store.shouldShowOnboarding, "history means the app has already been learned")
    }

    // MARK: - App Store review gate

    @Test
    fun reviewGateAsksWhenEveryConditionHolds() {
        val store = makeStore()
        repeat(REVIEW_MIN_WORKOUTS) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan) }
        assertEquals(5, store.engineState.counter)
        assertTrue(store.shouldRequestReview(lastResult = FeedbackResult.plan))
        assertTrue(store.shouldRequestReview(lastResult = FeedbackResult.more))
    }

    @Test
    fun reviewGateStaysSilentBelowTheWorkoutFloor() {
        val store = makeStore()
        repeat(REVIEW_MIN_WORKOUTS - 1) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan) }
        assertEquals(4, store.engineState.counter)
        assertFalse(store.shouldRequestReview(lastResult = FeedbackResult.plan), "four workouts is too early to ask")
    }

    @Test
    fun reviewGateStaysSilentAfterAToughSession() {
        val store = makeStore()
        repeat(REVIEW_MIN_WORKOUTS) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan) }
        assertFalse(store.shouldRequestReview(lastResult = FeedbackResult.less))
        assertFalse(store.shouldRequestReview(lastResult = null))
    }

    @Test
    fun reviewGateRespectsTheSixtyDayCooldown() {
        val store = makeStore()
        repeat(REVIEW_MIN_WORKOUTS) { store.completeWorkout(session = store.nextSession, result = FeedbackResult.plan) }
        val now = Instant.ofEpochSecond(1_784_000_000)
        store.recordReviewRequest(date = now)

        // Calendar days in the store's zone, as `Calendar.current` steps them.
        val start = now.atZone(ZoneId.systemDefault())
        val justUnder = start.plusDays(REVIEW_MIN_DAYS_BETWEEN - 1L).toInstant()
        val exactly = start.plusDays(REVIEW_MIN_DAYS_BETWEEN.toLong()).toInstant()
        assertFalse(store.shouldRequestReview(lastResult = FeedbackResult.plan, now = justUnder),
                    "59 days is still inside the cooldown")
        assertTrue(store.shouldRequestReview(lastResult = FeedbackResult.plan, now = exactly), "60 days clears it")
    }

    /** The onboarding and review fields round-trip through a save/reload like
     *  every other setting — the onboarding must not reappear after a relaunch. */
    @Test
    fun onboardingAndReviewSettingsSurviveReload() {
        val store = makeStore()
        assertFalse(store.settings.onboardingCompleted)
        store.completeOnboarding()
        val stamp = Instant.ofEpochSecond(1_784_000_000)
        store.recordReviewRequest(date = stamp)

        val reloaded = makeStore()
        assertTrue(reloaded.settings.onboardingCompleted, "the onboarding flag must survive a relaunch")
        assertEquals(stamp, reloaded.settings.lastReviewRequestAt)
    }
}
