//
//  Descent.swift
//  DredfitCore
//
//  Where a session RATING takes a pattern, and what the failure streak does
//  with it. Split out of Engine.swift in v2.23 (spec §34), when the rating
//  path stopped being a one-line clamp and became a rule of its own.
//
//  Until v2.23 the rating was the last descent WITHOUT a gate: it went by
//  whole levels and crossed a tier boundary freely, landing in the middle of
//  the tier below, where the dose is higher. The deload was the second such
//  path. Both are closed here; the exact-fact path (`positionFromPointFact`)
//  is untouched and stays in Engine.swift, where the rest of the fact rules
//  live.
//

import Foundation

extension Engine {

    /// Where a session-wide RATING lands a pattern (spec §5, §19.1, §26.1,
    /// §28.4).
    ///
    /// "More" runs through the same ceiling; downward moves never do. A
    /// targeted "less" reaches its aim only and every other movement holds —
    /// holding is not underperforming. A chronic aim takes a double step, or
    /// the descent to a manageable level costs 31 appearances while "less"
    /// grinds down the healthy movements. And while the comeback window is
    /// open "more" is credited as "plan": the levels came back, the tissue did
    /// not.
    ///
    /// v2.22 (spec §33): up by SUB-STEPS.
    /// v2.23 (spec §34.1): and down by them too. The evaluative descent steps
    /// one sub-step back along the growth path and never crosses the floor of
    /// its own block: until v2.23 it went by whole levels and landed in the
    /// MIDDLE of the tier below, where the dose is higher — `coreAntiExt`
    /// 24 → 23 meant 3×10 s → 3×31 s, `hinge` 24 → 23 meant 3×4 → 3×12 across
    /// both legs. The §25.3 gate never saw it: the gate stands on the exact-fact
    /// path, and the rating path was the one descent without it (§30.3).
    /// `chronicStep` is the same descent at a double step — two sub-steps.
    ///
    /// The second return value is the INTENT to descend, which is what feeds
    /// the failure streak (§34.2): on a block floor the position does not move,
    /// and without the intent "hard" would be an inert tap there — no streak,
    /// no deload, and no way out of a variation that is beyond its owner.
    static func positionFromRating(
        pattern p: Pattern, result: FeedbackResult, from entry: Position,
        cap: Int, rampLeft: Int, lessTargets: Set<Pattern>?, chronic: Set<Pattern>
    ) -> (position: Position, wantedDown: Bool) {
        let effective: FeedbackResult = rampLeft > 0 && result == .more ? .plan : result
        let sessionDelta: Int
        if let targets = lessTargets {
            sessionDelta = targets.contains(p)
                ? (chronic.contains(p) ? EngineConfig.chronicStep : EngineConfig.deltaLess)
                : 0
        } else {
            sessionDelta = effective.delta
        }
        let rampCap = rampLeft > 0 ? min(cap, EngineConfig.deltaPlan) : cap
        if sessionDelta > 0 {
            return (Level.rise(level: entry.level, sub: entry.sub,
                               by: min(sessionDelta, rampCap)), false)
        }
        if sessionDelta < 0 {
            return (Level.descend(level: entry.level, sub: entry.sub, by: -sessionDelta), true)
        }
        return (entry, false)   // holds
    }

    /// The failure streak and the deload it leads to.
    ///
    /// v2.22 (spec §33): on the exact-fact path the streak reads the LEVEL,
    /// not the position. Giving up sub-steps without losing a level is not a
    /// shortfall — otherwise a descent from `(L, 2)` to `(L, 0)` would start
    /// the count toward a deload, while the work has fallen by exactly what
    /// was not done.
    /// v2.23 (spec §34.2): on the rating path the streak is fed by the INTENT
    /// instead — on a block floor the position cannot move, and a streak that
    /// waited for movement would leave the deload, the only way out of that
    /// variation, permanently out of reach. Holding (§19.1) is not an intent
    /// and still clears the streak.
    ///
    /// v2.23 (spec §34.3): the deload passes the "no harder" gate for the
    /// first time. Until now it was the second descent (after the rating) with
    /// no gate at all, and it dropped `coreAntiExt` from 24 to 21, that is
    /// from 3×10 s to 3×31 s. The gate pulls the landing down to the floor of
    /// the tier below on its own. The roll-back starts from a different level
    /// on the two paths (`deloadFrom`): the rating never moved the level — it
    /// moved the position — so it counts from the entry level; a fact has
    /// already been named by the athlete, and a deload may not land above
    /// their own number, so there it stays v2.22's.
    static func tickStreak(
        _ next: inout EngineState, pattern p: Pattern, entryStreak: Int,
        landed: Position, entry: Position, wentDown: Bool, deloadFrom: Int
    ) -> Position {
        guard wentDown else {
            next.failStreak[p] = 0
            return landed
        }
        let streak = entryStreak + 1
        guard streak >= EngineConfig.failsToDeload else {
            next.failStreak[p] = streak
            return landed
        }
        next.failStreak[p] = 0
        let target = min(max(deloadFrom - EngineConfig.deloadDrop, 0), EngineConfig.levelMax)
        // A deload is a descent, so the sub-step goes with it.
        return Position(level: Level.descendNoHarder(pattern: p, from: entry.level,
                                                     factLevel: target, fromSub: entry.sub),
                        sub: 0)
    }
}
