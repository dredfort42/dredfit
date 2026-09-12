//
//  The onboarding screen and the App Store review prompt, moved out of
//  AppStoreTests.swift to keep it under the linter's file and type-body
//  ceilings. Grouped together because both are one-time gates keyed on
//  persisted flags and counters (a completed-onboarding bit, a workout
//  count, a cooldown window) rather than on the workout data itself. The
//  code moved unchanged.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Onboarding gate
extension AppStoreTests {

    func testOnboardingShowsOnceOnAFreshInstall() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.shouldShowOnboarding, "a fresh install must see it")

        store.completeOnboarding()
        XCTAssertFalse(store.shouldShowOnboarding, "not twice in the same run")
        XCTAssertFalse(AppStore(storageURL: tempURL).shouldShowOnboarding,
                       "and not after a relaunch either")
    }

    func testOnboardingIsSkippedForUsersWithHistory() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan)
        // an upgrading user has history but no flag — still no onboarding
        XCTAssertFalse(store.settings.onboardingCompleted)
        XCTAssertFalse(store.shouldShowOnboarding,
                       "history means the app has already been learned")
    }

    // MARK: - App Store review gate

    func testReviewGateAsksWhenEveryConditionHolds() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<AppStore.reviewMinWorkouts {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertEqual(store.engineState.counter, 5)
        XCTAssertTrue(store.shouldRequestReview(lastResult: .plan))
        XCTAssertTrue(store.shouldRequestReview(lastResult: .more))
    }

    func testReviewGateStaysSilentBelowTheWorkoutFloor() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<(AppStore.reviewMinWorkouts - 1) {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertEqual(store.engineState.counter, 4)
        XCTAssertFalse(store.shouldRequestReview(lastResult: .plan),
                       "four workouts is too early to ask")
    }

    func testReviewGateStaysSilentAfterAToughSession() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<AppStore.reviewMinWorkouts {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertFalse(store.shouldRequestReview(lastResult: .less))
        XCTAssertFalse(store.shouldRequestReview(lastResult: nil))
    }

    func testReviewGateRespectsTheSixtyDayCooldown() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<AppStore.reviewMinWorkouts {
            store.completeWorkout(session: store.nextSession, result: .plan)
        }
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        store.recordReviewRequest(at: now)

        let cal = Calendar.current
        let justUnder = cal.date(byAdding: .day, value: AppStore.reviewMinDaysBetween - 1, to: now)!
        let exactly = cal.date(byAdding: .day, value: AppStore.reviewMinDaysBetween, to: now)!
        XCTAssertFalse(store.shouldRequestReview(lastResult: .plan, now: justUnder),
                       "59 days is still inside the cooldown")
        XCTAssertTrue(store.shouldRequestReview(lastResult: .plan, now: exactly),
                      "60 days clears it")
    }

    /// The onboarding and review fields must round-trip through a save/reload
    /// like every other setting — the onboarding must not reappear after a relaunch.
    func testWaveFourSettingsSurviveReload() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertFalse(store.settings.onboardingCompleted)
        store.completeOnboarding()
        let stamp = Date(timeIntervalSince1970: 1_784_000_000)
        store.recordReviewRequest(at: stamp)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertTrue(reloaded.settings.onboardingCompleted,
                      "the onboarding flag must survive a relaunch")
        XCTAssertEqual(reloaded.settings.lastReviewRequestAt, stamp)
    }
}
