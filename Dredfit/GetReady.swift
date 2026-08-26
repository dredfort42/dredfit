//
//  The transition before every guided position (issue #52). Ten seconds is
// the base; a position that has to be walked to or got down into carries a
// supplement on top (issue #83). Neither number is a user setting.
//
//  The side-switch pause of issue #35 shared the base length and no longer
//  does: it is a pause inside one position, not travel to another.
//

import Foundation

enum GetReady {

    /// 5 → 10. Five seconds to change posture is a rush, and it is what people
    /// said about it. The reserve this is spent against was raised to match by
    /// the engine, not here — see `setupSupplementSec`.
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
    /// base it is 245 + 295 = 540 s = 9:00. Buying one more second is an
    /// ENGINE change, not an app one, and the engine has already made it
    /// once: the base transition doubled to 10 s — five seconds is not enough
    /// to change posture without hurrying — and `cooldownMin` rose from 3 to
    /// 4 to pay for it. The price is named rather than absorbed: every
    /// announced session duration grew by exactly one minute, and the
    /// engine's own acceptance asserts "grew by 1.0", not "unchanged".
    ///
    /// The reserve is again spent to the second, so the warning stands: the
    /// next second has to be bought from the engine too.
    static let setupSupplementSec = 5

    /// The count-in a START TAP earns before any clock runs.
    ///
    /// "I'm ready" and "Start hold" both used to put the countdown under the
    /// thumb: the number jumped from the transition's to the position's — or
    /// from the plank's target straight into running — while the hand was
    /// still moving away from the glass, and on a hold every second of that
    /// came off the number the engine measures.
    ///
    /// Five, not `seconds`: this is a count-in, not travel. The person has
    /// just said they are ready and needs only the beat between saying it and
    /// being counted in — the same beat the way back in from a pause gets.
    ///
    /// Before a hold it is preparation time that always existed, moved inside
    /// the app's clock: it used to be spent BEFORE the tap. On a transition it
    /// may only SHORTEN what is already running (see `countInWarmupMove`) —
    /// the two blocks are budgeted to the second, so a tap that lengthened one
    /// would spend a reserve this layer does not own.
    static var countInSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        #endif
        return 5
    }

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
    /// changes nothing a test under this flag can see. What it does NOT hold
    /// is a transition a START TAP opened or cut: that one is the count-in and
    /// lasts `countInSeconds` whatever this flag says, so a test that needs to
    /// tap a control living only on the transition has to reach an automatic
    /// one first — skip a position, and the next transition is held open. A driver walking a
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
