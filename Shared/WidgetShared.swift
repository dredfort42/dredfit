//
//  WidgetShared.swift
//  Dredfit (app + DredfitWidgets)
//
//  v1.3: the contract between the app and the widget extension.
//  The app writes; the widget only reads. No logic lives here.
//

import Foundation
import ActivityKit

/// The App Group the app and the widget share.
nonisolated enum SharedStorage {
    static let appGroupID = "group.app.dredfit"
    static let snapshotFilename = "widget-snapshot.json"

    /// nil when the entitlement is missing — callers degrade silently.
    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }
}

/// A 7-day plan snapshot the app refreshes after every relevant change.
/// The widget never computes rest days or statuses itself.
nonisolated struct WidgetSnapshot: Codable {
    struct Day: Codable {
        enum Status: String, Codable { case workout, done, rest }
        let date: Date            // start of day
        let status: Status
        let sessionNumber: Int?   // present for today's planned workout
    }
    let days: [Day]
}

/// Live Activity contract: the workout is static, the phase is mutable.
/// All user-facing strings arrive pre-localized from the app.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: Phase
        var title: String         // current exercise (work) or the next one (rest)
        var detail: String        // "set 2 of 3" / "Next up"
        var restEndDate: Date?    // set during rest — the system ticks the timer
    }
    enum Phase: String, Codable, Hashable { case work, rest }
    var sessionNumber: Int
}
