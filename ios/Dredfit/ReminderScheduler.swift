//
//  The local reminders: one one-shot per upcoming training day, rebuilt whole
//  on every change. The only place that adds or removes pending reminder
//  requests; the store only decides when to rebuild and from what.
//

import Foundation

struct ReminderScheduler {
    let notifications: NotificationScheduling

    /// 28 daily slots stay well under the iOS cap of 64 pending
    /// notifications per app. The accepted price: reminders run dry if the
    /// app is not opened for four weeks (BACKLOG №8).
    static let windowDays = 28

    /// The older weekly series stays in the removal list so the first
    /// reschedule after an update clears it.
    private static let ids = (1...7).map { "reminder-wd-\($0)" }
        + (0..<windowDays).map { "reminder-day-\($0)" }

    /// Replaces every pending reminder with one per day of the window that
    /// `remindsOn` accepts, at `hour:minute`. One-shots rather than a weekly
    /// repeat: a repeating trigger cannot skip a single firing, and "trained
    /// this morning" needs exactly that.
    func reschedule(enabled: Bool, hour: Int, minute: Int, now: Date,
                    remindsOn: (Date) -> Bool) {
        notifications.removePendingRequests(withIdentifiers: Self.ids)
        guard enabled else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        for offset in 0..<Self.windowDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  remindsOn(day) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
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

    /// True only when granted.
    func requestAuthorization() async -> Bool {
        await notifications.requestAuthorization()
    }
}
