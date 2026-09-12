//
//  Derived, never stored: computed from the state before and after
//  applyFeedback, so they cannot go stale or be double-counted.
//

import Foundation
import DredfitCore

enum Milestone: Identifiable, Equatable {
    /// A new movement on the ladder — and in v3 the ONLY door into one is a
    /// probe the person passed, so this milestone is always something they
    /// just did rather than something the engine decided (§40.4).
    case variationUp(pattern: Pattern, variation: Int, exercise: String)
    /// The top variation is the ceiling of the ladder; past it the sets grow
    /// instead (3 → 4 → 5, §40.5).
    case setBand(pattern: Pattern, sets: Int, exercise: String)
    case jubilee(workouts: Int)

    var id: String {
        switch self {
        // The identifier keeps its old prefix: UI tests key on it, and the
        // string is an identity, not a description.
        case .variationUp(let p, let v, _): return "tier-\(p.rawValue)-\(v)"
        case .setBand(let p, let s, _):     return "sets-\(p.rawValue)-\(s)"
        case .jubilee(let n):               return "jubilee-\(n)"
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
    /// session: new variations, set bands, jubilee.
    static func detect(before: EngineState,
                       after: EngineState,
                       session: Session,
                       skipped: Set<Pattern> = []) -> [Milestone] {
        var variationUps: [Milestone] = []
        var setBands: [Milestone] = []

        for ex in session.exercises where !skipped.contains(ex.pattern) {
            let pattern = ex.pattern
            let old = before.position(pattern)
            let new = after.position(pattern)
            // The *new* variation: the movement just unlocked.
            let name = Library.name(pattern, new.variation)

            if new.variation > old.variation {
                variationUps.append(.variationUp(pattern: pattern, variation: new.variation,
                                                 exercise: name))
            }
            // Not an `else`: entering a variation resets the sets to the base,
            // so the two cannot fire together today — but both render if the
            // banding ever changes.
            if new.sets > old.sets {
                setBands.append(.setBand(pattern: pattern, sets: new.sets, exercise: name))
            }
        }

        var result = variationUps + setBands
        // Not gated on the rating: a jubilee fires on one exact counter value
        // and never again — suppressing it would delete it permanently.
        if isJubilee(after.counter) {
            result.append(.jubilee(workouts: after.counter))
        }
        return result
    }
}
