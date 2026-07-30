//
//  WidgetShared.swift
//  Dredfit (app + DredfitWidgets)
//
//  The snapshot contract between the app and the widget extension.
//  The app writes; the widget only reads. No logic lives here.
//
//  This file also compiles into DredfitTests (for WidgetTimelineTests);
//  the Live Activity contract lives in ActivityShared.swift precisely so
//  it does not — a type twin in the test module is a confusing compile
//  error waiting for the first test that hands it to app code.
//

import Foundation

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
        /// "today" / "tomorrow" / "on Saturday" — the next training day as
        /// seen FROM THIS DAY, pre-localized by the app. Per day rather than
        /// once per snapshot: a relative word baked at write time reads wrong
        /// on every later entry the widget renders without the app's help.
        /// nil on planned days (they are the workout) and on past days
        /// (never rendered as entries).
        let nextLabel: String?
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
    /// The Monday of the week `week` tallies. The widget shows the tally only
    /// on entries inside this week — a next-week entry would otherwise label
    /// last week's numbers "This week".
    let weekStart: Date?
    let planSessionNumber: Int?
    let planMinutes: Int?
    let plan: [PlanRow]?
}
