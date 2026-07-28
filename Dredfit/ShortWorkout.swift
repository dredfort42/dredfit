//
//  ShortWorkout.swift
//  Dredfit
//
//  The short workout (issue #27): the answer to "I don't have 35 minutes"
//  that is not "skip the day". Three of the session's six exercises are
//  performed; the rest go to the engine as honest skips — the mechanism has
//  been in the engine since v2.1.1, this is the UI contract on top of it.
//
//  The session itself is never regenerated: the short version is a subset of
//  the very same list Today shows, so the resume fingerprint still matches
//  and the counter and rotation advance exactly as they would have.
//
//  Selection — "pull + anchor + laggard":
//
//    1. The pull slot always stays (pull, or pull_bar on bar sessions):
//       shoulder balance is not negotiable, and the slot is in every session
//       by design.
//    2. The anchor is the first movement of the rotation window
//       (`Engine.rotationAnchor`). Because the window shifts by 3 over 8
//       rotating patterns, the anchor visits all 8 over any 8 consecutive
//       sessions — so every movement is trained at least once even for
//       someone who only ever does short workouts.
//    3. The laggard is the lowest-level movement of the four that remain —
//       the self-correcting slot. Skipped patterns are frozen, so whatever
//       falls behind gets picked more often until it catches up.
//
//  Verified by simulation before implementing (spec §3.1): over 32 short
//  workouts from uneven levels every movement is trained 4–16 times and no
//  movement waits longer than 8 sessions. The naive "pull + the two lowest"
//  was rejected — it starves strong movements completely.
//

import Foundation
import DredfitCore

enum ShortWorkout {

    /// How many of the session's exercises the short version performs.
    static let exerciseCount = 3

    /// The patterns to perform, or nil when the session is too small to be
    /// worth shortening (never in practice — six exercises is the contract —
    /// but the flow must not be handed a "short" plan that is the whole
    /// session).
    static func plan(session: Session, counter: Int, levels: [Pattern: Int]) -> Set<Pattern>? {
        let patterns = session.exercises.map(\.pattern)
        guard patterns.count > exerciseCount else { return nil }

        var chosen: [Pattern] = []

        // 1. The pull slot — whichever branch this session took.
        if let pull = patterns.first(where: { $0 == .pull || $0 == .pullBar }) {
            chosen.append(pull)
        }

        // 2. The anchor. It comes from the rotation, so it is in the session
        //    by construction; the guard is defence in depth, not a case.
        let anchor = Engine.rotationAnchor(counter: counter)
        if patterns.contains(anchor), !chosen.contains(anchor) {
            chosen.append(anchor)
        }

        // 3. The laggard: lowest level among what is left. Ties resolve by
        //    session order — the same order the flow would run them in, so
        //    the choice is reproducible from the screen alone.
        let rest = patterns.filter { !chosen.contains($0) }
        if let laggard = rest.min(by: { lhs, rhs in
            let left = levels[lhs] ?? 0, right = levels[rhs] ?? 0
            if left != right { return left < right }
            return (patterns.firstIndex(of: lhs) ?? 0) < (patterns.firstIndex(of: rhs) ?? 0)
        }) {
            chosen.append(laggard)
        }

        // Fill from the session order if anything above was unavailable — a
        // short workout with two exercises would be a different promise than
        // the button makes.
        for pattern in patterns where chosen.count < exerciseCount {
            if !chosen.contains(pattern) { chosen.append(pattern) }
        }
        return Set(chosen)
    }

    /// The estimate the button shows, through the engine's own arithmetic:
    /// warm-up and cool-down included, so it is comparable with the full
    /// session's "≈ N min" right above it.
    static func estimatedMin(session: Session, plan: Set<Pattern>) -> Int {
        let exercises = session.exercises.filter { plan.contains($0.pattern) }
        return Int(Engine.estimatedMin(exercises: exercises).rounded())
    }
}
