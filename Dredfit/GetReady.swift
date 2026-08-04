//
//  GetReady.swift
//  Dredfit
//
//  The transition before every guided position (issue #52). Both blocks used
//  to start each position cold: the 30 s of a warm-up move and the timer of a
//  cool-down stretch began the instant the previous one ended, while the user
//  was still getting off the floor, reading the next name or finding the
//  wall. The first seconds of the interval went into moving house, not into
//  moving — the interval quietly lied about itself, and for the beginners the
//  app is built for that reads as "I can't keep up" rather than "the timer
//  starts too early".
//
//  Five seconds, the same length as the side-switch pause (issue #35), and
//  deliberately so: that pause counts a transition inside a position, this
//  one counts the transition between them. Neither is a user setting.
//
//  No estimate moves. The engine reserves 8 minutes for the two blocks
//  (warmupMin 5 + cooldownMin 3 = 480 s); with the transitions they spend
//  6 × 30 + 6 × 5 = 210 s on the warm-up and 6 × 30 + 6 × 5 + the side-switch
//  pauses = 220…235 s on the cool-down — 430…445 s of the reserved 480. The
//  number on "Today" keeps promising at least what the flow delivers.
//

import Foundation

enum GetReady {

    /// The transition length. Long enough for the 3-2-1 to run inside it with
    /// a beat to spare for reading the name of what is coming.
    static let seconds = 5

    /// --uitest-fast collapses the transition to a second, exactly as it
    /// already collapses the rest countdown and every cool-down stage: a
    /// driver walking both blocks would otherwise wait a real minute on
    /// transitions alone. Production is untouched; DEBUG builds only.
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
    static var stageSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        if CommandLine.arguments.contains("--uitest-long-transition") { return 600 }
        #endif
        return seconds
    }
}
