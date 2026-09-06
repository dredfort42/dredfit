//
//  Lifted out of AppStore.swift, which sits against the linter's class-body
//  ceiling — a CI error, not a style opinion. This is the only place that adds
//  or removes the pending reminder requests; everything else just asks for a
//  rebuild.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Local reminders

    /// 28 daily slots stay well under the iOS cap of 64 pending
    /// notifications per app. The accepted price: reminders run dry if the
    /// app is not opened for four weeks (BACKLOG №8).
    static let reminderWindowDays = 28

    /// The older weekly series stays in the removal list so the first
    /// reschedule after an update clears it.
    private static let reminderIDs = (1...7).map { "reminder-wd-\($0)" }
        + (0..<reminderWindowDays).map { "reminder-day-\($0)" }

    // MARK: - The alert a running workout may need — NOT HERE YET

    // There is no in-workout alert, and the three members that used to stand
    // here (`workoutAlertID`, `clearWorkoutAlert`, `requestNotificationAuthorization`)
    // were removed because nothing in the app, the unit tests or the UI tests
    // ever called one of them (UX review 05.09.2026, findings 13 and 58;
    // removed in review 06.09.2026). The blocker is structural rather than a
    // missing call site: `NotificationScheduling` can only fire on a CALENDAR
    // date (`UNCalendarNotificationTrigger`), and an alert that says "your
    // rest is over" has to fire after an INTERVAL. So no request could ever be
    // filed under that id, the cancel half could only remove an id that never
    // existed, and its doc claimed in the present tense that the workout
    // cancels an alert no code schedules — a sentence the next wave would have
    // built on. Bring them back with the interval trigger, and with a test
    // that proves the cancel removes a request that is really pending.

    /// One one-shot per upcoming training date. Repeating weekly triggers
    /// cannot skip a single firing, and "trained this morning" needs exactly
    /// that. Rebuilt from scratch on every settings change, activation and
    /// completion.
    func rescheduleReminders(now: Date = .now) {
        // A frozen launch knows neither the settings nor the journal: leave
        // what iOS holds rather than clearing a window the user expects.
        guard !journalFrozen else { return }
        notifications.removePendingRequests(withIdentifiers: Self.reminderIDs)
        guard settings.reminderEnabled else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        for offset in 0..<Self.reminderWindowDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  !isRestDay(day), !isDone(on: day) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = settings.reminderHour
            comps.minute = settings.reminderMinute
            // A slot whose time already passed would never fire but would
            // sit in the pending list.
            guard let fire = cal.date(from: comps), fire > now else { continue }
            notifications.addReminder(
                id: "reminder-day-\(offset)",
                title: "Dredfit",
                body: String(localized: "Today's workout is ready"),
                fireDate: comps)
        }
    }
}
