//
//  When the reminders are rebuilt and from what: the settings and the journal.
//  The window itself is ReminderScheduler's.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Local reminders

    var reminderScheduler: ReminderScheduler { ReminderScheduler(notifications: notifications) }

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
