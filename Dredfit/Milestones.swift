//
//  Derived, never stored: computed from the state before and after
//  applyFeedback, so they cannot go stale or be double-counted.
//

import Foundation
import DredfitCore

enum Milestone: Identifiable, Equatable {
    case tierUp(pattern: Pattern, tier: Int, exercise: String)
    /// Tier 4 is the ceiling; past it the sets grow instead (3 → 4 → 5).
    case setBand(pattern: Pattern, sets: Int, exercise: String)
    case jubilee(workouts: Int)

    var id: String {
        switch self {
        case .tierUp(let p, let t, _):  return "tier-\(p.rawValue)-\(t)"
        case .setBand(let p, let s, _): return "sets-\(p.rawValue)-\(s)"
        case .jubilee(let n):           return "jubilee-\(n)"
        }
    }
}

enum MilestoneDetector {

    /// Jubilees: 10, 25, then every 50 (50, 100, 150, …).
    static func isJubilee(_ counter: Int) -> Bool {
        counter == 10 || counter == 25 || (counter > 0 && counter.isMultiple(of: 50))
    }

    /// Skipped patterns are excluded explicitly, so this stays true even if
    /// the engine's skip handling changes. Order is deterministic for a given
    /// session: tier-ups, set bands, jubilee.
    static func detect(before: EngineState,
                       after: EngineState,
                       session: Session,
                       skipped: Set<Pattern> = []) -> [Milestone] {
        var tierUps: [Milestone] = []
        var setBands: [Milestone] = []

        for ex in session.exercises where !skipped.contains(ex.pattern) {
            let pattern = ex.pattern
            let old = Level.decode(before.levels[pattern] ?? 0)
            let new = Level.decode(after.levels[pattern] ?? 0)
            // The *new* tier: the exercise just unlocked.
            let name = ExerciseLibrary.entry(for: pattern).variations[new.tier - 1].name

            if new.tier > old.tier {
                tierUps.append(.tierUp(pattern: pattern, tier: new.tier, exercise: name))
            }
            // Not an `else`: a single step cannot raise both today, but both
            // render correctly if the engine's banding ever changes.
            if new.sets > old.sets {
                setBands.append(.setBand(pattern: pattern, sets: new.sets, exercise: name))
            }
        }

        var result = tierUps + setBands
        // Not gated on the rating: a jubilee fires on one exact counter value
        // and never again — suppressing it would delete it permanently.
        if isJubilee(after.counter) {
            result.append(.jubilee(workouts: after.counter))
        }
        return result
    }
}
