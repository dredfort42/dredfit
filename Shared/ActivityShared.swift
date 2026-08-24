//
//  Kept out of WidgetShared.swift: that file also compiles into the unit
//  test bundle, and this type is handed to app APIs from tests — it must
//  exist exactly once, as the app's own type.
//

import Foundation
import ActivityKit

/// All user-facing strings arrive pre-localized from the app.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: Phase
        var title: String
        var detail: String
        var restEndDate: Date?
    }
    enum Phase: String, Codable, Hashable { case work, rest }
    var sessionNumber: Int
}
