//
//  EngineV224Tests.swift
//  DredfitCoreTests
//
//  Engine v2.24 (spec §35, issues #136/#147): the shared sets floor and a trim
//  that removes one set at a time.
//
//  Two mechanisms cut sets — the time budget (§28.3) and the set-band gate
//  (§20.2) — and until this wave neither knew the other existed: the floor
//  lived inside the budget path only, so "at least two sets" was a property of
//  one route rather than an invariant of the plan. And the budget trim capped
//  all six movements at once, which made its step wider than the miss it was
//  closing: a 45-minute budget sawed 45 → 29 → 45.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV224Tests: XCTestCase {

    private func seeded(_ level: Int, budget: Int = 0, bar: Bool = false,
                        counter: Int = 0) -> EngineState {
        var s = EngineState.initial
        s.hasBar = bar
        s.counter = counter
        s.timeBudgetMin = budget
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    /// Branches deliberately apart: the gate reads the WEAKER of the two, so
    /// this is where the push ceiling drops below the movement's own band.
    private func split(pull: Int, pullBar: Int, others: Int,
                       budget: Int = 0, bar: Bool = true, counter: Int = 0) -> EngineState {
        var s = seeded(others, budget: budget, bar: bar, counter: counter)
        s.levels[.pull] = pull
        s.levels[.pullBar] = pullBar
        return s
    }

    // MARK: - §35.1 The shared floor

    /// The sweep the spec asks for: no combination of budget and gate may put
    /// any exercise below two sets — or above the ceiling, or hand out more
    /// per-set doses than there are sets.
    func testNoCombinationOfBudgetAndGateGoesBelowTheFloor() {
        for budget in [0, 15, 20, 25, 30, 35, 45, 60, 90] {
            for level in 0...EngineConfig.levelMax {
                for counter in 0..<8 {
                    for bar in [false, true] {
                        let states = [
                            seeded(level, budget: budget, bar: bar, counter: counter),
                            split(pull: 0, pullBar: 0, others: level,
                                  budget: budget, bar: bar, counter: counter),
                            split(pull: EngineConfig.levelMax, pullBar: 0, others: level,
                                  budget: budget, bar: bar, counter: counter),
                        ]
                        for state in states {
                            for ex in Engine.generateSession(state).exercises {
                                XCTAssertGreaterThanOrEqual(
                                    ex.sets, EngineConfig.setsFloor,
                                    "L\(level) c\(counter) bar=\(bar) budget \(budget): "
                                    + "\(ex.pattern) on \(ex.sets) sets")
                                XCTAssertLessThanOrEqual(ex.sets, EngineConfig.setsMax)
                                if let loads = ex.loads {
                                    XCTAssertEqual(loads.count, ex.sets,
                                        "L\(level): \(ex.pattern) loads vs sets")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - §35.2 One set at a time

    /// The shortfall the wave exists to close. Measured only where trimming
    /// actually happened — a cell that is already shorter than the budget says
    /// nothing about the quality of the trim. v2.23 missed by up to 36%.
    func testTheBudgetShortfallStaysUnderTenPercent() {
        let budget = 45
        var worst = 0.0
        var worstWhere = ""
        for level in 24...EngineConfig.levelMax {
            for counter in 0..<8 {
                for bar in [false, true] {
                    let full = Engine.generateSession(seeded(level, bar: bar, counter: counter))
                    guard full.estimatedTotalMin > Double(budget) else { continue }
                    let cut = Engine.generateSession(
                        seeded(level, budget: budget, bar: bar, counter: counter))
                    XCTAssertLessThanOrEqual(cut.estimatedTotalMin, Double(budget),
                        "L\(level) c\(counter) bar=\(bar) missed the budget")
                    let pct = (Double(budget) - cut.estimatedTotalMin) / Double(budget) * 100
                    if pct > worst { worst = pct; worstWhere = "L\(level) c\(counter) bar=\(bar)" }
                }
            }
        }
        XCTAssertLessThanOrEqual(worst, 10,
            "shortfall \(worst)% at \(worstWhere) — the ceiling is 10%")
    }

    /// Shrinking the budget can never LENGTHEN the session. It holds by
    /// construction — the removal order does not depend on the budget — and
    /// that is exactly why it is worth pinning: it is the property that made
    /// the old sawtooth a bug rather than a preference.
    func testShrinkingTheBudgetNeverLengthensTheSession() {
        for level in 0...EngineConfig.levelMax {
            for bar in [false, true] {
                for counter in [0, 1, 3] {
                    var previous = Double.infinity
                    for budget in stride(from: 90, through: 15, by: -1) {
                        let minutes = Engine.generateSession(
                            seeded(level, budget: budget, bar: bar, counter: counter)
                        ).estimatedTotalMin
                        XCTAssertLessThanOrEqual(minutes, previous,
                            "L\(level) c\(counter) bar=\(bar) budget \(budget)")
                        previous = minutes
                    }
                }
            }
        }
    }

    /// The trim takes sets and only sets: the movement list, the variations and
    /// the doses are the full plan's, and no exercise ever gains a set.
    func testTheTrimTakesSetsAndNothingElse() {
        for budget in [15, 20, 30, 45] {
            for level in 0...EngineConfig.levelMax {
                let full = Engine.generateSession(seeded(level))
                let cut = Engine.generateSession(seeded(level, budget: budget))
                XCTAssertEqual(cut.exercises.map(\.pattern), full.exercises.map(\.pattern),
                    "L\(level) at budget \(budget): the movement list changed")
                for (a, b) in zip(full.exercises, cut.exercises) {
                    XCTAssertEqual(a.tier, b.tier)
                    XCTAssertEqual(a.load, b.load)
                    XCTAssertEqual(a.name, b.name)
                    XCTAssertLessThanOrEqual(b.sets, a.sets,
                        "L\(level): \(b.pattern) gained a set from the budget")
                }
            }
        }
    }

    /// "No limit" never enters the trim — pinned here on the split branches
    /// too, where the gate is busy with no budget involved at all.
    func testNoLimitIsIdenticalToNoBudgetOnSplitBranches() {
        for level in 0...EngineConfig.levelMax {
            for bar in [false, true] {
                let a = Engine.generateSession(
                    split(pull: 0, pullBar: 0, others: level, bar: bar, counter: 1))
                let b = Engine.generateSession(
                    split(pull: 0, pullBar: 0, others: level, budget: 0, bar: bar, counter: 1))
                XCTAssertEqual(a, b, "L\(level) bar=\(bar)")
            }
        }
    }

    /// The tightest rung is honest about what it cannot do: with everything on
    /// the floor a plan may run past its budget, and that is the accepted
    /// consequence of never dropping a movement. What must NOT happen is a
    /// pattern falling out of the session to buy the minutes.
    func testTheTightestBudgetKeepsEveryMovementEvenWhenItOverruns() {
        var overran = false
        for level in 0...EngineConfig.levelMax {
            let full = Engine.generateSession(seeded(level))
            let cut = Engine.generateSession(seeded(level, budget: 20))
            XCTAssertEqual(cut.exercises.count, full.exercises.count,
                "L\(level): a movement was dropped for the budget")
            if cut.estimatedTotalMin > 20 {
                overran = true
                XCTAssertTrue(cut.exercises.allSatisfy { $0.sets == EngineConfig.setsFloor },
                    "L\(level) overran 20 min without reaching the floor")
            }
        }
        XCTAssertTrue(overran,
            "the tightest rung is supposed to overrun somewhere — otherwise this "
            + "test would pass vacuously and stop guarding the floor")
    }
}
