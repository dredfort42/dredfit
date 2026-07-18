//
//  Milestones.swift
//  Dredfit
//
//  Milestones (v1.4) are derived, never stored: the state before and after
//  applyFeedback is all it takes. Nothing new is persisted, so a milestone
//  cannot go stale, be double-counted, or need a migration.
//
//  Only upward movement counts. A deload or a shortfall is never announced —
//  the app does not comment on a bad day.
//

import Foundation
import DredfitCore

enum Milestone: Identifiable, Equatable {
    /// A pattern crossed into a harder variation.
    case tierUp(pattern: Pattern, tier: Int, exercise: String)
    /// Tier 4 is the ceiling; past it the sets grow instead (3 → 4 → 5).
    case setBand(pattern: Pattern, sets: Int, exercise: String)
    /// Workout count, independent of how the session went.
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
        counter == 10 || counter == 25 || (counter > 0 && counter % 50 == 0)
    }

    /// Compares the two states over the patterns that were actually trained.
    ///
    /// Skipped patterns are excluded: the engine leaves their level untouched,
    /// so they cannot produce a milestone anyway — excluding them explicitly
    /// keeps that true even if the engine's skip handling ever changes.
    ///
    /// Order is the spec's: tier-ups, then set bands, then the jubilee. Within
    /// a kind the session order (Pattern.ordered) decides, so the screen is
    /// deterministic for a given session.
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
            // The name comes from the *new* tier — that is the whole point of
            // the screen: this is the exercise you just unlocked.
            let name = ExerciseLibrary.entry(for: pattern).variations[new.tier - 1].name

            if new.tier > old.tier {
                tierUps.append(.tierUp(pattern: pattern, tier: new.tier, exercise: name))
            }
            // Not an `else`: a single step cannot raise both (tier caps at 4
            // exactly where the set bands begin), but the screen renders both
            // correctly if the engine's banding ever changes.
            if new.sets > old.sets {
                setBands.append(.setBand(pattern: pattern, sets: new.sets, exercise: name))
            }
        }

        var result = tierUps + setBands
        // Deliberately not gated on the session rating. A jubilee fires on one
        // exact counter value and never again — suppressing it after a hard
        // session would delete it permanently, and "you have done 10 workouts"
        // is a fact, not praise for today. (The review request in B5 *is*
        // gated on the rating; that one can wait for a better day.)
        if isJubilee(after.counter) {
            result.append(.jubilee(workouts: after.counter))
        }
        return result
    }
}
