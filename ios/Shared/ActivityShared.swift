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
        /// The end of whatever the phase is counting down — a rest, or a hold.
        /// The name is the rest it was born for; the field is the tile's one
        /// date, because the tile draws one countdown.
        var restEndDate: Date?
    }
    /// `hold` is work that owns an end date. A separate case rather than a
    /// `work` carrying a date, because both the tile's countdown and
    /// `staleDate` key off it: the hold — the one phase whose copy asks you to
    /// put the phone down — was the phase showing a static dot
    /// (UX review 05.09.2026).
    enum Phase: String, Codable, Hashable { case work, rest, hold }
    var sessionNumber: Int
}
