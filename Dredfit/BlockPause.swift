//
//  The pause of the guided blocks (issue #61). Warm-up and cool-down are the
//  only part of a workout that runs strictly on timers — working sets are
//  self-paced, and a rest timer that ran out while you answered the door only
//  granted extra rest — so they are the only part that needs a way to stand
//  still.
//
//  Orthogonal to both stage machines: neither Warmup nor Cooldown knows a
//  pause exists. The frozen seconds stay with the block; this owns only the
//  fact that they are frozen and how far the way back in has got.
//

import Foundation

enum BlockPause {

    /// The way back into a frozen position: the COUNT-IN — five seconds, the
    /// same beat a start tap buys before any clock runs.
    ///
    /// It was the base transition length (ten), and the tree carried two
    /// opposite reasons for that at once: this comment already said "Resume is
    /// tapped by someone already back in place, so this is a count-in, not
    /// travel time", while the test pinning it said being counted back into a
    /// position you walked away from IS travel. Ten seconds is a long wait for
    /// someone standing on the mat with a thumb on Resume. Owner's decision,
    /// 27.08.2026: it is a count-in, and it is five.
    ///
    /// The 3-2-1 still fits with two beats to spare (`countdownSignalSeconds`
    /// is 3), and the reserve the two blocks are budgeted to the second
    /// against is untouched: a pause is not part of the announced duration,
    /// and this can only make a paused session shorter.
    static var reentrySeconds: Int { GetReady.countInSeconds }

    /// A frozen transition resumes straight into itself: it already IS the way
    /// back in, and a lead-in before a lead-in would count the user down
    /// twice. Only what drops the user into a position — a move, a stretch,
    /// either side — hands its frozen seconds to a re-entry first.
    static func needsReentry(_ stage: Warmup.Stage) -> Bool { stage != .getReady }

    /// The cool-down has two transitions, and the side-switch is one of them:
    /// its go into the second side is still ahead of it, and a re-entry ending
    /// on a go of its own would sound the same signal twice seconds apart —
    /// exactly what issue #52 moved the go to stop doing.
    static func needsReentry(_ stage: Cooldown.Stage) -> Bool {
        stage != .getReady && stage != .switchPause
    }

    /// What a tick asks of the flow. The flow owns the tones and the block's
    /// own countdown; this owns the state.
    enum Tick: Equatable {
        case nothing
        case redraw
        /// One of the last seconds of the way back in.
        case signal
        /// The way back in is over — the position picks up where it stopped.
        case over
    }

    struct State: Equatable {
        private(set) var isPaused = false
        private(set) var reentryRemaining = 0
        private(set) var reentryEndDate: Date?

        /// Frozen and standing still — the screen says so and nothing moves.
        var isHeld: Bool { isPaused && reentryRemaining == 0 }

        /// Counting the user back in, so it owns the screen while it does.
        var isReentering: Bool { isPaused && reentryRemaining > 0 }

        /// Freezes: with no end date anywhere there is nothing to run out, so
        /// a locked or backgrounded phone changes nothing. Called on a running
        /// way back in too — pausing again holds where the block froze, and
        /// the lead-in starts over on the next resume.
        mutating func hold() {
            isPaused = true
            reentryRemaining = 0
            reentryEndDate = nil
        }

        /// A zero-length way back in would leave an end date the tick can
        /// never retire — held, with a deadline nobody reads. Hold plainly.
        mutating func beginReentry(seconds: Int, now: Date) {
            guard seconds > 0 else { return hold() }
            isPaused = true
            reentryRemaining = seconds
            reentryEndDate = now.addingTimeInterval(TimeInterval(seconds))
        }

        mutating func clear() { self = State() }

        /// The technique mini-sheet (issue #34) freezes the way back in like
        /// it freezes a position: reading is not getting back into position.
        mutating func freezeForSheet() { reentryEndDate = nil }

        /// ...and hands back exactly what it froze. A held block stays held —
        /// the user's pause outranks the sheet's, so the two cannot fight.
        mutating func thawAfterSheet(now: Date) {
            guard isReentering else { return }
            reentryEndDate = now.addingTimeInterval(TimeInterval(reentryRemaining))
        }

        mutating func tick(now: Date, signalSeconds: Int) -> Tick {
            guard let end = reentryEndDate else { return .nothing }
            let remaining = max(0, Int(end.timeIntervalSince(now).rounded()))
            guard remaining != reentryRemaining else { return .nothing }
            guard remaining > 0 else { return .over }
            let audible = remaining <= signalSeconds && remaining < reentryRemaining
            reentryRemaining = remaining
            return audible ? .signal : .redraw
        }
    }
}
