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
