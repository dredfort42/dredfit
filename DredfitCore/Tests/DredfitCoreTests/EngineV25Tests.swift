//
//  EngineV25Tests.swift
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

    /// The shipped values, cell by cell: calves at every tier, the vertical
    /// push from tier 3, tier 4 for everyone, two everywhere else. The
    /// reference verifier checks the same table against the spec.
    func testTheShippedCeilingMatchesTheDeclaredRule() {
        for p in Pattern.allCases {
            for tier in 1...EngineConfig.tiers {
                let slow = p == .calf
                    || (p == .pushV && tier >= 3)
                    || tier == EngineConfig.tiers
                XCTAssertEqual(EngineConfig.maxUp(pattern: p, tier: tier), slow ? 1 : 2,
                               "\(p.rawValue) tier \(tier)")
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

    // MARK: - Discomfort and the freeze

    private func report(_ state: EngineState, _ result: FeedbackResult,
                        discomfort: Set<Pattern> = [], skipped: Set<Pattern> = [],
                        overrides: [Pattern: Int] = [:]) -> EngineState {
        Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                             result: result, overrides: overrides,
                             skipped: skipped, discomfort: discomfort)
    }

    /// The reported session behaves as a skip — nothing moves — and the
    /// pattern comes out frozen.
    func testDiscomfortLeavesTheSessionAloneAndFreezes() {
        var state = seeded(level: 12)
        state.failStreak[.pull] = 1
        let next = report(state, .more, discomfort: [.pull])

        XCTAssertEqual(next.levels[.pull], 12, "the level does not move")
        XCTAssertEqual(next.failStreak[.pull], 1, "the streak does not move")
        XCTAssertEqual(next.freezeRemaining(.pull), EngineConfig.freezeAppearances)
        XCTAssertEqual(next.counter, state.counter + 1, "the workout still happened")
        XCTAssertEqual(next.levels[.squat], 14, "a neighbour still climbs")
    }

    /// Frozen, the pattern keeps its place in the plan and holds its level for
    /// exactly N appearances — `pull` is in every session, so appearances are
    /// sessions here.
    func testTheFreezeHoldsForExactlyThreeAppearances() {
        var state = report(seeded(level: 12), .plan, discomfort: [.pull])
        for left in stride(from: EngineConfig.freezeAppearances, to: 0, by: -1) {
            XCTAssertEqual(state.freezeRemaining(.pull), left)
            state = report(state, .more)
            XCTAssertEqual(state.levels[.pull], 12, "no growth while frozen")
        }
        XCTAssertEqual(state.freezeRemaining(.pull), 0, "the freeze has run out")
        state = report(state, .more)
        XCTAssertEqual(state.levels[.pull], 14, "growth returns")
    }

    /// Honesty is never overridden: a fact still takes the level down, while
    /// one above the plan is clamped to where it was.
    func testAFactStillMovesAFrozenPatternDown() {
        let frozen = report(seeded(level: 12), .plan, discomfort: [.pull])
        let down = report(frozen, .plan, overrides: [.pull: 8])
        XCTAssertLessThan(down.levels[.pull]!, 12, "a fact below the plan still lands")
        let up = report(frozen, .plan, overrides: [.pull: 99])
        XCTAssertEqual(up.levels[.pull], 12, "a fact above the plan cannot grow it")
    }

    /// No double punishment: the streak neither grows nor resets under a
    /// freeze, so the deload cannot fire on top of it.
    func testAFreezeCannotDeload() {
        var state = seeded(level: 20)
        state.failStreak[.pull] = 2
        state = report(state, .less, discomfort: [.pull])
        for _ in 0..<EngineConfig.freezeAppearances { state = report(state, .less) }

        XCTAssertEqual(state.levels[.pull], 17, "three shortfalls, three steps — no deload")
        XCTAssertEqual(state.failStreak[.pull], 2, "the streak stayed where it was")
        state = report(state, .less)
        XCTAssertEqual(state.levels[.pull], 13, "once thawed the deload is possible again")
    }

    /// A repeat report starts the rest over.
    func testARepeatReportRefreshesTheCounter() {
        var state = report(seeded(level: 12), .plan, discomfort: [.pull])
        state = report(state, .plan)
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances - 1)
        state = report(state, .plan, discomfort: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances)
    }

    /// A skip freezes the counter with everything else — the pattern was not
    /// trained, so the appearance does not count.
    func testASkipDoesNotSpendAnAppearance() {
        var state = report(seeded(level: 12), .plan, discomfort: [.pull])
        let before = state.freezeRemaining(.pull)
        state = report(state, .plan, skipped: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), before)
        XCTAssertEqual(state.levels[.pull], 12)
    }

    /// Named in both, discomfort wins: the freeze carries information a silent
    /// skip does not.
    func testDiscomfortOutranksASkipAndAFact() {
        let state = report(seeded(level: 12), .more, discomfort: [.pull],
                           skipped: [.pull], overrides: [.pull: 99])
        XCTAssertEqual(state.levels[.pull], 12)
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances)
    }

    /// A pattern that is not in the session is a no-op, as with skips.
    func testDiscomfortOutsideTheSessionIsANoOp() {
        let state = seeded(level: 12)
        let inSession = Set(Engine.generateSession(state).exercises.map(\.pattern))
        let outside = Pattern.allCases.first { !inSession.contains($0) }!
        XCTAssertEqual(report(state, .plan, discomfort: [outside]).freezeRemaining(outside), 0)
    }

    /// A break lowers the levels but must not thaw a freeze.
    func testBreaksDoNotThawTheFreeze() {
        let frozen = report(seeded(level: 20), .plan, discomfort: [.pull])
        let left = frozen.freezeRemaining(.pull)

        let decayed = Engine.applySilentDecay(state: frozen, gapDays: 10)
        XCTAssertEqual(decayed.freezeRemaining(.pull), left, "silent decay keeps the freeze")
        XCTAssertEqual(decayed.levels[.pull], 19, "and still takes the step")

        let back = Engine.applyComeback(state: decayed, gapDays: 16, alreadyDecayed: true)
        XCTAssertEqual(back.freezeRemaining(.pull), left, "the comeback keeps it too")
        XCTAssertEqual(back.levels[.pull], 18, "the two drops still do not stack")
        XCTAssertEqual(report(back, .more).levels[.pull], 18, "and it is still frozen")
    }

    // MARK: - Serialization

    /// A state file written before the freeze existed decodes to "nothing
    /// frozen" rather than failing.
    func testLegacyStateDecodesWithoutTheFreezeField() throws {
        let legacy = """
        {"counter":3,"levels":["pull",5,"squat",4],"failStreak":["pull",1],"hasBar":true}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertTrue(state.frozen.isEmpty)
        XCTAssertEqual(state.levels[.pull], 5)
        XCTAssertEqual(state.hasBar, true)
    }

    /// And a state with a freeze round-trips.
    func testFreezeRoundTripsThroughTheStateFile() throws {
        let frozen = report(seeded(level: 12), .plan, discomfort: [.pull])
        let data = try JSONEncoder().encode(frozen)
        let back = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(back, frozen)
        XCTAssertEqual(back.freezeRemaining(.pull), EngineConfig.freezeAppearances)
    }
}
