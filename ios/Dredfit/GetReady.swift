//
//  The transition before every guided position (issue #52). Eight seconds is
//  the base; a position that has to be walked to or got down into carries a
//  supplement on top (issue #83). Neither number is a user setting.
//
//  The side-switch pause of issue #35 is not a transition and does not take
//  its length: it is a pause inside one position, not travel to another.
//

import Foundation

enum GetReady {

    /// Eight: five seconds to change posture is a rush, and ten is longer than
    /// the change takes — the block would spend the difference standing
    /// still. The reserve this is spent against is the engine's — see
    /// `setupSupplementSec`.
    static let seconds = 8

    /// The supplement of issue #83, on top of `seconds`, for a position that
    /// changes the starting position (standing → the floor) or needs a prop
    /// (a wall). The flag travels with the move or position (`needsSetup`) —
    /// the cool-down set is dynamic, so an index would not survive
    /// composition.
    ///
    /// Neither this nor the base length is a taste: both are spent against a
    /// reserve the engine owns. `warmupMin + cooldownMin` is the whole budget
    /// for the two blocks, and the dearest pair the app can compose — every
    /// supplemented position drawn, every switch pause played — is 520 s
    /// against a reserve of 600. Past the reserve, a longer transition is an
    /// ENGINE change, not an app one: the minute it needs goes into the
    /// reserve, and with it into every announced session duration.
    ///
    /// Nine minutes would hold 520 s, and **the owner kept ten**: giving the
    /// minute back is an engine change too, and would take a minute off every
    /// announced duration, the onboarding line and the store listing, to
    /// reclaim slack nobody is short of. `BlockReserveTests` holds the floor
    /// (the blocks never overrun the reserve) and the ceiling (the reserve
    /// never holds two spare minutes).
    static let setupSupplementSec = 4

    /// The count-in a START TAP earns before any clock runs.
    ///
    /// Without it "I'm ready" and "Start hold" would put the countdown under
    /// the thumb: the number would jump from the transition's to the
    /// position's — or from the plank's target straight into running — while
    /// the hand is still moving away from the glass, and on a hold every
    /// second of that would come off the number the engine measures.
    ///
    /// Four, not `seconds`: this is a count-in, not travel. The person has
    /// just said they are ready and needs only the beat between saying it and
    /// being counted in — the same beat the way back in from a pause gets,
    /// which is this constant (`BlockPause.reentrySeconds`).
    ///
    /// Before a hold it is preparation time that would otherwise be spent
    /// BEFORE the tap, moved inside the app's clock. On a transition it may
    /// only SHORTEN what is already running (see `WorkoutSession.countIn`) —
    /// a tap that lengthened one would spend a reserve this layer does not
    /// own.
    ///
    /// The shortest of the three lengths, tied with the side-switch pause:
    /// travel to a position is eight seconds, turning over inside one is
    /// four, and being counted in after saying "ready" is four as well — the
    /// last two are the same act from the athlete's side, so they take the
    /// same time.
    ///
    /// Four holds the 3-2-1 (`countdownSignalSeconds` is 3) with one beat to
    /// spare. Three would put the first tick under the thumb that asked for
    /// it, which is the whole reason this beat exists — so four is the floor,
    /// not a waypoint.
    static var countInSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 1 }
        #endif
        return 4
    }

    /// The two lengths a transition can have. The side-switch pause and the
    /// way back in from a pause (issue #61) take neither: the switch is a
    /// pause inside one position, not travel to another, and Resume is tapped
    /// by someone already back — its 3-2-1 is a count-in, not travel time.
    /// Both run four seconds (`Cooldown.sideSwitchPauseSec`,
    /// `BlockPause.reentrySeconds`).
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
    /// that taps it has a few seconds for the whole of resolve-element-then-
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
    /// It does not stretch the way back in from a pause (issue #61): that
    /// asks for `countInSeconds`, which only `--uitest-fast` touches. A test
    /// that pauses a running position under this flag is counted back in at
    /// the real four seconds.
    ///
    /// Production is untouched by both; DEBUG builds only.
    static var stageSeconds: Int { stageSeconds(needsSetup: false) }
}
