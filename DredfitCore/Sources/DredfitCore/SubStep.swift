//
//  SubStep.swift
//  DredfitCore
//
//  v2.22 (spec §33): the sub-step. One rung of a level used to add its dose to
//  ALL the sets at once — a median of +11 % more work per growth event, up to
//  +25 % on reps. A sub-step splits that rung across the sets: growth takes one
//  set at a time, so a plan that overshoots its owner's capacity costs one rep
//  in one set instead of a whole level.
//
//  Everything here is integer arithmetic over one monotone scale, so "N
//  sub-steps up", "how far did we come" and "no higher than the cap" answer
//  identically in both implementations — no walking a loop and accumulating
//  drift, and no dependence on a platform's rounding mode.
//

import Foundation

/// A pattern's place on the progression: the level, how many of its sets
/// already carry the next rung's dose, and — since v2.25 (spec §36.3) — how
/// many sets have been taken off it.
///
/// The third coordinate defaults to zero so every pre-v2.25 construction still
/// reads as it did: a position that never met the sets handle IS a position
/// with an empty cut, and the plan it produces is bit-for-bit v2.24's.
public struct Position: Equatable, Sendable {
    public let level: Int
    public let sub: Int
    public let cut: Int

    public init(level: Int, sub: Int, cut: Int = 0) {
        self.level = level
        self.sub = sub
        self.cut = cut
    }
}

extension Level {

    /// The top rung of a tier or a set band, where the sub-step is DISABLED:
    /// rung `L+1` there is already a different variation (or a different band,
    /// or — on `pullBar` — a different unit), and mixing two variations inside
    /// one exercise is forbidden. Without the rule 110 of 1680 cells would ask
    /// for two different exercises in one session slot.
    public static func subDisabled(at level: Int) -> Bool {
        min(max(level, 0), EngineConfig.levelMax) % EngineConfig.stepsPerTier
            == EngineConfig.stepsPerTier - 1
    }

    /// How many growth events it takes to LEAVE level `L`: one per set, or a
    /// single one on the top rung, which goes straight to `L+1`.
    public static func subSteps(at level: Int) -> Int {
        subDisabled(at: level) ? 1 : decode(level).sets
    }

    /// The sub-step actually in force: garbage, the top rung, and a set count
    /// trimmed below the level's own band all collapse to a uniform plan. Pass
    /// `sets` when the exercise shows fewer sets than its band (the §20.2 gate
    /// or the §28.3 budget) — a sub-step can never ask for more sets than are
    /// on screen.
    public static func effectiveSub(level: Int, sub: Int, sets: Int? = nil) -> Int {
        guard !subDisabled(at: level) else { return 0 }
        let top = max(0, (sets ?? decode(level).sets) - 1)
        return min(max(sub, 0), top)
    }

    /// Cumulative sub-steps from the bottom of the scale to the start of each
    /// level. Monotone by construction — the whole point of keeping a table.
    /// Its last entry is the height of the scale: 153 sub-steps against 48
    /// levels.
    static let subOrdinalTable: [Int] = {
        var out = [0]
        out.reserveCapacity(EngineConfig.levelMax + 2)
        for level in 0...EngineConfig.levelMax { out.append(out[level] + subSteps(at: level)) }
        return out
    }()

    /// The scale's ceiling is the position `(levelMax, 0)`: there is nothing
    /// above it to grow into, and the top rung has no sub-steps of its own.
    static var subOrdinalMax: Int { subOrdinalTable[EngineConfig.levelMax] }

    /// Where a position sits on the scale.
    public static func ordinal(_ position: Position) -> Int {
        let level = min(max(position.level, 0), EngineConfig.levelMax)
        return subOrdinalTable[level]
            + effectiveSub(level: level, sub: position.sub)
    }

    public static func ordinal(level: Int, sub: Int) -> Int {
        ordinal(Position(level: level, sub: sub))
    }

    /// The inverse: which position an ordinal names.
    public static func position(atOrdinal ordinal: Int) -> Position {
        let o = min(max(ordinal, 0), subOrdinalMax)
        var level = 0
        while level < EngineConfig.levelMax, subOrdinalTable[level + 1] <= o { level += 1 }
        return Position(level: level, sub: o - subOrdinalTable[level])
    }

    /// A growth event is ONE sub-step: `sub += 1`, and at `sub == sets(L)` the
    /// level rises and the sub-step returns to zero. On a tier's top rung one
    /// event goes straight to `L+1, sub = 0`.
    public static func rise(level: Int, sub: Int, by count: Int) -> Position {
        position(atOrdinal: ordinal(level: level, sub: sub) + max(0, count))
    }

    /// How far one position lies above another, in sub-steps; zero when the
    /// target is not above.
    public static func subRise(from: Position, to: Position) -> Int {
        max(0, ordinal(to) - ordinal(from))
    }

    /// v2.23 (spec §34.1): the evaluative descent — `count` sub-steps BACK
    /// along the very path growth took, with a floor at the bottom of the
    /// level's own block. Exactly the reverse of a growth event (§33.3):
    /// `(L, sub>0)` → `(L, sub−1)`; `(L, 0)` → `(L−1, sets(L−1)−1)`; and on a
    /// block floor the position does not move at all — nothing lighter exists
    /// inside this variation, and changing the variation is not the rating's
    /// to make (§15.2 reserves it for pain and for the deload).
    ///
    /// This cannot make a plan heavier BY CONSTRUCTION rather than by check:
    /// inside a block the variation, the unit, the band and the sides are all
    /// the same, and total work is strictly monotone along the growth path
    /// (§33.9, block "b"). The `noHarder` gate is therefore not a filter here
    /// but a statement about the result, and it lives in the tests.
    public static func descend(level: Int, sub: Int, by count: Int) -> Position {
        position(atOrdinal: max(ordinal(level: level, sub: sub) - max(0, count),
                                ordinal(level: bandFloor(level), sub: 0)))
    }

    /// The dose a level asks for, in its own unit — the number the plan shows.
    public static func dose(pattern: Pattern, level: Int) -> Int {
        let d = decode(level)
        let entry = ExerciseLibrary.entry(for: pattern)
        return entry.unit(forTier: d.tier) == .reps ? d.reps : d.hold
    }

    /// What ONE sub-step adds: the dose of rung `L+1` less the dose of `L`.
    /// Only ever asked where sub-steps are enabled, so `L+1` is guaranteed to
    /// be the same tier, the same band, the same variation and the same unit.
    public static func subDelta(pattern: Pattern, level: Int) -> Int {
        guard !subDisabled(at: level) else { return 0 }
        return dose(pattern: pattern, level: level + 1) - dose(pattern: pattern, level: level)
    }

    /// Per-set doses, in DESCENDING order: the first `sub` sets carry the next
    /// rung's dose. A uniform plan answers `nil` — "nothing to say" — which is
    /// exactly what `SessionExercise.loads` being optional means, and what lets
    /// a journal written before v2.22 decode without a migration.
    public static func perSetLoads(pattern: Pattern, level: Int, sub: Int, sets: Int) -> [Int]? {
        let s = effectiveSub(level: level, sub: sub, sets: sets)
        guard s > 0 else { return nil }
        let base = dose(pattern: pattern, level: level)
        let high = base + subDelta(pattern: pattern, level: level)
        return (0..<sets).map { $0 < s ? high : base }
    }
}
