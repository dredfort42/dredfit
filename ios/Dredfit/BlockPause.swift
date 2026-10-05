//
//  The pause of the guided blocks (issue #61) and of a hands-free hold run's
//  rest. Warm-up and cool-down run strictly on timers, and so does a
//  hands-free run: its rest STARTS the next set when it ends. Working sets are
//  self-paced, and any other rest that runs out while you answer the door
//  only grants extra rest — so these are the only parts that need a way to
//  stand still.
//
//  Orthogonal to the blocks' stage machine: `GuidedBlock` knows nothing of a
//  pause. The frozen seconds stay with the block; this owns only the fact
//  that they are frozen and how far the way back in has got.
//

import Foundation

enum BlockPause {

    /// The way back into a frozen position: the COUNT-IN — four seconds, the
    /// same beat a start tap buys before any clock runs.
    ///
    /// A count-in, not travel time: Resume is tapped by someone already back
    /// in place, standing on the mat with a thumb on it, and a transition's
    /// length would be a long wait for them. The owner's decision, and it is
    /// whatever the count-in is, so the two cannot drift apart.
    ///
    /// The 3-2-1 fits with one beat to spare (`countdownSignalSeconds` is 3),
    /// and the reserve the two blocks are budgeted against does not pay for
    /// it: a pause is not part of the announced duration.
    static var reentrySeconds: Int { GetReady.countInSeconds }

    /// How far past a stage boundary a block may run and still just carry on.
    ///
    /// Beyond it the phone was somewhere else — a call, another app, a pocket
    /// — and the block freezes instead of absorbing the stages the absence
    /// covered. The threshold is the count-in for the reason the rest uses
    /// three seconds for its own version of this: past it, whatever the block
    /// would have said was said to nobody, and a signal nobody could hear must
    /// not be what started a position.
    ///
    /// One value for both blocks, and the DEBUG override is not cosmetic:
    /// under `--uitest-fast` a whole stage is one second, so the real
    /// threshold would read an ordinary late tick on a saturated runner as an
    /// absence and freeze a suite that never left the foreground. What is
    /// being detected is a real absence, and no test takes one.
    static var absenceSeconds: Int {
        #if DEBUG
        if CommandLine.arguments.contains("--uitest-fast") { return 60 }
        #endif
        return GetReady.countInSeconds
    }

    /// The seconds a REST picks up when the pause ends or the technique sheet
    /// closes.
    ///
    /// A rest is not a position to be counted back into — it is time being
    /// given — so it resumes into itself with no lead-in of its own. What it
    /// does need is a floor: on a hands-free hold run the rest STARTS the next
    /// set when it ends, and resuming with two seconds left would drop someone
    /// who has just walked back in straight into a plank. The floor is the
    /// count-in every start tap earns, and it is capped by the rest's own
    /// total so a one-second rest under `--uitest-fast` stays one second.
    static func restAfterPause(remaining: Int, total: Int) -> Int {
        max(remaining, min(reentrySeconds, total))
    }

    /// The seconds a frozen guided stage picks up when the pause ends.
    ///
    /// A transition is its own way back in (`needsReentry`), so it never picks
    /// up less than the count-in: the seconds before its go — with the 3-2-1
    /// on a "Get ready" — are what someone who has just come back needs, and
    /// one frozen a second or two from its end, by a tap or by an absence,
    /// would otherwise drop them into the position on a partial count or none.
    /// In production the side switch is no longer than the count-in, so it
    /// comes back whole.
    /// A position takes the re-entry instead and keeps exactly the seconds it
    /// froze with.
    static func stageAfterPause(remaining: Int, stage: GuidedStage) -> Int {
        needsReentry(stage) ? remaining : max(remaining, reentrySeconds)
    }

    /// A frozen transition resumes straight into itself: it already IS the way
    /// back in, and a lead-in before a lead-in would count the user down
    /// twice. Only what drops the user into a position — a whole one, either
    /// half — hands its frozen seconds to a re-entry first.
    ///
    /// The side switch is a transition too: its go into the second half is
    /// still ahead of it, and a re-entry ending on a go of its own would sound
    /// the same signal twice seconds apart — exactly what issue #52 moved the
    /// go to stop doing.
    static func needsReentry(_ stage: GuidedStage) -> Bool {
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
        private(set) var reentry = Countdown()

        var reentryRemaining: Int { reentry.remaining }
        var reentryEndDate: Date? { reentry.endDate }

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
            reentry.stand(at: 0)
        }

        /// A zero-length way back in would end on the next tick: a go with no
        /// count before it. Hold plainly.
        mutating func beginReentry(seconds: Int, now: Date) {
            guard seconds > 0 else { return hold() }
            isPaused = true
            reentry.start(seconds, now: now)
        }

        mutating func clear() { self = State() }

        /// The technique mini-sheet (issue #34) freezes the way back in like
        /// it freezes a position: reading is not getting back into position.
        mutating func freezeForSheet() { reentry.freeze() }

        /// ...and hands back exactly what it froze. A held block stays held —
        /// the user's pause outranks the sheet's, so the two cannot fight.
        mutating func thawAfterSheet(now: Date) {
            guard isReentering else { return }
            reentry.resume(now: now)
        }

        mutating func tick(now: Date, signalSeconds: Int) -> Tick {
            switch reentry.read(now: now) {
            case .unchanged:
                return .nothing
            case .ended:
                return .over
            case .second(let second):
                let audible = reentry.signals(second, within: signalSeconds)
                reentry.show(second)
                return audible ? .signal : .redraw
            }
        }
    }
}
