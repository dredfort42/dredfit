//
//  The reminder seam, lifted out of AppStore.swift: it is UserNotifications
//  and nothing else, and the store's own file has a lint ceiling to stay
//  under. Unit tests substitute a spy for the protocol.
//

import Foundation
import UserNotifications

/// Injectable seam: unit tests substitute a spy.
protocol NotificationScheduling {
    /// True only when granted.
    func requestAuthorization() async -> Bool
    func removePendingRequests(withIdentifiers ids: [String])
    func addReminder(id: String, title: String, body: String,
                     fireDate: DateComponents)
}

struct UserNotificationScheduler: NotificationScheduling {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func removePendingRequests(withIdentifiers ids: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }

    func addReminder(id: String, title: String, body: String,
                     fireDate: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The branded reminder tone (#84) — provisioned on demand, falls
        // back to .default if the file cannot be written.
        content.sound = ReminderSoundFile.notificationSound()
        let trigger = UNCalendarNotificationTrigger(dateMatching: fireDate, repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
