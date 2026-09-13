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

    /// 5 → 10 → 8. Five seconds to change posture was a rush and people said
    /// so; ten turned out to be longer than the change takes, and the block
    /// spent the difference on standing still (owner, 06.09.2026). The reserve
    /// this is spent against is the engine's — see `setupSupplementSec`.
    static let seconds = 8

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
    /// Buying one more second is an ENGINE change, not an app one, and the
    /// engine has already made it once: the base transition doubled to 10 s —
    /// five seconds is not enough to change posture without hurrying — and
    /// `cooldownMin` rose from 3 to 4 to pay for it. The price was named
    /// rather than absorbed: every announced session duration grew by exactly
    /// one minute, and the engine's own acceptance asserts "grew by 1.0".
    ///
    /// SHORTENING is the safe direction, and on 06.09.2026 the base went to 8
    /// (supplemented stage 12). The worst pair is now 520 s against a reserve
    /// of 600, so ten minutes is no longer the smallest whole minute that
    /// fits — nine would hold it. **The owner kept ten** (06.09.2026): giving
    /// the minute back is the same engine wave in reverse and would take a
    /// minute off every announced duration, the onboarding line and the store
    /// listing, to reclaim slack nobody is short of.
    ///
    /// So the warning is now one-sided and still stands: seconds may be given
    /// back here freely, but the next second SPENT has to be bought from the
    /// engine. `BlockReserveTests` holds the floor and the ceiling.
    static let setupSupplementSec = 4

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
    /// being counted in — the same beat the way back in from a pause gets,
    /// which is literally this constant since 27.08.2026 (`BlockPause`).
    ///
    /// Before a hold it is preparation time that always existed, moved inside
    /// the app's clock: it used to be spent BEFORE the tap. On a transition it
    /// may only SHORTEN what is already running (see `countInWarmupMove`) —
    /// the two blocks are budgeted to the second, so a tap that lengthened one
    /// would spend a reserve this layer does not own.
    /// 5 → 4 (owner, 06.09.2026), with the transition and the side-switch
    /// pause. It stays the SHORTEST of the three — travel to a position is
    /// eight seconds, turning over inside one is four, and being counted in
    /// after saying "ready" is four as well: the last two are the same act
    /// from the athlete's side, and they are one number again.
    ///
    /// Four still holds the 3-2-1 (`countdownSignalSeconds` is 3) with one
    /// beat to spare rather than two. Three would put the first tick under
    /// the thumb that asked for it, which is the whole reason this beat
    /// exists — so four is the floor, not a waypoint.
    static var countInSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        #endif
        return 4
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
    /// It no longer stretches the way back in from a pause (issue #61): since
    /// 27.08.2026 that asks for `countInSeconds`, which only `--uitest-fast`
    /// touches. A test that pauses a running position under this flag is
    /// counted back in at the real five seconds.
    ///
    /// Production is untouched by both; DEBUG builds only.
    static var stageSeconds: Int { stageSeconds(needsSetup: false) }
}
