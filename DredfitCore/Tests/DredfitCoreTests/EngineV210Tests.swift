//
//  EngineV210Tests.swift
//  DredfitCoreTests
//
//  Engine v2.10 (spec §20, issue #90): the pull slot keeps its full speed with
//  the bar enabled (the cross-credit), and the push never shows a wider set
//  band than the pull of the same session (the band gate).
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV210Tests: XCTestCase {

    private func seeded(_ levels: [Pattern: Int] = [:], counter: Int = 0,
                        hasBar: Bool = true, base: Int = 7) -> EngineState {
        var s = EngineState.initial
        s.hasBar = hasBar
        s.counter = counter
        for p in Pattern.allCases { s.levels[p] = levels[p] ?? base }
        return s
    }
    private func pullSlot(_ session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { Pattern.pullSide.contains($0.pattern) })
    }

    // MARK: - §20.1 the cross-credit

    func testTrainingOneBranchMovesTheOther() throws {
        for counter in [0, 1] {
            for (result, delta) in [(FeedbackResult.plan, EngineConfig.deltaPlan),
                                    (.more, EngineConfig.deltaMore)] {
                let state = seeded(counter: counter)
                let session = Engine.generateSession(state)
                let trained = try pullSlot(session).pattern
                let other: Pattern = trained == .pull ? .pullBar : .pull
                let after = Engine.applyFeedback(state: state, session: session, result: result)

                let gained = min(delta, EngineConfig.maxUp(pattern: trained, tier: Level.decode(7).tier))
                let credited = min(gained, EngineConfig.maxUp(pattern: other, tier: Level.decode(7).tier))
                XCTAssertEqual(after.levels[trained], 7 + gained, "\(trained) on \(result)")
                XCTAssertEqual(after.levels[other], 7 + credited, "\(other) is credited")
                XCTAssertEqual(after.failStreak[other], 0, "the other branch's streak is untouched")
            }
        }
    }

    func testTheCreditIsCappedByTheReceivingCell() {
        // counter 0 trains the horizontal row; the bar branch sits at tier 2,
        // where its own cell now holds it to one step (spec §20.1, §15.3).
        let state = seeded([.pull: 7, .pullBar: 10])
        let session = Engine.generateSession(state)
        let after = Engine.applyFeedback(state: state, session: session, result: .more)
        XCTAssertEqual(after.levels[.pull], 9, "tier 1 takes the full +2")
        XCTAssertEqual(after.levels[.pullBar], 11, "the credit stops at the receiver's cell")
    }

    func testNothingIsCreditedWhenTheSlotDidNotGrow() throws {
        let state = seeded()
        let session = Engine.generateSession(state)
        let trained = try pullSlot(session).pattern

        let down = Engine.applyFeedback(state: state, session: session, result: .less)
        XCTAssertEqual(down.levels[.pullBar], 7, "a downward move credits nothing")

        for (label, opts) in [("a skip", (skipped: Set([trained]), discomfort: Set<Pattern>(), pinned: Set<Pattern>())),
                              ("a discomfort report", (skipped: Set<Pattern>(), discomfort: Set([trained]), pinned: Set<Pattern>())),
                              ("a hold", (skipped: Set<Pattern>(), discomfort: Set<Pattern>(), pinned: Set([trained])))] {
            let after = Engine.applyFeedback(state: state, session: session, result: .more,
                                             skipped: opts.skipped, discomfort: opts.discomfort,
                                             pinned: opts.pinned)
            XCTAssertEqual(after.levels[.pullBar], 7, "\(label) on the slot credits nothing")
        }
    }

    func testWithoutTheBarTheVerticalBranchNeverMoves() {
        let state = seeded(hasBar: false)
        let after = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                         result: .more)
        XCTAssertEqual(after.levels[.pullBar], 7, "the branch is out of the plan without the bar")
    }

    func testAnExactNumberAlsoCredits() throws {
        let state = seeded([.pull: 0, .pullBar: 0])
        let session = Engine.generateSession(state)
        let ex = try pullSlot(session)
        let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [ex.pattern: ex.load + 6])
        XCTAssertGreaterThan(after.levels[.pull] ?? 0, 2, "the fact calibrated the trained branch")
        XCTAssertEqual(after.levels[.pullBar],
                       min(EngineConfig.maxUp(pattern: .pullBar, tier: 1), after.levels[.pull] ?? 0),
                       "the credit from a fact stops at the receiver's cell")
    }

    /// The slot now moves at one speed whether or not the bar is on — which is
    /// the whole point: splitting the bookkeeping was what halved it.
    func testTheSlotKeepsOneSpeedWithAndWithoutTheBar() {
        func gain(overEightSessionsWithBar hasBar: Bool) -> [Pattern: Int] {
            var s = EngineState.initial
            s.hasBar = hasBar
            let start = s.levels
            for _ in 0..<8 {
                s = Engine.applyFeedback(state: s, session: Engine.generateSession(s), result: .plan)
            }
            return s.levels.mapValues { $0 } .reduce(into: [:]) { acc, kv in
                acc[kv.key] = kv.value - (start[kv.key] ?? 0)
            }
        }
        let off = gain(overEightSessionsWithBar: false)
        let on = gain(overEightSessionsWithBar: true)
        XCTAssertEqual(off[.pull], 8, "without the bar the slot gains eight in eight")
        XCTAssertEqual(on[.pull], 8, "with the bar the horizontal branch keeps up")
        XCTAssertEqual(on[.pullBar], 8, "and so does the vertical one")
        XCTAssertEqual(on[.squat], 5, "a rotating pattern still gains five")
    }

    /// The period-2 lock inherited from #91: with a rhythm of period two the
    /// bar branch used to land in the same rating forever and never left zero.
    func testThePeriodTwoLockIsOpen() {
        var state = EngineState.initial
        state.hasBar = true
        for k in 0..<96 {
            state = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                         result: k % 2 == 0 ? .more : .less)
        }
        XCTAssertGreaterThan(state.levels[.pullBar] ?? 0, 0,
                             "the vertical branch leaves zero on an alternating rhythm")
    }

    // MARK: - §20.2 the band gate

    func testThePushNeverShowsAWiderBandThanThePull() throws {
        for (pullL, pushL) in [(0, 47), (20, 47), (31, 32), (39, 40), (47, 47), (40, 32)] {
            let state = seeded([.pull: pullL, .pullBar: pullL, .pushH: pushL, .pushV: pushL])
            let session = Engine.generateSession(state)
            let slot = try pullSlot(session)
            for ex in session.exercises where Pattern.pushSide.contains(ex.pattern) {
                XCTAssertEqual(ex.sets, min(Level.decode(pushL).sets, slot.sets),
                               "pull \(pullL) / push \(pushL): the band is the smaller of the two")
                // Re-marked for v2.17 (spec §28.2): the rest follows the
                // resulting band AND the tier — a gated tier-4 push rests 90 s,
                // because the gate trimmed the plan, not the difficulty.
                XCTAssertEqual(ex.restSetSec,
                               EngineConfig.restSetByTierBand[ex.tier]?[ex.sets]
                                ?? EngineConfig.restSetByBand[ex.sets]
                                ?? EngineConfig.restSetSec,
                               "the rest follows the resulting band and tier")
            }
        }
    }

    func testTheGateClampsThePlanAndNotTheState() throws {
        let state = seeded([.pull: 0, .pullBar: 0, .pushH: 40, .pushV: 40])
        let session = Engine.generateSession(state)
        let push = try XCTUnwrap(session.exercises.first { Pattern.pushSide.contains($0.pattern) })
        XCTAssertEqual(push.sets, Level.decode(0).sets, "the plan shows the pull's band")
        let after = Engine.applyFeedback(state: state, session: session, result: .plan)
        XCTAssertEqual(after.levels[push.pattern], 41, "the push level grows all the same")
    }

    func testTheGateLeavesEveryOtherPatternAlone() {
        let state = seeded([.pull: 0, .pullBar: 0, .squat: 47, .lunge: 47])
        let session = Engine.generateSession(state)
        for ex in session.exercises where ex.pattern == .squat || ex.pattern == .lunge {
            XCTAssertEqual(ex.sets, Level.decode(47).sets, "\(ex.pattern) is not gated")
        }
    }

    /// The acceptance of the wave: the pull holds at least 0.7 of the push in
    /// sets over any six-session window, with the bar and without it.
    func testTheBalanceHoldsTheSevenTenthsPrinciple() {
        let rhythms: [[FeedbackResult]] = [[.plan], [.more, .plan], [.more, .plan, .less, .plan],
                                           [.plan, .plan, .less], [.more]]
        for hasBar in [false, true] {
            for rhythm in rhythms {
                var state = EngineState.initial
                state.hasBar = hasBar
                var sessions: [Session] = []
                for k in 0..<60 {
                    let session = Engine.generateSession(state)
                    sessions.append(session)
                    state = Engine.applyFeedback(state: state, session: session,
                                                 result: rhythm[k % rhythm.count])
                }
                for i in 0...(sessions.count - 6) {
                    var pull = 0, push = 0
                    for session in sessions[i..<(i + 6)] {
                        for ex in session.exercises {
                            if Pattern.pullSide.contains(ex.pattern) { pull += ex.sets }
                            if Pattern.pushSide.contains(ex.pattern) { push += ex.sets }
                        }
                    }
                    XCTAssertGreaterThanOrEqual(Double(pull) / Double(push), 0.7,
                                                "bar \(hasBar), window \(i): pull/push in sets")
                }
            }
        }
    }

    // MARK: - §20.1 the pause

    /// The credit lands on sessions the branch is not in — the ones you cannot
    /// answer. Without the pause the level ran away from what the athlete could
    /// actually do: 29 whether their ceiling was 6, 12 or 20.
    func testAHardAppearancePausesTheCreditUntilAGoodOne() {
        let state = seeded(counter: 1)          // counter 1 puts the bar branch in the plan
        let strained = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                            result: .less)
        XCTAssertTrue(strained.creditPaused.contains(.pullBar), "a hard session marks the branch")

        let next = Engine.applyFeedback(state: strained, session: Engine.generateSession(strained),
                                        result: .plan)
        XCTAssertEqual(next.levels[.pullBar], strained.levels[.pullBar],
                       "a marked branch earns no credit")
        XCTAssertGreaterThan(next.levels[.pull] ?? 0, strained.levels[.pull] ?? 0,
                             "the trained branch still moves")

        let cleared = Engine.applyFeedback(state: next, session: Engine.generateSession(next),
                                           result: .plan)
        XCTAssertFalse(cleared.creditPaused.contains(.pullBar), "an appearance without a signal clears it")
        let resumed = Engine.applyFeedback(state: cleared, session: Engine.generateSession(cleared),
                                           result: .plan)
        XCTAssertGreaterThan(resumed.levels[.pullBar] ?? 0, cleared.levels[.pullBar] ?? 0,
                             "and the credit comes back")
    }

    func testAFactBelowPlanAHoldAndPainAllMarkTheBranch() throws {
        let state = seeded(counter: 1)
        let session = Engine.generateSession(state)
        let bar = try XCTUnwrap(session.exercises.first { $0.pattern == .pullBar })
        let cases: [(String, EngineState)] = [
            ("a fact below plan", Engine.applyFeedback(state: state, session: session, result: .plan,
                                                       overrides: [.pullBar: bar.load - 2])),
            ("pain", Engine.applyFeedback(state: state, session: session, result: .plan,
                                          discomfort: [.pullBar])),
            ("a hold", Engine.applyFeedback(state: state, session: session, result: .plan,
                                            pinned: [.pullBar])),
        ]
        for (label, after) in cases {
            XCTAssertTrue(after.creditPaused.contains(.pullBar), "\(label) marks the branch")
        }
    }

    func testABreakClearsTheMark() {
        let state = seeded(counter: 1)
        let strained = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                            result: .less)
        XCTAssertTrue(Engine.applyComeback(state: strained, gapDays: 30).creditPaused.isEmpty)
        XCTAssertTrue(Engine.applySilentDecay(state: strained, gapDays: 9).creditPaused.isEmpty)
    }

    /// The question this wave has to answer: someone whose pull-ups top out
    /// must not be asked for more and more forever.
    func testThePlanSettlesAtWhatTheAthleteCanHold() {
        for ceiling in [6, 12, 20] {
            var state = EngineState.initial
            state.hasBar = true
            for _ in 0..<90 {
                let session = Engine.generateSession(state)
                let barIsIn = session.exercises.contains { $0.pattern == .pullBar }
                let tooHard = barIsIn && (state.levels[.pullBar] ?? 0) > ceiling
                state = Engine.applyFeedback(state: state, session: session,
                                             result: tooHard ? .less : .plan)
            }
            XCTAssertLessThanOrEqual(state.levels[.pullBar] ?? 0, ceiling + 1,
                                     "ceiling \(ceiling): the plan parks a step above it, not beyond")
        }
    }

    func testAStateFileWithoutThePauseDecodesEmpty() throws {
        let legacy = """
        {"counter":3,"levels":["pull",7,"pull_bar",7],"failStreak":["pull",0],"hasBar":true}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertTrue(state.creditPaused.isEmpty, "a file written before v2.10 reads as no pause")
    }
}
