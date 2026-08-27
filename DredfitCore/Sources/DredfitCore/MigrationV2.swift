//
//  §41.7: reading a state written by an engine before v3.
//
//  REVERSES the §40.8 decision "there is no migration" (owner, 26.08.2026).
//  The reason was not the reset itself but that the mechanism the decision
//  counted on never reached the person: the one line in the app explaining
//  how to enter facts shows only when the journal is EMPTY, and an upgrading
//  trainee's journal is intact — by the same paragraph's decision. They never
//  saw it once. Alongside the rungs, `hasBar` and `counter` were lost too,
//  and neither carries progress.
//
//  Mirrors `migrateFromV2` in the reference engine. The golden fixture does NOT
//  pin it, contrary to what this header used to claim: `make_golden.js` seeds
//  scenario `migration_v2` with the OUTPUT of the reference migration, and
//  `GoldenTests.seedState` replays that output field by field instead of
//  calling this function — so the fixture pins what happens AFTER an upgrade
//  and never the upgrade itself. The two tables below are pinned by tests
//  instead: `MigrationV2Tests+Table` compares them cell by cell against a
//  second, independent transcription of the v2 format, and `MigrationV2Tests`
//  sweeps all 480 cells for real work (`sets × dose × sides`) on both sides of
//  the jump. Before those existed, replacing a whole row here with
//  `[1, 1, 1, 1]` — every upgrading trainee thrown back to the first rung of
//  every movement — left the entire suite green.
//

import Foundation

public extension Engine {

    /// v2 tier → v3 variation. Baked as data, not derived: the v2 library does
    /// not exist at runtime. Thirty-four of forty positions matched by MOVEMENT
    /// NAME; six were decided by the owner (§41.7) — two are renames, three
    /// moved into the warm-up, one was removed outright. Order is preserved by
    /// cascade: a higher v2 tier never lands below a lower one.
    static let v2TierToVariation: [Pattern: [Int]] = [
        .squat: [1, 3, 5, 6],
        .pushH: [1, 3, 4, 6],
        .hinge: [1, 2, 3, 4],
        .pull: [1, 4, 5, 7],
        .pushV: [1, 4, 5, 7],
        .lunge: [1, 2, 3, 4],
        .coreAntiExt: [1, 3, 4, 5],
        .coreRot: [1, 3, 4, 5],
        .calf: [1, 3, 4, 5],
        .pullBar: [1, 5, 6, 7],
    ]

    /// A SNAPSHOT of a removed format. v2's `decodeLevel` was a pure function of
    /// L ∈ [0, 47], so its forty-eight rows are baked here rather than dragging
    /// live copies of dead tables (`repStart`, `repStartBand`, `holdLadderFor`)
    /// into v3. A row is [tier, sets, reps, seconds]. Taken from
    /// `adaptive_engine.v2.27-baseline.js`, checked across all 48 values.
    static let v2LevelTable: [[Int]] = [
        [1,3,8,20], [1,3,9,22], [1,3,10,24], [1,3,11,26], [1,3,12,29], [1,3,13,32],
        [1,3,14,35], [1,3,15,39], [2,3,6,15], [2,3,7,17], [2,3,8,19], [2,3,9,21],
        [2,3,10,23], [2,3,11,25], [2,3,12,28], [2,3,13,31], [3,3,5,15], [3,3,6,17],
        [3,3,7,19], [3,3,8,21], [3,3,9,23], [3,3,10,25], [3,3,11,28], [3,3,12,31],
        [4,3,4,10], [4,3,5,11], [4,3,6,12], [4,3,7,13], [4,3,8,14], [4,3,9,15],
        [4,3,10,17], [4,3,11,19], [4,4,6,20], [4,4,7,23], [4,4,8,26], [4,4,9,29],
        [4,4,10,32], [4,4,11,35], [4,4,12,38], [4,4,13,41], [4,5,8,24], [4,5,9,27],
        [4,5,10,30], [4,5,11,33], [4,5,12,36], [4,5,13,39], [4,5,14,42], [4,5,15,45],
    ]

    /// What a v2 state carries, as far as v3 needs to read it.
    struct V2State {
        public var counter: Int
        public var hasBar: Bool
        public var levels: [Pattern: Int]
        public var failStreak: [Pattern: Int]
        public init(counter: Int, hasBar: Bool,
                    levels: [Pattern: Int], failStreak: [Pattern: Int] = [:]) {
            self.counter = counter
            self.hasBar = hasBar
            self.levels = levels
            self.failStreak = failStreak
        }
    }

    /// Returns a v3 state, or nil when the input does not look like v2 —
    /// nil means "this is not v2", never "migrate into nothing".
    static func migrateFromV2(_ old: V2State) -> EngineState? {
        guard !old.levels.isEmpty else { return nil }
        var next = EngineState.initial
        next.counter = EngineState.clamped(old.counter, 0, EngineConfig.countMax)
        next.hasBar = old.hasBar
        for p in Pattern.allCases {
            guard let row = v2TierToVariation[p], let level = old.levels[p] else { continue }
            let entry = v2LevelTable[EngineState.clamped(level, 0, v2LevelTable.count - 1)]
            let (tier, v2sets, v2reps, v2hold) = (entry[0], entry[1], entry[2], entry[3])
            let v = Library.index(pattern: p, variation: row[EngineState.clamped(tier, 1, row.count) - 1])
            let unit = Library.unit(p, v)
            // The grid is the same (reps 4…15, holds 15…45), so the dose carries
            // over with a snap down and a clamp. Where v2 could hand out a dose
            // below v3's floor (a 10-second hold), the trainee comes UP to the
            // floor — there is nothing lower in the product to land on
            // (accepted gap §41.6 item 4, ten cells of 480, worst ×1.50).
            let dose = Dose.clamped(unit, Dose.snap(unit, unit == .hold ? v2hold : v2reps))
            next.vars[p] = v
            next.doses[p] = dose
            // Sets bands live only on the top variation (§40.5): carrying one
            // lower would silently build an unreachable state.
            if v2sets > EngineConfig.setsBase && Library.isTop(p, v) {
                next.sets[p] = EngineState.clamped(v2sets, EngineConfig.setsBase, Engine.setsCeil(p, v))
            }
            // The journal: they really did do this dose in this variation, or
            // they would never have reached it. Without the record the very
            // first descent would send them to the floor.
            next.shown[p, default: [:]][v] = dose
            next.failStreak[p] = EngineState.clamped(old.failStreak[p] ?? 0,
                                                     0, EngineConfig.failsToDeload - 1)
        }
        return next
    }
}
