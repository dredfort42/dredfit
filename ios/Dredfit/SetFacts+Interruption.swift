//
//  Time charged to an absence, and what an interrupted workout amounts to.
//

import Foundation
import DredfitCore

nonisolated extension SetFacts {
    // MARK: - Time the athlete was away

    /// Seconds to charge to an ABSENCE rather than to the workout, for one
    /// resume: everything past the moment the session stopped owing time.
    ///
    /// A rest running on schedule is training whether or not the process
    /// survived it. Measured from `savedAt` alone — the last phase transition,
    /// which for a rest is its START — a phone locked at the top of a 90 s
    /// rest and opened at its end would report a workout a minute and a half
    /// SHORTER than it was, the exact mirror of the inflation the away time
    /// exists to remove.
    ///
    /// The work screen carries no end date, so a kill inside a hold still
    /// charges the set to the absence. That is a known floor, not a claim:
    /// closing it needs the moment of leaving stamped on the snapshot, which
    /// nothing writes yet.
    ///
    /// Here rather than in the flow because it is arithmetic over three dates,
    /// and a rule stated inside a SwiftUI view is a rule no test can reach.
    static func awayGained(savedAt: Date, restEndDate: Date?, now: Date) -> Int {
        let owedUntil = max(savedAt, restEndDate ?? .distantPast)
        return max(0, Int(now.timeIntervalSince(owedUntil)))
    }

    /// An absence the PROCESS LIVED THROUGH: the flow sent to the background
    /// and brought back without dying. Charged by the same rule `restore`
    /// uses, from the moment of leaving — otherwise a phone locked overnight
    /// would send an eleven-hour workout to Health.
    /// The rest end is taken AS IT STOOD WHEN THE SCENE LEFT: on the way back
    /// the timer may tick first, and the tick that ends a rest clears its date.
    struct Absence {
        private var leftAt: Date?
        private var restEndDate: Date?

        /// A leaving is stamped and not spent yet.
        var isAway: Bool { leftAt != nil }

        /// The first leaving wins.
        mutating func leave(now: Date, restEndDate: Date?) {
            guard leftAt == nil else { return }
            leftAt = now
            self.restEndDate = restEndDate
        }

        /// Seconds to add to the away time (0 if nothing was stamped); spends
        /// the stamp.
        mutating func comeBack(now: Date) -> Int {
            guard let leftAt else { return 0 }
            let gained = SetFacts.awayGained(savedAt: leftAt, restEndDate: restEndDate, now: now)
            self = Absence()
            return gained
        }
    }

    // MARK: - An interrupted workout

    /// What an interruption amounts to: which movements were never trained,
    /// how many sets of the one in progress are missing, and which movement —
    /// if any — was left half-done.
    ///
    /// ONE place, because two callers describe the same interruption: the
    /// flow's "finish now" and the settlement of a workout that was trained
    /// and never rated. Two copies would let the same abandoned session reach
    /// the journal two different ways depending on whether the app happened
    /// to stay alive.
    struct Settlement: Equatable {
        /// Never reached. A skip to the engine: the ladder freezes.
        var skipped: Set<Pattern> = []
        /// Sets taken off a movement that WAS trained — its numbers stay.
        var setsSkipped: Skips = [:]
        /// Left half-done. Also a skip to the engine; "not finished" is the
        /// only difference, and it is a difference the athlete sees.
        var interrupted: Pattern?
    }

    /// - Parameters:
    ///   - exIndex: the exercise in front of the athlete when it stopped.
    ///   - setsBehind: sets of THAT exercise already over, skips included.
    ///   - currentIsDone: every set of it is behind — the rest that follows a
    ///     last set, the summary of a finished hold, or the rating screen.
    static func settlement(in exercises: [SessionExercise],
                           exIndex: Int,
                           setsBehind: Int,
                           currentIsDone: Bool,
                           alreadySkipped: Skips) -> Settlement {
        var out = Settlement(setsSkipped: alreadySkipped)
        // Clamped from below the way `restore(from:)` clamps a resume: both
        // numbers come off disk, and a negative index would trap here inside
        // `activate()` before the snapshot is cleared — so every launch after
        // it would trap too. Past the end is NOT clamped: it means all
        // behind. A negative count settles exactly like zero.
        let exIndex = max(exIndex, 0)
        let setsBehind = max(setsBehind, 0)
        guard exIndex < exercises.count else { return out }
        var firstUnfinished = exIndex
        if currentIsDone {
            firstUnfinished = exIndex + 1
        } else {
            let ex = exercises[exIndex]
            let already = alreadySkipped[ex.pattern] ?? 0
            let left = max(0, ex.sets - setsBehind)
            let performed = setsBehind - already
            // Enough of the movement is behind to leave a trained one: keep
            // its numbers and let the remainder travel as skipped SETS, the
            // same statement an in-workout skip makes. Otherwise there is no
            // movement to keep, and it is named as unfinished instead.
            if performed >= EngineConfig.setsFloor,
               skipFits(left, of: ex.sets, alreadySkipped: already) {
                if left > 0 { out.setsSkipped[ex.pattern, default: 0] += left }
                firstUnfinished = exIndex + 1
            } else if setsBehind > 0 {
                out.interrupted = ex.pattern
            }
        }
        for ex in exercises[min(firstUnfinished, exercises.count)...] {
            out.skipped.insert(ex.pattern)
            // A skip wins over a partial count: the movement was not trained.
            out.setsSkipped.removeValue(forKey: ex.pattern)
        }
        return out
    }
}
