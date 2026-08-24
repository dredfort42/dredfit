//
//  The transition before every guided position (issue #52). Ten seconds is
//  the base since v2.26 (spec §37.7a); a position that has to be walked to or
//  got down into carries a supplement on top (issue #83). Neither number is a
//  user setting.
//
//  The side-switch pause of issue #35 shared the base length and no longer
//  does: it is a pause inside one position, not travel to another.
//

import Foundation

enum GetReady {

    /// v2.26 (spec §37.7a): 5 → 10. Five seconds to change posture is a rush,
    /// and it is what people said about it. The reserve this is spent against
    /// was raised to match by the engine, not here — see `setupSupplementSec`.
    static let seconds = 10

    /// The supplement of issue #83, on top of `seconds`, for a position that
    /// changes the starting position (standing → the floor) or needs a prop
    /// (a wall). The flag travels with the move or position (`needsSetup`) —
    /// the cool-down set is dynamic, so an index would not survive
    /// composition.
    ///
    /// Five is not a taste, and neither is the base length: both are spent
    /// against a reserve the engine owns. `warmupMin + cooldownMin` is the
    /// whole budget for the two blocks, and the worst-case composition —
    /// every supplemented position drawn, every per-side pause played —
    /// lands on it exactly, with nothing to spare:
    ///
    ///     warm-up   6 moves, one supplemented   5×(base+30) + (base+5+30)
    ///     cool-down 6 poses, five supplemented  5×(base+5+35) + (base+35)
    ///
    /// At a 5-second base that is 215 + 265 = 480 s = 8:00; at a 10-second
    /// base it is 245 + 295 = 540 s = 9:00. This comment used to say that one
    /// second more would break the reserve and that fixing it is an engine
    /// change, not an app one. That was right, and engine v2.26 is that
    /// change: §37.7а doubles the base transition to 10 s — five seconds is
    /// not enough to change posture without hurrying — and raises
    /// `cooldownMin` from 3 to 4 to pay for it. The price is named rather
    /// than absorbed: every announced session duration grew by exactly one
    /// minute, and the engine's own acceptance asserts "grew by 1.0", not
    /// "unchanged".
    ///
    /// The reserve is again spent to the second, so the warning stands as it
    /// did: the next second has to be bought from the engine.
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
