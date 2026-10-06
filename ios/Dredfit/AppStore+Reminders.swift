//
//  When the reminders are rebuilt and from what: the settings and the journal.
//  The window itself is ReminderScheduler's.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Local reminders

    var reminderScheduler: ReminderScheduler { ReminderScheduler(notifications: notifications) }

    /// Rebuilt from scratch on every settings change, activation and
    /// completion; a day that is a rest day, or already trained, gets none.
    func rescheduleReminders(now: Date = .now) {
        // A frozen launch knows neither the settings nor the journal: leave
        // what iOS holds rather than clearing a window the user expects.
        guard !journalFrozen else { return }
        reminderScheduler.reschedule(enabled: settings.reminderEnabled,
                                     hour: settings.reminderHour,
                                     minute: settings.reminderMinute,
                                     now: now,
                                     remindsOn: { !isRestDay($0) && !isDone(on: $0) })
    }
}
