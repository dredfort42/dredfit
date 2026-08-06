//
//  EngineV25Tests.swift
//  DredfitCoreTests
//
//  The safety wave: the per-pattern, per-tier growth ceiling. Mirrors the
//  corresponding blocks in the reference verifier — anything asserted here is
//  asserted there too.
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

    private func after(_ state: EngineState, _ result: FeedbackResult,
                       overrides: [Pattern: Int] = [:]) -> EngineState {
        Engine.applyFeedback(state: state, session: Engine.generateSession(state),
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

    /// The set bands are covered by the tier-4 cell rather than a special case.
    func testSetBandsAreTierFour() {
        for level in [24, 31, 32, 39, 40, 47] {
            XCTAssertEqual(Level.decode(level).tier, 4, "level \(level) is tier 4")
        }
    }

    // MARK: - The ceiling in applyFeedback

    /// "More" climbs by the cell, never past it, at every level.
    func testMoreClimbsByTheCell() {
        for level in 0...EngineConfig.levelMax {
            let state = seeded(level: level)
            let next = after(state, .more)
            for ex in Engine.generateSession(state).exercises {
                let cap = EngineConfig.maxUp(pattern: ex.pattern,
                                             tier: Level.decode(level).tier)
                let expected = min(level + min(EngineConfig.deltaMore, cap),
                                   EngineConfig.levelMax)
                XCTAssertEqual(next.levels[ex.pattern], expected,
                               "\(ex.pattern.rawValue) from \(level) with cap \(cap)")
            }
        }
    }

    /// A pointed fact far above the plan is clamped by the same cell.
    func testAFactIsClampedByTheCell() {
        for level in 1...EngineConfig.levelMax {
            let state = seeded(level: level)
            let cap = EngineConfig.maxUp(pattern: .pull, tier: Level.decode(level).tier)
            let next = after(state, .plan, overrides: [.pull: 99])
            XCTAssertEqual(next.levels[.pull], min(level + cap, EngineConfig.levelMax),
                           "an enormous fact from \(level) is capped at +\(cap)")
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
        for _ in 0..<3 { state = after(state, .less) }
        XCTAssertEqual(state.levels[.pull], 4, "−1, −1, −1 then the −3 deload")
        XCTAssertEqual(state.failStreak[.pull], 0, "the deload resets the streak")
    }

    /// "On plan" is a step, whatever the cell allows.
    func testOnPlanIsAlwaysOneStep() {
        let next = after(seeded(level: 3), .plan)
        for ex in Engine.generateSession(seeded(level: 3)).exercises {
            XCTAssertEqual(next.levels[ex.pattern], 4, "\(ex.pattern.rawValue)")
        }
    }
}
