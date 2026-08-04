//
//  GetReady.swift
//  Dredfit
//
//  The transition before every guided position (issue #52). Five seconds,
//  the same length as the side-switch pause of issue #35. Neither is a user
//  setting.
//

import Foundation

enum GetReady {

    static let seconds = 5

    /// --uitest-fast collapses the transition, as it already collapses the
    /// rest countdown and every cool-down stage.
    ///
    /// --uitest-long-transition is the opposite need: "I'm ready" is on
    /// screen only while the transition runs, so at its real length a suite
    /// that taps it has five seconds for the whole of resolve-element-then-
    /// tap, and one accessibility snapshot on a saturated runner can cost
    /// seconds (I-5). The flag holds the transition open instead.
    ///
    /// It holds the transition of BOTH blocks — the cool-down asks GetReady
    /// for the same length. A driver walking a whole workout must not combine
    /// it with completeWorkout: six cool-down transitions at this length
    /// outlast the driver's own deadline. Pass --uitest-fast instead; it is
    /// checked first and wins when both are given.
    ///
    /// Production is untouched by both; DEBUG builds only.
    static var stageSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        if CommandLine.arguments.contains("--uitest-long-transition") { return 600 }
        #endif
        return seconds
    }
}
