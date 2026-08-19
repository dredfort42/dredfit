//
//  EngineV217Tests.swift
//  DredfitCoreTests
//
//  Engine v2.17 (spec §28, issues #136/#129/#142/#144): volume and time.
//  Session length used to be an output of the model with no handle for the
//  person doing it — the shortest plan anywhere on the scale was 31 minutes,
//  honest progress rode it past 45 by session 37 and past 75 by 67, and the
//  "short version" bottomed out at 20. Meanwhile daily training walked around
//  the per-session growth caps by multiplication, entering a sets band halved
//  the actual work, and a tier-4 movement in band 3 rested a minute.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV217Tests: XCTestCase {

    private func seeded(_ level: Int, budget: Int = 0, bar: Bool = false) -> EngineState {
        var s = EngineState.initial
        s.hasBar = bar
        s.timeBudgetMin = budget
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    // MARK: - §28.1 Entering a sets band keeps the dose

    func testABandStartsAtItsOwnDoseNotTheTierFloor() {
        XCTAssertEqual(Level.decode(32).reps, EngineConfig.repStartBand[4])
        XCTAssertEqual(Level.decode(40).reps, EngineConfig.repStartBand[5])
        for boundary in [31, 39] {
            let before = Level.decode(boundary), after = Level.decode(boundary + 1)
            let workBefore = before.sets * before.reps
            let workAfter = after.sets * after.reps
            let drop = 1 - Double(workAfter) / Double(workBefore)
            XCTAssertLessThanOrEqual(drop, 0.31,
                "L\(boundary)→\(boundary + 1) drops the work by \(Int(drop * 100))%")
        }
    }

    func testTheEncodingStillRoundTrips() {
        for level in 0...EngineConfig.levelMax {
            let d = Level.decode(level)
            XCTAssertEqual(Level.fromActual(pattern: .squat, tier: d.tier,
                                            sets: d.sets, actual: d.reps), level)
            XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: d.tier,
                                            sets: d.sets, actual: d.hold), level)
        }
    }

    // MARK: - §28.2 Rest reads the tier as well as the band

    func testATierFourMovementInBandThreeRestsLongerThanAMinute() throws {
        let session = Engine.generateSession(seeded(28))
        let ex = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(ex.tier, 4)
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.restSetSec, 90, "the band alone was never the whole story")
    }

    func testTheRestLadderNeverGoesBackwards() {
        var previous = 0
        for level in 24...EngineConfig.levelMax {
            let rest = Engine.generateSession(seeded(level)).exercises[0].restSetSec
            XCTAssertGreaterThanOrEqual(rest, previous,
                "levelling up must not buy less rest (L\(level))")
            previous = rest
        }
    }

    // MARK: - §28.3 The time budget

    func testEveryBudgetIsMetAtEveryLevelWithoutTouchingLevels() {
        for budget in [20, 35, 45] {
            for level in 0...EngineConfig.levelMax {
                let state = seeded(level, budget: budget)
                let session = Engine.generateSession(state)
                XCTAssertLessThanOrEqual(session.estimatedTotalMin, Double(budget),
                    "L\(level) at budget \(budget): \(session.estimatedTotalMin) min")
                XCTAssertGreaterThanOrEqual(session.exercises.count,
                                            EngineConfig.budgetPatternsFloor)
                let full = Engine.generateSession(seeded(level))
                for ex in session.exercises {
                    let same = full.exercises.first { $0.pattern == ex.pattern }
                    XCTAssertEqual(ex.tier, same?.tier, "the budget changed the variation")
                    XCTAssertEqual(ex.load, same?.load, "the budget changed the load")
                    XCTAssertGreaterThanOrEqual(ex.sets, EngineConfig.budgetSetsFloor)
                }
            }
        }
    }

    func testNoBudgetIsExactlyTheOldBehaviour() {
        for level in stride(from: 0, through: EngineConfig.levelMax, by: 7) {
            XCTAssertEqual(Engine.generateSession(seeded(level)),
                           Engine.generateSession(seeded(level, budget: 0)))
        }
    }

    func testAShortBudgetStillShowsEveryMovementOftenEnough() {
        var state = seeded(0, budget: 20)
        var last: [Pattern: Int] = [:]
        var worst = 0
        for session in 0..<24 {
            let plan = Engine.generateSession(state)
            for ex in plan.exercises {
                if let seen = last[ex.pattern] { worst = max(worst, session - seen) }
                last[ex.pattern] = session
            }
            state = Engine.applyFeedback(state: state, session: plan, result: .plan)
        }
        for p in Pattern.ordered {
            XCTAssertNotNil(last[p], "\(p) never appeared in 24 sessions")
        }
        XCTAssertLessThanOrEqual(worst, 5,
            "a pattern waited \(worst) sessions — longer than the silent decay's interval")
    }

    // MARK: - §28.4 The window after a comeback

    func testAComebackOpensAWindowWhereMoreCountsAsPlan() {
        var state = seeded(20)
        for _ in 0..<4 {
            state = Engine.applyFeedback(state: state,
                                         session: Engine.generateSession(state), result: .plan)
        }
        let back = Engine.applyComeback(state: state, gapDays: 90)
        XCTAssertEqual(back.rampWindow, EngineConfig.rampWindowSessions)

        let before = back.levels
        let after = Engine.applyFeedback(state: back, session: Engine.generateSession(back),
                                         result: .more)
        for p in Pattern.ordered {
            XCTAssertLessThanOrEqual((after.levels[p] ?? 0) - (before[p] ?? 0),
                                     EngineConfig.deltaPlan,
                                     "\(p) grew by more than one inside the window")
        }
        XCTAssertEqual(after.rampWindow, EngineConfig.rampWindowSessions - 1)
    }

    func testTheWindowRunsOutAndDownwardMovesAreUntouched() {
        var state = Engine.applyComeback(state: seeded(20), gapDays: 90)
        let down = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                        result: .less)
        XCTAssertTrue(Pattern.ordered.contains { (down.levels[$0] ?? 0) < (state.levels[$0] ?? 0) },
                      "honesty is never blocked by the window")
        for _ in 0..<EngineConfig.rampWindowSessions {
            state = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                         result: .plan)
        }
        XCTAssertEqual(state.rampWindow, 0)
    }

    // MARK: - §28.5 The weekly ceiling

    func testTheWeeklyCeilingIsFreeForAnHonestThreeTimesAWeek() {
        var blind = EngineState.initial, signalled = EngineState.initial
        let gaps = [2, 2, 3]
        for k in 0..<36 {
            blind = Engine.applyFeedback(state: blind,
                                         session: Engine.generateSession(blind), result: .plan)
            signalled = Engine.applyFeedback(state: signalled,
                                             session: Engine.generateSession(signalled),
                                             result: .plan, gapDays: gaps[k % 3])
        }
        for p in Pattern.allCases {
            XCTAssertEqual(blind.levels[p], signalled.levels[p],
                           "\(p): an honest 3×/week must pay nothing for the ceiling")
        }
    }

    func testDailyTrainingNoLongerReachesFullPullUpsInFourWeeks() {
        var state = EngineState.initial
        state.hasBar = true
        for _ in 0..<28 {
            state = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                         result: .plan, gapDays: 1)
        }
        let windows = Int((28.0 + 1).rounded(.up) / Double(EngineConfig.weeklyWindowDays)) + 1
        XCTAssertLessThanOrEqual(state.levels[.pull] ?? 0,
                                 windows * EngineConfig.weeklyRiseSlow)
        XCTAssertLessThanOrEqual(state.levels[.pullBar] ?? 0,
                                 windows * EngineConfig.weeklyRiseSlow,
                                 "the cross-credit is charged too, or it walks around the budget")
        XCTAssertLessThan(Level.decode(state.levels[.pull] ?? 0).tier, EngineConfig.tiers,
                          "full pull-ups no longer arrive after 28 days without a rest day")
    }

    // MARK: - The inversion bug the budget work uncovered (§28.0)

    func testAnHonestOvershootOfAGatedPlanDoesNotCollapseASoreMovement() throws {
        var state = seeded(10)
        state.levels[.pushV] = 44
        state.levels[.pull] = 20
        state.sore[.pushV] = EngineConfig.freezeAppearances
        let session = Engine.generateSession(state)
        guard let ex = session.exercises.first(where: { $0.pattern == .pushV }) else { return }
        XCTAssertLessThan(ex.sets, Level.decode(44).sets, "the gate trimmed the plan")
        let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [.pushV: ex.load + 1])
        XCTAssertGreaterThanOrEqual(after.levels[.pushV] ?? 0, 44,
                                    "an honest overshoot used to drop the level to 29")
        XCTAssertNil(after.sore[.pushV], "and it closes the pain episode")
    }
}
