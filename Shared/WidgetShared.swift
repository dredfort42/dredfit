//
//  WidgetShared.swift
//  Dredfit (app + DredfitWidgets)
//
//  The contract between the app and the widget extension.
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

/// A two-week status snapshot the app refreshes after every relevant change.
/// The widget never computes rest days, history or statuses itself.
///
/// It starts on the Monday of the current week rather than on today, so the
/// widget can draw the calendar week around *any* day it renders — a timeline
/// entry six days out still finds its own Monday–Sunday inside the snapshot.
nonisolated struct WidgetSnapshot: Codable {
    struct Day: Codable {
        /// `unmarked` is a past training day that was not done. The Calendar
        /// leaves those deliberately unmarked rather than accusing, and the
        /// widget mirrors that — hence its own case instead of `workout`,
        /// which would read as "still planned".
        enum Status: String, Codable { case workout, done, rest, unmarked }
        let date: Date            // start of day
        let status: Status
        let sessionNumber: Int?   // present for today's planned workout
    }

    /// One row of the next session's plan, pre-localized by the app: the
    /// widget must not reach into the engine or the string catalogs itself.
    struct PlanRow: Codable {
        let name: String
        let detail: String        // "3×12", "3×40 sec"
    }

    /// The calendar week's tally, as the Progress screen states it.
    struct Week: Codable {
        let workouts: Int
        let levelsDelta: Int      // negative on a deload week — that is honest
    }

    let days: [Day]

    // Everything below arrived with the medium, large and lock-screen
    // families. Right after an update a snapshot written by the previous
    // build is still on disk, so these must decode as nil instead of failing
    // the whole file and blanking the widget until the app is next opened.
    let totalLevel: Int?
    let week: Week?
    let nextDateLabel: String?    // "today" / "tomorrow" / "on Saturday"
    let planSessionNumber: Int?
    let planMinutes: Int?
    let plan: [PlanRow]?
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
