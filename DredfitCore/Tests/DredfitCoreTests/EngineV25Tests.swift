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

    /// v2.9: this file is about the growth-cap table and the freeze, so an
    /// unnamed "less" is taken under a run — session-wide delta (spec §19.2).
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
                // v2.10 (spec §20.1): the bar branch joins the pull's cells —
                // the cross-credit gives it the slot's full speed, so the
                // frequency argument of #76 reaches it too.
                let slow = p == .calf
                    || (p == .pushV && tier >= 3)
                    || (Pattern.pullSide.contains(p) && tier >= 2)
                    || tier == EngineConfig.tiers
                XCTAssertEqual(EngineConfig.maxUp(pattern: p, tier: tier), slow ? 1 : 2,
                               "\(p.rawValue) tier \(tier)")
            }
        }
    }

    /// The pull's cells are the one frequency argument in the table: the
    /// fixed slot gives it eight appearances where a rotating pattern gets
    /// five, so from the first real row on it is held to a step. Tier 1 is
    /// scapular activation, not a row, and deliberately keeps the default;
    /// the bar branch used to sit at four appearances in eight and went
    /// uncapped — until v2.10 (spec §20.1) gave the slot back its full speed
    /// through the cross-credit, which makes the same argument apply to it.
    func testThePullIsHeldToAStepFromTierTwo() {
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 1), 2, "tier 1 keeps the default")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 2), 1, "the inverted row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 3), 1, "the feet-elevated row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 2), 1, "the bar branch is capped alongside the row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 3), 1, "the bar branch is capped alongside the row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 1), 2, "the hang keeps the default")

        // "More" at a tier-2 level takes one step, not two; "on plan" is
        // never capped, so the pull still moves every session.
        let atTierTwo = after(seeded(level: 10), .more)
        XCTAssertEqual(atTierTwo.levels[.pull], 11, "the collateral +2 is gone")
        let onPlan = after(seeded(level: 10), .plan)
        XCTAssertEqual(onPlan.levels[.pull], 11, "one step per session survives the cap")
        let atTierOne = after(seeded(level: 4), .more)
        XCTAssertEqual(atTierOne.levels[.pull], 6, "tier 1 still climbs by two")
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
        let base = result == .less && discomfort.isEmpty ? state.underLessRun : state
        return Engine.applyFeedback(state: base, session: Engine.generateSession(state),
                                    result: result, overrides: overrides,
                                    skipped: skipped, discomfort: discomfort)
    }

    /// v2.11 (spec §21.1), re-marked for v2.19 (spec §30.6): the report voids
    /// the session for the pattern AND takes the load off — the FIRST step
    /// being the floor of the current tier, the streak resets, the episode
    /// opens.
    func testDiscomfortLeavesTheSessionAloneAndFreezes() {
        var state = seeded(level: 12)
        state.failStreak[.pull] = 1
        let next = report(state, .more, discomfort: [.pull])

        XCTAssertEqual(next.levels[.pull], Level.tierFloor(12),
                       "tier 2 lands on its own floor")
        XCTAssertEqual(next.failStreak[.pull], 0, "the unload resets the streak")
        XCTAssertEqual(next.freezeRemaining(.pull), EngineConfig.freezeAppearances)
        XCTAssertEqual(next.sore[.pull], EngineConfig.freezeAppearances, "the episode opens")
        XCTAssertEqual(next.counter, state.counter + 1, "the workout still happened")
        XCTAssertEqual(next.levels[.squat], 14, "a neighbour still climbs")
    }

    /// Frozen, the pattern holds its unloaded level for exactly N appearances
    /// — and then WAITS (v2.11, spec §21.2): taps never resume growth, only a
    /// fact at or above the plan does. `pull` is in every session, so
    /// appearances are sessions here.
    func testTheFreezeHoldsForExactlyThreeAppearances() {
        var state = report(seeded(level: 20), .plan, discomfort: [.pull])
        let dropped = Level.tierFloor(20)          // v2.19 (§30.6): first step
        XCTAssertEqual(state.levels[.pull], dropped)
        for left in stride(from: EngineConfig.freezeAppearances, to: 0, by: -1) {
            XCTAssertEqual(state.freezeRemaining(.pull), left)
            state = report(state, .more)
            XCTAssertEqual(state.levels[.pull], dropped, "no growth while frozen")
        }
        XCTAssertEqual(state.freezeRemaining(.pull), 0, "the freeze has run out")
        XCTAssertEqual(state.sore[.pull], EngineConfig.freezeAppearances, "the episode lives on")
        state = report(state, .more)
        XCTAssertEqual(state.levels[.pull], dropped, "a tap does not bring growth back")
        let session = Engine.generateSession(state)
        let load = session.exercises.first { $0.pattern == .pull }!.load
        state = Engine.applyFeedback(state: state, session: session, result: .plan,
                                     overrides: [.pull: load])
        XCTAssertNil(state.sore[.pull], "the fact confirms recovery")
        XCTAssertEqual(state.levels[.pull], dropped + EngineConfig.deltaPlan,
                       "and the same fact takes the step")
    }

    /// Honesty is never overridden: a fact still takes the level down, while
    /// one above the plan is clamped — and under the freeze it does not
    /// confirm either (v2.11: the assigned rest is served in full).
    func testAFactStillMovesAFrozenPatternDown() {
        // v2.19 (§30.6): the landing is the current tier's floor; the block is
        // about the fact, so it reads the landing rather than a pinned number.
        let landed = Level.tierFloor(20)
        let frozen = report(seeded(level: 20), .plan, discomfort: [.pull])
        XCTAssertEqual(frozen.levels[.pull], landed)
        let down = report(frozen, .plan, overrides: [.pull: 3])
        XCTAssertLessThan(down.levels[.pull]!, landed, "a fact below the plan still lands")
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: landed, to: down.levels[.pull]!),
                      "and lands no harder than the plan it fell short of")
        let up = report(frozen, .plan, overrides: [.pull: 99])
        XCTAssertEqual(up.levels[.pull], landed, "a fact above the plan cannot grow it")
        XCTAssertEqual(up.sore[.pull], EngineConfig.freezeAppearances,
                       "a fact during the freeze does not confirm")
    }

    /// No double punishment: the unload resets the streak, and under the
    /// freeze — and the waiting after it — the streak stands, so the deload
    /// is unreachable until the episode is confirmed (v2.11, spec §21.2).
    func testAFreezeCannotDeload() {
        var state = seeded(level: 20)
        state.failStreak[.pull] = 2
        state = report(state, .less, discomfort: [.pull])
        // v2.19 (§30.6): the landing moved, the arithmetic below did not.
        let landed = Level.tierFloor(20)
        XCTAssertEqual(state.levels[.pull], landed, "the report unloads")
        XCTAssertEqual(state.failStreak[.pull], 0, "and resets the streak")
        for _ in 0..<EngineConfig.freezeAppearances { state = report(state, .less) }

        XCTAssertEqual(state.levels[.pull], landed - EngineConfig.freezeAppearances,
                       "three shortfalls, three steps — no deload")
        XCTAssertEqual(state.failStreak[.pull], 0, "the streak stays put")
        state = report(state, .less)
        XCTAssertEqual(state.levels[.pull], landed - EngineConfig.freezeAppearances - 1,
                       "waiting: still a step, still no deload")
        XCTAssertEqual(state.failStreak[.pull], 0)
    }

    /// v2.11 (spec §21.2 p.2): a repeat report doubles the rest up the
    /// 3 → 6 → 12 ladder instead of refreshing it, and never drops twice.
    func testARepeatReportDoublesTheRest() {
        var state = report(seeded(level: 20), .plan, discomfort: [.pull])
        state = report(state, .plan)
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances - 1)
        state = report(state, .plan, discomfort: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), 6, "3 → 6")
        // v2.19 (§30.6): the second report takes the second step. From level
        // 20 both landings happen to be 8 — tier 3's floor is 16 and its
        // unload is 8, exactly where v2.11 landed in one go — so the number
        // is spelled as the composition it now is, not as a coincidence.
        XCTAssertEqual(state.levels[.pull], Level.unload(Level.tierFloor(20)),
                       "the second report is the second step")
        state = report(state, .plan, discomfort: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeCapAppearances, "6 → 12")
        state = report(state, .plan, discomfort: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeCapAppearances,
                       "the ladder tops out")
    }

    /// A skip freezes the counter with everything else — the pattern was not
    /// trained, so the appearance does not count.
    func testASkipDoesNotSpendAnAppearance() {
        var state = report(seeded(level: 12), .plan, discomfort: [.pull])
        let before = state.freezeRemaining(.pull)
        state = report(state, .plan, skipped: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), before)
        XCTAssertEqual(state.levels[.pull], Level.tierFloor(12),
                       "held at the unloaded level")
    }

    /// Named in both, discomfort wins: the unload is stronger than the fact,
    /// and the freeze carries information a silent skip does not.
    func testDiscomfortOutranksASkipAndAFact() {
        let state = report(seeded(level: 12), .more, discomfort: [.pull],
                           skipped: [.pull], overrides: [.pull: 99])
        XCTAssertEqual(state.levels[.pull], Level.tierFloor(12))
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances)
    }

    /// A pattern that is not in the session is a no-op, as with skips.
    func testDiscomfortOutsideTheSessionIsANoOp() {
        let state = seeded(level: 12)
        let inSession = Set(Engine.generateSession(state).exercises.map(\.pattern))
        let outside = Pattern.allCases.first { !inSession.contains($0) }!
        XCTAssertEqual(report(state, .plan, discomfort: [outside]).freezeRemaining(outside), 0)
    }

    /// A break lowers the levels but must not thaw a freeze — nor close a
    /// pain episode (v2.11, spec §21.2 p.8).
    func testBreaksDoNotThawTheFreeze() {
        let landed = Level.tierFloor(20)             // v2.19 (§30.6): first step
        let frozen = report(seeded(level: 20), .plan, discomfort: [.pull])
        XCTAssertEqual(frozen.levels[.pull], landed)
        let left = frozen.freezeRemaining(.pull)

        let decayed = Engine.applySilentDecay(state: frozen, gapDays: 10)
        XCTAssertEqual(decayed.freezeRemaining(.pull), left, "silent decay keeps the freeze")
        XCTAssertEqual(decayed.sore[.pull], EngineConfig.freezeAppearances, "and the episode")
        XCTAssertEqual(decayed.levels[.pull], landed - 1, "and still takes the step")

        let back = Engine.applyComeback(state: decayed, gapDays: 16, alreadyDecayed: true)
        XCTAssertEqual(back.freezeRemaining(.pull), left, "the comeback keeps it too")
        XCTAssertEqual(back.sore[.pull], EngineConfig.freezeAppearances, "episode included")
        // v2.12 (spec §22.1): the landing crosses a tier boundary, so rep
        // continuity decides where it lands. Re-marked for v2.19 (§30.6): the
        // block is about a break not thawing a freeze, so it asserts the
        // property — down, and no harder — rather than the pinned 0 the old
        // one-step landing produced.
        XCTAssertLessThan(back.levels[.pull]!, decayed.levels[.pull]!,
                          "the tier crossing still goes down")
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: decayed.levels[.pull]!,
                                     to: back.levels[.pull]!),
                      "and never asks for more work than before the break")
        XCTAssertEqual(Engine.applyComeback(state: frozen, gapDays: 16).levels[.pull],
                       back.levels[.pull], "the two paths still agree")
        XCTAssertEqual(report(back, .more).levels[.pull], back.levels[.pull],
                       "and it is still frozen")
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
