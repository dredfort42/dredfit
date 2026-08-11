//
//  GetReady.swift
//  Dredfit
//
//  The transition before every guided position (issue #52). Five seconds is
//  the base, the same length as the side-switch pause of issue #35; a
//  position that has to be walked to or got down into carries a supplement
//  on top (issue #83). Neither number is a user setting.
//

import Foundation

enum GetReady {

    static let seconds = 5

    /// The supplement of issue #83, on top of `seconds`, for a position that
    /// changes the starting position (standing → the floor) or needs a prop
    /// (a wall). The flag travels with the move or position (`needsSetup`) —
    /// the cool-down set is dynamic, so an index would not survive
    /// composition. Five is not a taste: the engine reserves 8:00 for both
    /// blocks, and the worst-case composition — every supplemented position
    /// drawn, every per-side pause played — lands on 8:00 exactly. One
    /// second more and the reserve breaks, which is an engine change, not an
    /// app one.
    static let setupSupplementSec = 5

    /// The two lengths a transition can have. The side-switch pause and the
    /// way back in from a pause (issue #61) stay at the base length: nobody
    /// changes support in the middle of a position, and Resume is tapped by
    /// someone already back — its 3-2-1 is a count-in, not travel time.
    static func stageSeconds(needsSetup: Bool) -> Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        if CommandLine.arguments.contains("--uitest-long-transition") { return 600 }
        #endif
        return needsSetup ? seconds + setupSupplementSec : seconds
    }

    /// --uitest-fast collapses the transition, as it already collapses the
    /// rest countdown and every cool-down stage.
    ///
    /// --uitest-long-transition is the opposite need: "I'm ready" is on
    /// screen only while the transition runs, so at its real length a suite
    /// that taps it has five seconds for the whole of resolve-element-then-
    /// tap, and one accessibility snapshot on a saturated runner can cost
    /// seconds (I-5). The flag holds the transition open instead.
    ///
    /// It holds the transition of BOTH blocks and BOTH lengths — base and
    /// supplemented route through the same override, so issue #83's split
    /// changes nothing a test under this flag can see. A driver walking a
    /// whole workout must not combine it with completeWorkout: six cool-down
    /// transitions at this length outlast the driver's own deadline. Pass
    /// --uitest-fast instead; it is checked first and wins when both are
    /// given.
    ///
    /// It stretches the way back in from a pause too (issue #61) — that asks
    /// GetReady for the same length. A test that pauses a running position
    /// under this flag waits ten minutes to be counted back in.
    ///
    /// Production is untouched by both; DEBUG builds only.
    static var stageSeconds: Int { stageSeconds(needsSetup: false) }
}
