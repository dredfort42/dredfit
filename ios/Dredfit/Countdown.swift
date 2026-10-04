import Foundation

/// One countdown of the workout flow: a rest, a hold, a count-in, a side
/// switch, a stage of a guided block, the way back into a paused one.
///
/// The clock is an end DATE, never a tick count, so a locked or backgrounded
/// phone loses nothing — every tick re-reads the date. `remaining` is the
/// second on screen. Without a date the countdown stands still on that
/// second: paused, frozen under a sheet, or over.
///
/// What a countdown does when it ends is its owner's business; this type
/// only says that it ended and how late the tick that noticed it came.
struct Countdown: Equatable {
    private(set) var endDate: Date?
    private(set) var remaining = 0

    var isRunning: Bool { endDate != nil }

    /// Runs `seconds` from `now`, and returns the end date for whatever has
    /// to count down to the same moment (the lock screen).
    @discardableResult
    mutating func start(_ seconds: Int, now: Date) -> Date {
        let end = now.addingTimeInterval(TimeInterval(seconds))
        remaining = seconds
        endDate = end
        return end
    }

    /// Runs until `end`, showing what is left of it — a countdown restored
    /// from a date written before the process died.
    mutating func run(until end: Date, now: Date) {
        endDate = end
        remaining = max(0, Int(end.timeIntervalSince(now).rounded()))
    }

    /// Runs on from the second on screen — the way out of a freeze.
    mutating func resume(now: Date) {
        endDate = now.addingTimeInterval(TimeInterval(remaining))
    }

    /// Stops the clock; the second on screen stays, ready for `resume`.
    mutating func freeze() {
        endDate = nil
    }

    /// Stops the clock and shows `seconds`.
    mutating func stand(at seconds: Int) {
        endDate = nil
        remaining = seconds
    }

    /// Shows `seconds` instead of what was there: a running countdown runs
    /// them from `now`, a frozen one stays frozen on them.
    mutating func reset(to seconds: Int, now: Date) {
        if isRunning { start(seconds, now: now) } else { remaining = seconds }
    }

    /// Moves a running end date, and the second on screen with it.
    mutating func extend(by seconds: Int, now: Date) {
        guard let endDate else { return }
        run(until: endDate.addingTimeInterval(TimeInterval(seconds)), now: now)
    }

    /// What a tick found.
    enum Reading: Equatable {
        /// Not running, or still above zero on the second already shown.
        case unchanged
        /// A new second to show; nothing has been shown yet — see `show`.
        case second(Int)
        /// Ran out. `overshoot` is how far past the end date the tick came:
        /// near zero while the app is in front of the person, and the length
        /// of the absence when it comes back from one.
        case ended(overshoot: TimeInterval)
    }

    /// Reads the clock without changing anything, so the owner decides what
    /// is animated, sounded and reset — and in which order.
    ///
    /// Rounded to the nearest second, so a running countdown reaches 0 half a
    /// second before its end date. Zero always ends it, even when 0 is already
    /// on screen — a rest restored in its last half-second, or a countdown
    /// started at zero, has no new second to show and would otherwise never
    /// end.
    func read(now: Date) -> Reading {
        guard let endDate else { return .unchanged }
        let left = endDate.timeIntervalSince(now)
        let second = max(0, Int(left.rounded()))
        if second == 0 { return .ended(overshoot: -left) }
        return second == remaining ? .unchanged : .second(second)
    }

    /// Shows a second `read` returned.
    mutating func show(_ second: Int) {
        remaining = second
    }

    /// The 3-2-1: one of the last `signalSeconds`, reached on the way DOWN.
    /// A countdown that comes back from the background past several of them
    /// sounds only the one it lands on, and one that was just extended
    /// sounds its last seconds again on the new way down.
    func signals(_ second: Int, within signalSeconds: Int) -> Bool {
        second <= signalSeconds && second < remaining
    }
}
