//
//  ShortWorkout.swift
//  Dredfit
//
//  The short workout (issue #27): three of the session's six exercises are
//  performed, the rest go to the engine as honest skips.
//
//  The session is never regenerated — the short version is a subset of the
//  very list Today shows, so the resume fingerprint still matches.
//
//  Selection is "pull + anchor + laggard", verified by simulation (spec
//  §3.1): over 32 short workouts every movement is trained 4–16 times and
//  none waits longer than 8 sessions. The naive "pull + the two lowest" was
//  rejected — it starves strong movements completely.
//

import Foundation
import DredfitCore

enum ShortWorkout {

    /// How many of the session's exercises the short version performs.
    static let exerciseCount = 3

    /// nil when the session is too small to shorten — the flow must never be
    /// handed a "short" plan that is the whole session.
    static func plan(session: Session, counter: Int, levels: [Pattern: Int]) -> Set<Pattern>? {
        let patterns = session.exercises.map(\.pattern)
        guard patterns.count > exerciseCount else { return nil }

        var chosen: [Pattern] = []

        // Pull slot, whichever branch this session took: shoulder balance
        // is not negotiable.
        if let pull = patterns.first(where: { $0 == .pull || $0 == .pullBar }) {
            chosen.append(pull)
        }

        // The anchor visits all 8 rotating patterns over any 8 sessions, so
        // nothing starves. It is in the session by construction; the guard is
        // defence in depth.
        let anchor = Engine.rotationAnchor(counter: counter)
        if patterns.contains(anchor), !chosen.contains(anchor) {
            chosen.append(anchor)
        }

        // The laggard: lowest level among what is left — the self-correcting
        // slot. Ties resolve by session order, so the pick is reproducible.
        let rest = patterns.filter { !chosen.contains($0) }
        if let laggard = rest.min(by: { lhs, rhs in
            let left = levels[lhs] ?? 0, right = levels[rhs] ?? 0
            if left != right { return left < right }
            return (patterns.firstIndex(of: lhs) ?? 0) < (patterns.firstIndex(of: rhs) ?? 0)
        }) {
            chosen.append(laggard)
        }

        // Fill from session order: a short workout with two exercises would
        // be a different promise than the button makes.
        for pattern in patterns where chosen.count < exerciseCount {
            if !chosen.contains(pattern) { chosen.append(pattern) }
        }
        return Set(chosen)
    }

    /// Through the engine's own arithmetic, so it is comparable with the
    /// full session's "≈ N min" right above it.
    static func estimatedMin(session: Session, plan: Set<Pattern>) -> Int {
        let exercises = session.exercises.filter { plan.contains($0.pattern) }
        return Int(Engine.estimatedMin(exercises: exercises).rounded())
    }
}
