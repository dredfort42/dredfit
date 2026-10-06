//
//  Whether to ask: the read-only gates of onboarding, the comeback card
//  and the review request. What an answer does is in AppStore+SettingsWrites
//  and AppStore.swift, where the state is set through `update`.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Onboarding

    /// Genuinely new installs only.
    var shouldShowOnboarding: Bool {
        // A frozen launch knows nothing about the user — never mistake it
        // for a fresh install.
        !journalFrozen && records.isEmpty && engineState.counter == 0
            && !settings.onboardingCompleted
    }

    // MARK: - Comeback after a break

    /// Asked once per break: the answer is stamped against the last workout's
    /// date, so it goes stale by itself instead of needing to be cleared. A
    /// break inside the trainee's own rhythm is not a break at all (#134) — no
    /// card, and so no comeback either.
    func shouldOfferComeback(now: Date? = nil) -> Bool {
        guard let last = records.last, let gap = gapDays(now: now) else { return false }
        guard gap >= EngineConfig.comebackMinGapDays, !isRhythmBreak(gap) else { return false }
        guard let decided = settings.comebackDecidedFor,
              Calendar.current.isDate(decided, inSameDayAs: last.date) else { return true }
        // Once per break — unless the break has since grown a door the answer
        // could not have been about. "Start from scratch" appears only from
        // `comebackFreshStartDays`, so without this someone who declined on
        // day 20 of a break that ran to three months would never see the one
        // offer meant for exactly them. At most ONE extra ask — closing the
        // question again stamps the gap it was answered at.
        guard let answeredAt = settings.comebackDecidedAtGap else { return false }
        return answeredAt < Self.comebackFreshStartDays && gap >= Self.comebackFreshStartDays
    }

    /// Drives both the once-per-break guard and the comeback's
    /// `alreadyDecayed`: the two drops must not stack. Internal so the
    /// read-only preview in AppStore+Comeback sees the same weakening.
    var silentDecayAppliedForCurrentBreak: Bool {
        guard let applied = settings.silentDecayAppliedFor,
              let last = records.last?.date else { return false }
        return Calendar.current.isDate(applied, inSameDayAs: last)
    }

    func offersFreshStart(now: Date? = nil) -> Bool {
        (gapDays(now: now) ?? 0) >= Self.comebackFreshStartDays
    }

    /// From 90 days — a quarter away is long enough that "as it was" can be
    /// blind and "from scratch" must be reachable.
    static let comebackFreshStartDays = 90

    // MARK: - App Store review

    /// Pure and injectable so the gate is unit-testable without StoreKit.
    /// A `.less` rating disqualifies the session outright.
    func shouldRequestReview(lastResult: FeedbackResult?, now: Date = .now) -> Bool {
        guard engineState.counter >= Self.reviewMinWorkouts else { return false }
        guard let lastResult, lastResult != .less else { return false }
        guard let previous = settings.lastReviewRequestAt else { return true }
        let days = Calendar.current.dateComponents([.day], from: previous, to: now).day ?? 0
        return days >= Self.reviewMinDaysBetween
    }

    static let reviewMinWorkouts = 5
    static let reviewMinDaysBetween = 60
}
