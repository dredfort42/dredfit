//
//  The athlete's handles.
//
//  The wave removes two mechanisms that decided FOR the person — the pain
//  channel and the time budget — and gives back three controls that decide
//  WITH them. Every one of them goes through the ENGINE. The app writing a
//  level or a cut into the state by hand is the bypass of `applyFeedback` the
//  audit counts as a finding: it would skip the floor, the sanitizer, and the
//  position measure the postcondition repair reads.
//
//  This file holds what the handles can be ASKED — availability and previews.
//  The four actions that WRITE state live in AppStore proper, the same way
//  `acceptComeback` does: the store owns its own mutations.
//
//  All three live on the plan, before the workout starts. That is not a
//  layout preference: `nextSession` is generated from the state on every
//  access, so pulling a handle here redraws the plan AND the announced
//  duration together. Mid-workout they would have to mutate a session the
//  engine is already going to read the plan from when feedback lands, and a
//  shown plan that disagrees with the one the rating is computed against is a
//  defect rather than a feature.
//

import Foundation
import DredfitCore

extension AppStore {

    // MARK: - Per-movement: an easier variation

    /// False on tier 1 — there is no variation below it, and the control says
    /// so instead of disappearing.
    func canMakeEasier(_ pattern: Pattern) -> Bool {
        Engine.easierLevel(pattern: pattern,
                           level: engineState.levels[pattern] ?? 0,
                           sub: engineState.sub[pattern] ?? 0,
                           cut: engineState.cutOf(pattern)) != nil
    }

    /// The name this movement would carry after the handle — shown BEFORE the
    /// tap, so the choice is made on the thing itself rather than on a
    /// promise. Nil when the handle is inactive.
    func easierPreview(_ pattern: Pattern) -> String? {
        guard canMakeEasier(pattern) else { return nil }
        let after = Engine.easierVariation(state: engineState, pattern: pattern)
        return Engine.generateSession(after).exercises
            .first { $0.pattern == pattern }
            .map { "\($0.name) · \($0.display)" }
    }

    // MARK: - Per-movement: fewer sets

    /// False once the movement is already on the shared floor of two sets.
    func canTakeSetOff(_ pattern: Pattern) -> Bool {
        engineState.cutOf(pattern)
            < Level.cutMax(level: engineState.levels[pattern] ?? 0,
                           floor: EngineConfig.setsFloor)
    }

    /// True once anything has been taken off this movement — the control that
    /// puts it back has to be reachable, or the handle is a one-way door.
    func canGiveSetBack(_ pattern: Pattern) -> Bool {
        engineState.cutOf(pattern) > 0
    }

    // MARK: - The session handle: shorter today

    /// How long today's workout is announced to take, and how long it would
    /// take one step shorter. Nil for the second when every movement is
    /// already on the floor.
    ///
    /// This is the pair the engine asks to be visible BEFORE the person
    /// agrees: "37 → 26 min". The number is the engine's own
    /// `estimatedTotalMin`, not an app-side estimate — the wave's answer to
    /// "how long will this take" is that the engine announces it.
    func sessionLengthPreview() -> (now: Int, shorter: Int?) {
        let now = Int(nextSession.estimatedTotalMin.rounded())
        let shortened = Engine.shorterSession(state: engineState, steps: 1)
        guard shortened != engineState else { return (now, nil) }
        let after = Int(Engine.generateSession(shortened).estimatedTotalMin.rounded())
        return (now, after < now ? after : nil)
    }

    /// The same pair, measured inside the movements that are actually going
    /// to be performed. With the short version chosen, "34 → 26" is a promise
    /// about a workout nobody is going to do — the handle has to price itself
    /// against the plan on screen, not against the full session behind it.
    func sessionLengthPreview(within plan: Set<Pattern>?) -> (now: Int, shorter: Int?) {
        guard let plan else { return sessionLengthPreview() }
        let now = ShortWorkout.estimatedMin(session: nextSession, plan: plan)
        let shortened = Engine.shorterSession(state: engineState, steps: 1)
        guard shortened != engineState else { return (now, nil) }
        let after = ShortWorkout.estimatedMin(session: Engine.generateSession(shortened),
                                              plan: plan)
        return (now, after < now ? after : nil)
    }

    /// True while any movement in today's plan still has room to lose a set.
    var canMakeSessionShorter: Bool {
        Engine.shorterSession(state: engineState, steps: 1) != engineState
    }

    var isSessionShortened: Bool {
        Pattern.allCases.contains { engineState.cutOf($0) > 0 }
    }
}
