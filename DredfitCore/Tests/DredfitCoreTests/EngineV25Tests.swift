//
//  DredfitCoreTests
//
//  The safety wave: the per-pattern, per-tier growth ceiling and the
//  discomfort input that freezes a pattern. Mirrors the corresponding blocks
//  in the reference verifier — anything asserted here is asserted there too.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV25Tests: XCTestCase {

    /// A state where every pattern sits at the same level, so one session
    /// exercises six patterns at once.
    private func seeded(level: Int, counter: Int = 0) -> EngineState {
        var state = EngineState.initial
        state.counter = counter
        for p in Pattern.allCases { state.levels[p] = level }
        return state
    }

    /// This file is about the growth-cap table and the freeze, so an unnamed
    /// "less" is taken under a run — session-wide delta.
    private func after(_ state: EngineState, _ result: FeedbackResult,
                       overrides: [Pattern: Int] = [:]) -> EngineState {
        Engine.applyFeedback(state: result == .less ? state.underLessRun : state,
                             session: Engine.generateSession(state),
                             result: result, overrides: overrides)
    }

    // MARK: - The table (mechanism)

    /// Every cell the table does not declare falls back to the default, and
    /// the lookup covers the whole level lattice — including the set bands,
    /// which are tier 4 by encoding.
    func testMissingCellsFallBackToTheDefault() {
        for p in Pattern.allCases {
            for level in 0...EngineConfig.levelMax {
                let tier = Level.decode(level).tier
                let declared = EngineConfig.maxUpByPatternTier[p]?[tier]
                XCTAssertEqual(EngineConfig.maxUp(pattern: p, tier: tier),
                               declared ?? EngineConfig.maxUpPerSession,
                               "\(p.rawValue) tier \(tier): cap must follow the table")
            }
        }
    }

    /// The shipped values, cell by cell: calves at every tier, the vertical
    /// push from tier 3, the pull from tier 2 (the fixed slot makes it the
    /// most frequent pattern — issue #76), tier 4 for everyone, two
    /// everywhere else. The reference verifier checks the same table against
    /// the spec.
    func testTheShippedCeilingMatchesTheDeclaredRule() {
        for p in Pattern.allCases {
            for tier in 1...EngineConfig.tiers {
                // The bar branch joins the pull's cells — the cross-credit
                // gives it the slot's full speed, so the frequency argument of
                // #76 reaches it too.
                let slow = p == .calf
                    || (p == .pushV && tier >= 3)
                    || (Pattern.pullSide.contains(p) && tier >= 2)
                    || tier == EngineConfig.tiers
                XCTAssertEqual(EngineConfig.maxUp(pattern: p, tier: tier), slow ? 1 : 2,
                               "\(p.rawValue) tier \(tier)")
            }
        }
    }

    /// The pull's cells are the one frequency argument in the table: the fixed
    /// slot gives it eight appearances where a rotating pattern gets five, so
    /// from the first real row on it is held to a step. Tier 1 is scapular
    /// activation, not a row, and deliberately keeps the default; the bar
    /// branch used to sit at four appearances in eight and went uncapped —
    /// until gave the slot back its full speed through the cross-credit, which
    /// makes the same argument apply to it.
    func testThePullIsHeldToAStepFromTierTwo() {
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 1), 2, "tier 1 keeps the default")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 2), 1, "the inverted row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 3), 1, "the feet-elevated row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 2), 1, "the bar branch is capped alongside the row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 3), 1, "the bar branch is capped alongside the row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 1), 2, "the hang keeps the default")

        // "More" at a tier-2 level takes one step, not two; "on plan" is never
        // capped, so the pull still moves every session. The cell counts
        // SUB-STEPS, so all three land on positions rather than on levels. The
        // subject is untouched.
        assertPosition(after(seeded(level: 10), .more), .pull,
                       Level.rise(level: 10, sub: 0, by: 1), "the collateral +2 is gone")
        assertPosition(after(seeded(level: 10), .plan), .pull,
                       Level.rise(level: 10, sub: 0, by: 1),
                       "one step per session survives the cap")
        assertPosition(after(seeded(level: 4), .more), .pull,
                       Level.rise(level: 4, sub: 0, by: 2), "tier 1 still climbs by two")
    }

    /// The set bands are covered by the tier-4 cell rather than a special case.
    func testSetBandsAreTierFour() {
        for level in [24, 31, 32, 39, 40, 47] {
            XCTAssertEqual(Level.decode(level).tier, 4, "level \(level) is tier 4")
        }
    }

    // MARK: - The ceiling in applyFeedback

    /// "More" climbs by the cell, never past it, at every level. Re-marked.
    /// The cell counts SUB-STEPS — a "2" means two sub-steps, not two levels —
    /// so the expectation is derived from the same helper the engine uses. The
    /// subject (the cell governs the climb) stands.
    func testMoreClimbsByTheCell() {
        for level in 0...EngineConfig.levelMax {
            let state = seeded(level: level)
            let next = after(state, .more)
            for ex in Engine.generateSession(state).exercises {
                let cap = EngineConfig.maxUp(pattern: ex.pattern,
                                             tier: Level.decode(level).tier)
                assertPosition(next, ex.pattern,
                               Level.rise(level: level, sub: 0,
                                          by: min(EngineConfig.deltaMore, cap)),
                               "\(ex.pattern.rawValue) from \(level) with cap \(cap)")
            }
        }
    }

    /// A pointed fact far above the plan is clamped by the same cell. In
    /// SUB-STEPS.
    func testAFactIsClampedByTheCell() {
        for level in 1...EngineConfig.levelMax {
            let state = seeded(level: level)
            let cap = EngineConfig.maxUp(pattern: .pull, tier: Level.decode(level).tier)
            let next = after(state, .plan, overrides: [.pull: 99])
            assertPosition(next, .pull, Level.rise(level: level, sub: 0, by: cap),
                           "an enormous fact from \(level) is capped at +\(cap) sub-steps")
        }
    }

    /// Calibration outranks the ceiling: from zero there is no achieved level
    /// to grow from, only the honest fact of the first workout.
    func testCalibrationFromZeroIgnoresTheCeiling() {
        let state = EngineState.initial
        let next = after(state, .plan, overrides: [.pull: 20])
        XCTAssertEqual(next.levels[.pull], 12,
                       "a fact of 20 reps from zero still calibrates straight to 12")
    }

    /// Downward moves are never capped, and the deload still fires on the
    /// third shortfall in a row.
    func testTheCeilingNeverActsDownwards() {
        var state = seeded(level: 10)
        var lastEntry = state.position(.pull)
        for _ in 0..<3 {
            lastEntry = state.position(.pull)
            state = after(state, .less)
        }
        // The subject — the ceiling never bounds a descent, and the deload
        // still fires on the third shortfall — is untouched; both figures
        // changed unit. The old 4 was 10 − 1 − 1 − 1 − 3, three level-wise
        // "less" plus an ungated deload, and it landed `pull` on tier 1 × 12
        // reps where the plan had asked for 3×7 — the deload made the work 71
        // % heavier. Now the roll-back goes through the gate.
        assertPosition(state, .pull, expectedDeload(.pull, from: lastEntry),
                       "one sub-step, one sub-step, then the gated deload")
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: 10, to: state.levels[.pull]!, fromCut: 0, toCut: 0),
                      "a deload on top of a ceiling-1 cell may not make the plan heavier")
        XCTAssertEqual(state.failStreak[.pull], 0, "the deload resets the streak")
    }

    /// "On plan" is a step, whatever the cell allows.
    func testOnPlanIsAlwaysOneStep() {
        let next = after(seeded(level: 3), .plan)
        for ex in Engine.generateSession(seeded(level: 3)).exercises {
            // One step is one SUB-STEP.
            assertPosition(next, ex.pattern, Level.rise(level: 3, sub: 0, by: 1),
                           "\(ex.pattern.rawValue)")
        }
    }

    // SNIPPED: eleven tests of — the discomfort input and the freeze it armed.
    // `applyFeedback` has no `discomfort` argument and the state has no
    // `frozen`, so none of them has an input any more.
    //
    // — the growth-cap table, which is what the rest of this suite is about —
    // is untouched by the wave and stays here in full.
    //
    // NOT LOST: "a skip does not spend an appearance" was the one claim here
    // that outlived its mechanism. It is the invariant "a per-pattern counter
    // ticks in APPEARANCES, not sessions", and it now lives on `setsHold` —
    // asserted in EngineV225Tests and swept by the reference's block 33.
}
