//
//  §41.7: the two baked tables the v2 → v3 migration is made of, checked
//  against values that do NOT come out of those tables.
//
//  DO NOT "SIMPLIFY" THIS FILE by reading the expectations back from
//  `Engine.v2TierToVariation` / `Engine.v2LevelTable`. Taking the expectation
//  from the thing under test is the exact defect this file exists to remove:
//  until it was written, the only test that touched the mapping read its
//  expectation out of the mapping (`CleanStartTests` did
//  `Engine.v2TierToVariation[p]?[3]`), so it could not fail. `GoldenTests`
//  does not close the gap either — `make_golden.js` seeds the `migration_v2`
//  scenario with the OUTPUT of the reference `migrateFromV2`, and `seedState`
//  replays that output field by field instead of calling
//  `Engine.migrateFromV2`. Rewriting every row of `v2TierToVariation` to
//  `[1, 1, 1, 1]` — every upgrading trainee thrown back to the first rung of
//  every movement — left the whole suite green.
//
//  The values below were transcribed by hand from the local reference
//  sources: `V2_TIER_TO_VAR` and `V2_LEVEL_TABLE` in `adaptive_engine.js`
//  (§41.7), and `LIBRARY` in `adaptive_engine.v2.27-baseline.js` for what v2
//  itself did at each (pattern, tier).
//

import XCTest
import DredfitCore

/// The removed v2 format, as data. v2's library and its level arithmetic are
/// gone from the runtime, so there is nothing in the shipping code that could
/// serve as the other side of these comparisons — a second, independent copy
/// is the only measure available, and that is why it is duplicated on purpose.
enum V2FormatSnapshot {

    /// v2's `decodeLevel` flattened: one row per level L ∈ [0, 47], each
    /// `[tier, sets, reps, seconds]`. Produced by evaluating `decodeLevel(L)`
    /// for all forty-eight levels of `adaptive_engine.v2.27-baseline.js`.
    static let levelTable: [[Int]] = [
        [1, 3, 8, 20], [1, 3, 9, 22], [1, 3, 10, 24], [1, 3, 11, 26], [1, 3, 12, 29], [1, 3, 13, 32],
        [1, 3, 14, 35], [1, 3, 15, 39], [2, 3, 6, 15], [2, 3, 7, 17], [2, 3, 8, 19], [2, 3, 9, 21],
        [2, 3, 10, 23], [2, 3, 11, 25], [2, 3, 12, 28], [2, 3, 13, 31], [3, 3, 5, 15], [3, 3, 6, 17],
        [3, 3, 7, 19], [3, 3, 8, 21], [3, 3, 9, 23], [3, 3, 10, 25], [3, 3, 11, 28], [3, 3, 12, 31],
        [4, 3, 4, 10], [4, 3, 5, 11], [4, 3, 6, 12], [4, 3, 7, 13], [4, 3, 8, 14], [4, 3, 9, 15],
        [4, 3, 10, 17], [4, 3, 11, 19], [4, 4, 6, 20], [4, 4, 7, 23], [4, 4, 8, 26], [4, 4, 9, 29],
        [4, 4, 10, 32], [4, 4, 11, 35], [4, 4, 12, 38], [4, 4, 13, 41], [4, 5, 8, 24], [4, 5, 9, 27],
        [4, 5, 10, 30], [4, 5, 11, 33], [4, 5, 12, 36], [4, 5, 13, 39], [4, 5, 14, 42], [4, 5, 15, 45],
    ]

    /// v2 tier (1…4) → v3 variation, indexed `[tier - 1]`. Forty cells: this
    /// is the whole of what an upgrade decides about where a person stands.
    static let tierToVariation: [Pattern: [Int]] = [
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

    /// `LIBRARY[p].unilateral` in v2: did v2 train this (pattern, tier) one
    /// side at a time. Without this column no measure built out of v3 alone
    /// can see the worst thing an upgrade could do — land a two-sided tier on
    /// a one-sided rung, which is real work ×2 at an unchanged rep count.
    static let unilateral: [Pattern: [Bool]] = [
        .squat: [false, true, true, true],
        .pushH: [false, false, false, true],
        .hinge: [false, true, true, false],
        .pull: [false, false, false, true],
        .pushV: [false, false, false, false],
        .lunge: [true, true, true, true],
        .coreAntiExt: [false, false, false, false],
        .coreRot: [true, true, true, true],
        .calf: [false, true, true, true],
        .pullBar: [false, false, false, false],
    ]

    /// `LIBRARY[p].unit` / `.units` in v2. Only `pull_bar` changed unit along
    /// its own ladder (a hang, then reps), which is why v2 carried a per-tier
    /// array for it alone.
    static let unit: [Pattern: [LoadUnit]] = [
        .squat: [.reps, .reps, .reps, .reps],
        .pushH: [.reps, .reps, .reps, .reps],
        .hinge: [.reps, .reps, .reps, .reps],
        .pull: [.reps, .reps, .reps, .reps],
        .pushV: [.reps, .reps, .reps, .reps],
        .lunge: [.reps, .reps, .reps, .reps],
        .coreAntiExt: [.hold, .hold, .hold, .hold],
        .coreRot: [.hold, .hold, .hold, .hold],
        .calf: [.reps, .reps, .reps, .reps],
        .pullBar: [.hold, .reps, .reps, .reps],
    ]

    /// What one v2 session at level `L` really cost: `sets × dose × sides`, in
    /// v2's own unit and v2's own sidedness. This is the same quantity
    /// `Engine.planLoad` computes for v3 (`Descent.swift`), which is internal
    /// and deliberately stays that way — a measure widened to `public` for a
    /// test is a production change, so the test brings its own instead.
    static func work(_ pattern: Pattern, level: Int) throws -> Int {
        let raw = try XCTUnwrap(levelTable[checked: level],
                                "L=\(level) is outside v2's forty-eight levels")
        let wellFormed: [Int]? = raw.count == 4 ? raw : nil
        let row = try XCTUnwrap(wellFormed,
                                "L=\(level): a v2 row is [tier, sets, reps, seconds]")
        let tier = row[0]
        let units = try XCTUnwrap(unit[pattern], "\(pattern.rawValue) has no unit column in the v2 snapshot")
        let sides = try XCTUnwrap(unilateral[pattern], "\(pattern.rawValue) has no sidedness in the v2 snapshot")
        let tierUnit = try XCTUnwrap(units[checked: tier - 1],
                                     "\(pattern.rawValue) has no tier \(tier) in the v2 unit column")
        let tierPerSide = try XCTUnwrap(sides[checked: tier - 1],
                                        "\(pattern.rawValue) has no tier \(tier) in the v2 sidedness column")
        return row[1] * (tierUnit == .hold ? row[3] : row[2]) * (tierPerSide ? 2 : 1)
    }
}

/// Bounds-checked read. A mis-transcribed snapshot must fail as a NAMED
/// assertion; an out-of-range crash takes the whole suite's report with it and
/// reads as an infrastructure problem rather than as this file's finding.
private extension Array {
    subscript(checked index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class MigrationV2TableTests: XCTestCase {

    private let v2Tiers = 1...4

    // MARK: - The forty cells that decide where an upgrade lands

    func test_v2TierToVariation_everyCell_matchesTheIndependentSnapshot() throws {
        XCTAssertEqual(Set(Engine.v2TierToVariation.keys), Set(Pattern.allCases),
                       "every pattern must be migrated: one missing row means that movement is left behind")
        for pattern in Pattern.allCases {
            let shipped = try XCTUnwrap(Engine.v2TierToVariation[pattern],
                                        "\(pattern.rawValue) has no row in the shipped table")
            let expected = try XCTUnwrap(V2FormatSnapshot.tierToVariation[pattern],
                                         "\(pattern.rawValue) has no row in the snapshot")
            XCTAssertEqual(shipped, expected,
                           "\(pattern.rawValue): the four rungs an upgrade lands on, tier 1…4")
        }
    }

    /// The one property whose loss is invisible to any v3-only measure: v2's
    /// sidedness must survive the jump. A bilateral tier landing on a
    /// unilateral rung keeps the rep count and doubles the session.
    func test_v2TierToVariation_everyMappedRung_keepsTheSidednessOfTheTierItReplaces() throws {
        for pattern in Pattern.allCases {
            let row = try XCTUnwrap(Engine.v2TierToVariation[pattern],
                                    "\(pattern.rawValue) has no row in the shipped table")
            let wasPerSide = try XCTUnwrap(V2FormatSnapshot.unilateral[pattern],
                                           "\(pattern.rawValue) has no sidedness in the snapshot")
            for tier in v2Tiers {
                let variation = try XCTUnwrap(row[checked: tier - 1],
                                              "\(pattern.rawValue) has no tier \(tier)")
                let wasUnilateral = try XCTUnwrap(wasPerSide[checked: tier - 1],
                                                  "\(pattern.rawValue) has no tier \(tier) in the snapshot")
                let expected = wasUnilateral ? 2 : 1
                XCTAssertEqual(Library.sides(pattern, variation), expected,
                               "\(pattern.rawValue) tier \(tier) lands on variation \(variation): "
                               + "v2 trained it on \(expected) side(s), and changing that scales "
                               + "the real work by two in one direction or the other")
            }
        }
    }

    /// The dose is carried over as a NUMBER (`MigrationV2.swift`), so the unit
    /// that number is spoken in has to be the same on both sides. Nine reps
    /// read as nine seconds is not a migration, it is a different workout.
    func test_v2TierToVariation_everyMappedRung_keepsTheUnitOfTheTierItReplaces() throws {
        for pattern in Pattern.allCases {
            let row = try XCTUnwrap(Engine.v2TierToVariation[pattern],
                                    "\(pattern.rawValue) has no row in the shipped table")
            let wasUnit = try XCTUnwrap(V2FormatSnapshot.unit[pattern],
                                        "\(pattern.rawValue) has no unit column in the snapshot")
            for tier in v2Tiers {
                let variation = try XCTUnwrap(row[checked: tier - 1],
                                              "\(pattern.rawValue) has no tier \(tier)")
                let expected = try XCTUnwrap(wasUnit[checked: tier - 1],
                                             "\(pattern.rawValue) has no tier \(tier) in the snapshot")
                XCTAssertEqual(Library.unit(pattern, variation), expected,
                               "\(pattern.rawValue) tier \(tier) lands on variation \(variation): "
                               + "the dose crosses as a bare number, so the unit must not change under it")
            }
        }
    }

    /// The cascade §41.7 promises: a higher v2 tier never lands below a lower
    /// one, and no cell points past the end of its ladder. `Library.index`
    /// CLAMPS rather than traps, so an out-of-range cell would be swallowed in
    /// silence and land the trainee on the top rung of a movement they never
    /// did.
    func test_v2TierToVariation_everyRow_risesStrictlyAndStaysInsideItsLadder() throws {
        for pattern in Pattern.allCases {
            let row = try XCTUnwrap(Engine.v2TierToVariation[pattern],
                                    "\(pattern.rawValue) has no row in the shipped table")
            XCTAssertEqual(row.count, v2Tiers.count,
                           "\(pattern.rawValue): v2 had exactly four tiers, and each needs a landing")
            for tier in v2Tiers {
                let variation = try XCTUnwrap(row[checked: tier - 1],
                                              "\(pattern.rawValue) has no tier \(tier)")
                XCTAssertGreaterThanOrEqual(variation, 1,
                                            "\(pattern.rawValue) tier \(tier): variations are 1-based")
                XCTAssertLessThanOrEqual(variation, Library.count(pattern),
                                         "\(pattern.rawValue) tier \(tier): variation \(variation) is past "
                                         + "the end of a \(Library.count(pattern))-rung ladder")
                if tier > 1 {
                    let below = try XCTUnwrap(row[checked: tier - 2],
                                              "\(pattern.rawValue) has no tier \(tier - 1)")
                    XCTAssertGreaterThan(variation, below,
                                         "\(pattern.rawValue): tier \(tier) must land above tier \(tier - 1), "
                                         + "or two v2 tiers collapse onto one rung")
                }
            }
        }
    }

    // MARK: - The forty-eight rows of the removed level format

    func test_v2LevelTable_allFortyEightRows_matchTheIndependentSnapshot() throws {
        XCTAssertEqual(Engine.v2LevelTable.count, V2FormatSnapshot.levelTable.count,
                       "v2 encoded L ∈ [0, 47]: a shorter table clamps real levels onto the wrong row")
        for level in V2FormatSnapshot.levelTable.indices {
            let shipped = try XCTUnwrap(Engine.v2LevelTable[checked: level],
                                        "L=\(level) is missing from the shipped table")
            XCTAssertEqual(shipped, V2FormatSnapshot.levelTable[level],
                           "L=\(level): [tier, sets, reps, seconds] as v2's decodeLevel produced them")
        }
    }

    /// §40.5: bands of 4 and 5 sets exist ONLY on the top rung of a ladder.
    /// v2 had them above tier 4 regardless, so the band may only ride along
    /// where the landing rung happens to be the top — carrying one lower
    /// builds a state the engine can never reach again, and the trainee would
    /// be stuck with sets no handle can give back.
    func test_migration_whenAV2BandLandsBelowTheTopRung_dropsTheBandInsteadOfBuildingAnUnreachableState() throws {
        for pattern in Pattern.allCases {
            let row = try XCTUnwrap(V2FormatSnapshot.tierToVariation[pattern],
                                    "\(pattern.rawValue) has no row in the snapshot")
            for level in V2FormatSnapshot.levelTable.indices {
                let snapshotRow = V2FormatSnapshot.levelTable[level]
                let tier = try XCTUnwrap(snapshotRow[checked: 0], "L=\(level) has no tier column")
                let v2sets = try XCTUnwrap(snapshotRow[checked: 1], "L=\(level) has no sets column")
                let variation = try XCTUnwrap(row[checked: tier - 1],
                                              "\(pattern.rawValue) has no tier \(tier)")
                let migrated = try XCTUnwrap(
                    Engine.migrateFromV2(Engine.V2State(counter: 1, hasBar: true,
                                                        levels: [pattern: level])),
                    "a state carrying one level is still a v2 state")
                let isTop = Library.isTop(pattern, variation)
                let expected: Int? = v2sets > EngineConfig.setsBase && isTop ? v2sets : nil
                XCTAssertEqual(migrated.sets[pattern], expected,
                               "\(pattern.rawValue) L=\(level): v2 planned \(v2sets) sets and the landing "
                               + "rung \(variation) is \(isTop ? "the top" : "not the top") of its ladder")
            }
        }
    }
}
