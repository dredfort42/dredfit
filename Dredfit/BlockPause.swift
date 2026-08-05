//
//  BlockPause.swift
//  Dredfit
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

    /// The way back into a frozen position: the app's one transition length,
    /// so the 3-2-1 fits with a beat left to read the name. Same seconds and
    /// same argument as the "Get ready" of issue #52 — one transition in the
    /// app lasts the same everywhere.
    static var reentrySeconds: Int { GetReady.stageSeconds }

    /// A frozen transition resumes straight into itself: it already IS the way
    /// back in, and a lead-in before a lead-in would count the user down
    /// twice. Every other stage — a move, a stretch, either side, the
    /// side-switch pause — hands its frozen seconds to a re-entry first.
    static func needsReentry(_ stage: Warmup.Stage) -> Bool { stage != .getReady }

    static func needsReentry(_ stage: Cooldown.Stage) -> Bool { stage != .getReady }

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

        mutating func beginReentry(seconds: Int, now: Date) {
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
