//
//  Writes that touch nothing but the settings (more of them sit in
//  AppSettings.swift and AppStore+Health). Each goes through
//  `update`, which persists and refreshes the widget exactly as a direct write
//  followed by `persist()` does; every write that also moves the engine stays
//  in AppStore.swift, where the state is set.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Settings

    /// Refuses to turn the last training day into rest: at least one training
    /// day must remain, nextTrainingDate relies on it.
    func toggleRestDay(_ weekday: Int) {
        var days = settings.restWeekdays
        if days.contains(weekday) {
            days.remove(weekday)
        } else {
            days.insert(weekday)
            guard days.count < 7 else { return }
        }
        update { $0.settings.restWeekdays = days }
        rescheduleReminders()
    }

    func setSounds(_ on: Bool) {
        update { $0.settings.soundsEnabled = on }
    }

    func setReminderEnabled(_ on: Bool) {
        update { $0.settings.reminderEnabled = on }
        guard on else { return rescheduleReminders() }
        reminderAuthTask = Task { [weak self] in
            guard let self else { return }
            if await self.reminderScheduler.requestAuthorization() {
                self.rescheduleReminders()
            } else {
                // the system said no — reflect reality in the toggle
                self.update { $0.settings.reminderEnabled = false }
            }
        }
    }

    func setReminderTime(hour: Int, minute: Int) {
        update {
            $0.settings.reminderHour = hour
            $0.settings.reminderMinute = minute
        }
        rescheduleReminders()
    }

    // MARK: - Onboarding

    /// Deliberately not called when the pager merely appears: an app killed
    /// mid-pager shows it again. The only path here is the care card's
    /// explicit button (#101) — Skip jumps to that card instead of past it —
    /// so completing also records the acknowledgement.
    func completeOnboarding() {
        update {
            $0.settings.onboardingCompleted = true
            $0.settings.careAcknowledgedAt = .now
        }
    }

    // MARK: - Comeback after a break

    func declineComeback(now: Date? = nil) {
        closeComebackQuestion(now: now)
    }

    /// Internal rather than private only because it lives in this file;
    /// `acceptComeback` and `resetProgress` in AppStore.swift end with it.
    func closeComebackQuestion(now: Date? = nil) {
        update {
            $0.settings.comebackDecidedFor = $0.records.last?.date
            // How long the break was when it was answered, so a break that
            // keeps growing can ask once more (see shouldOfferComeback).
            $0.settings.comebackDecidedAtGap = gapDays(now: now)
        }
        // `update` already mirrors to the widget — accepting a comeback moves
        // the levels the plan is drawn from, and it reaches the snapshot on
        // that one write. A second refresh here is a second
        // reloadAllTimelines() for the same content.
    }

    // MARK: - App Store review

    func recordReviewRequest(at date: Date = .now) {
        update { $0.settings.lastReviewRequestAt = date }
    }

    // MARK: - The weak-link prompt (#135)

    /// Dismisses the prompt for this session without changing the plan.
    func dismissSuspectPrompt() {
        update { $0.settings.weakLinkPromptAnsweredFor = $0.records.last?.sessionNumber }
    }

    // MARK: - One-shot hints

    /// The one line on Today that says a plan row is a door: the variation one
    /// step below lives behind the technique sheet, and a control nobody knows
    /// about is a control nobody has.
    ///
    /// Gated on having been through the door, never on `records.isEmpty`: the
    /// person carried over from v2 has a full journal and is exactly the person
    /// the sentence is for — the carry-over keeps their positions, and any
    /// movement above its first variation has a step below it.
    var showsTechniqueHint: Bool { !settings.hasOpenedTechnique }

    /// Spent by the first technique sheet that keeps the hint's promise
    /// (`TechniqueSheet`'s `.task`): one opened from a plan row whose movement
    /// has a step below — or any technique sheet, when no movement of the plan
    /// has a rung below. Written only on the transition: the sheet is opened
    /// many times over a life of the app and this is a one-way flag.
    func markTechniqueOpened() {
        guard !settings.hasOpenedTechnique else { return }
        update { $0.settings.hasOpenedTechnique = true }
    }

    /// The one-shot card on Today explaining what an upgrade did.
    var showsMigrationNotice: Bool { settings.migrationNoticePending == true }

    func dismissMigrationNotice() {
        update { $0.settings.migrationNoticePending = false }
    }
}
