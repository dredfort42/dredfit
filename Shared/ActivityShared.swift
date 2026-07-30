//
//  ActivityShared.swift
//  Dredfit (app + DredfitWidgets)
//
//  The Live Activity contract between the app and the widget extension.
//  Split from WidgetShared.swift: that file also compiles into the unit
//  test bundle, and this type is handed to app APIs from tests — it must
//  exist exactly once, as the app's own type.
//

import Foundation
import ActivityKit

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
