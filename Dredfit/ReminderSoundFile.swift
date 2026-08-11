//
//  ReminderSoundFile.swift
//  Dredfit
//
//  The reminder's branded sound (#84, stage C). Notification sounds must be
//  real files in Library/Sounds — the one place the "generated, not shipped"
//  rule meets the filesystem. The WAV is still generated (SignalTone),
//  written once, and never rewritten: iOS caches notification sounds by
//  NAME, so a future timbre change ships as a new name (_v2), not new bytes
//  under the old one.
//
//  Deliberately independent of `settings.soundsEnabled`: notifications are
//  the system's channel and follow the system's notification-sound setting;
//  the app's toggle governs the in-workout tones only.
//

import Foundation
import UserNotifications

enum ReminderSoundFile {

    static let name = "dredfit_reminder_v1.wav"

    /// Ensures `Library/Sounds/dredfit_reminder_v1.wav` exists and returns
    /// the sound to attach. Idempotent: an existing file is left untouched.
    /// Any failure to provision falls back to `.default` — a reminder with
    /// the stock sound beats a silent one.
    static func notificationSound(
        library: URL = FileManager.default.urls(for: .libraryDirectory,
                                                in: .userDomainMask)[0]
    ) -> UNNotificationSound {
        let directory = library.appendingPathComponent("Sounds", isDirectory: true)
        let file = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) {
            do {
                try FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: true)
                try SignalTone.reminder.write(to: file, options: .atomic)
            } catch {
                return .default
            }
        }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }
}
