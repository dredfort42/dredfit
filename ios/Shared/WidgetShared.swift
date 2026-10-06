//
//  Compiles into DredfitTests too. Keep the Live Activity contract out of
//  here (see ActivityShared.swift): a type twin in the test module is a
//  compile error the first time a test hands it to app code.
//

import Foundation

nonisolated enum SharedStorage {
    static let appGroupID = "group.app.dredfit"
    static let snapshotFilename = "widget-snapshot.json"

    /// nil when the App Group entitlement is missing — callers must degrade,
    /// not unwrap.
    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }
}

/// Starts on the Monday of the current week, not on today: a timeline entry
/// days out still has to find its own Monday–Sunday inside the snapshot.
nonisolated struct WidgetSnapshot: Codable {
    /// A sibling of `Day` rather than a member of it, so the nesting stays
    /// one level deep. The raw values are the wire format and do not move.
    enum DayStatus: String, Codable { case workout, done, rest, unmarked }

    struct Day: Codable {
        let date: Date
        let status: DayStatus
        let sessionNumber: Int?
        /// Per day, not once per snapshot: a relative word baked at write
        /// time reads wrong on every later entry the widget renders.
        let nextLabel: String?
    }

    struct PlanRow: Codable {
        let name: String
        let detail: String
    }

    struct Week: Codable {
        let workouts: Int
        /// Optional for the same reason as `totalSteps`: the key changed with
        /// the scale (the old `levelsDelta` was in the retired level unit).
        /// A snapshot from the old build leaves this absent, which reads as
        /// "no number yet" — right — while reusing the old key would present
        /// a level count as steps.
        let stepsDelta: Int?
    }

    let days: [Day]

    // Optional for backward compatibility: right after an update a snapshot
    // written by the previous build is still on disk, and a failed decode
    // blanks the widget until the app is next opened. The key changed with
    // the scale (the old `totalLevel` was in the retired level unit), so an
    // old snapshot carries no number here until the app writes the next
    // one — which is the correct answer rather than a gap.
    let totalSteps: Int?
    let week: Week?
    let weekStart: Date?
    let planSessionNumber: Int?
    let planMinutes: Int?

    // The low end of the same range the app prints on Today (PlanLength): the
    // plan with every movement on its sets floor. The full number alone
    // overstates what the person is agreeing to, on the very surface where
    // "will this fit today" is answered without opening the app.
    //
    // Absent means "written by a build without this field" — the widget then
    // prints the one number it has. Declared `var` with no initializer so the
    // memberwise initializer defaults it: a snapshot built without the floor
    // is still a snapshot.
    var planMinutesFloor: Int?

    let plan: [PlanRow]?
}
