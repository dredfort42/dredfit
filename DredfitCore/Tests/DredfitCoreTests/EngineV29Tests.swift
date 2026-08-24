//
//  DredfitCoreTests
//
//  Engine v2.9 (spec §19, issue #91): a session-wide "less" reaches the
//  movement the user named, or — when nothing was named — the single
//  highest-level one, until a run of unnamed "less" hands the delta back to
//  everyone.
//

import XCTest
@testable import DredfitCore

/// Tests whose subject is the deload, a freeze, a hold, a break or the bar
/// branch take their "less" under an already-running series of unnamed ones:
/// there the delta is session-wide (spec §19.2), which is exactly the
/// semantics those tests were written against. The targeting itself is the
/// subject of this file.
extension EngineState {
    var underLessRun: EngineState {
        var copy = self
        copy.lessRun = EngineConfig.lessRunToGlobal
        return copy
    }
}

final class EngineV29Tests: XCTestCase {

    private func seeded(_ level: Int, counter: Int = 0, hasBar: Bool = false) -> EngineState {
        var s = EngineState.initial
        s.counter = counter
        s.hasBar = hasBar
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    // MARK: - the unnamed "less"

    func testAnUnnamedLessTakesDownOneMovementAndHoldsTheRest() throws {
        for level in [1, 7, 8, 20, 31, 32, 40, 47] {
            let state = seeded(level)
            let session = Engine.generateSession(state)
            // levels are equal, so the aim is the first movement of the session
            let aim = try XCTUnwrap(session.exercises.first?.pattern)
            let after = Engine.applyFeedback(state: state, session: session, result: .less)
            var moved = 0
            for ex in session.exercises {
                if ex.pattern == aim {
                    // v2.23 (spec §34.1): the aim steps ONE SUB-STEP back along
                    // the growth path, not one level — and on a block floor
                    // (L mod 8 == 0) it does not move at all: nothing lighter
                    // exists in this variation. Its streak grows either way,
                    // because the streak counts the INTENT (§34.2) — without
                    // that, a deload on a floor would be unreachable and its
                    // owner locked into a variation beyond them.
                    assertDescended(after, ex.pattern, from: Position(level: level, sub: 0), by: 1,
                                    "L=\(level): the aim steps back")
                    XCTAssertEqual(after.failStreak[ex.pattern], 1, "L=\(level): the aim's streak grows")
                    moved += 1
                } else {
                    assertPosition(after, ex.pattern, Position(level: level, sub: 0),
                                   "L=\(level): \(ex.pattern) holds")
                    XCTAssertEqual(after.failStreak[ex.pattern], 0,
                                   "L=\(level): holding is not underperforming")
                }
            }
            XCTAssertEqual(moved, 1, "L=\(level): exactly one movement takes the delta")
            XCTAssertEqual(after.lessRun, 1, "L=\(level): the run of unnamed ratings counts up")
        }
    }

    func testTheAimIsTheHighestLevelNotTheSessionOrder() throws {
        var state = seeded(7)
        let session = Engine.generateSession(state)
        let high = try XCTUnwrap(session.exercises.last?.pattern)
        state.levels[high] = 20
        let after = Engine.applyFeedback(state: state, session: session, result: .less)
        XCTAssertEqual(after.levels[high], 19)
        for ex in session.exercises where ex.pattern != high {
            XCTAssertEqual(after.levels[ex.pattern], state.levels[ex.pattern],
                           "\(ex.pattern) holds while another movement is the aim")
        }
    }

    func testASkippedMovementIsNeverTheAim() throws {
        var state = seeded(7)
        let session = Engine.generateSession(state)
        let skipped = try XCTUnwrap(session.exercises.first?.pattern)
        state.levels[skipped] = 30          // the highest, but it was not trained
        let after = Engine.applyFeedback(state: state, session: session, result: .less,
                                         skipped: [skipped])
        XCTAssertEqual(after.levels[skipped], 30, "a skipped movement keeps its level")
        let fell = session.exercises.filter { after.levels[$0.pattern]! < state.levels[$0.pattern]! }
        XCTAssertEqual(fell.count, 1, "the delta moves to a movement that was actually trained")
    }

    // MARK: - the named "less"

    func testAnExactNumberBelowPlanNamesTheMovementAndSparesTheRest() throws {
        let state = seeded(10)
        let session = Engine.generateSession(state)
        let named = try XCTUnwrap(session.exercises.first(where: { $0.unit == .reps }))
        let after = Engine.applyFeedback(state: state, session: session, result: .less,
                                         overrides: [named.pattern: named.load - 2])
        XCTAssertLessThan(after.levels[named.pattern]!, 10, "the named movement follows its fact")
        for ex in session.exercises where ex.pattern != named.pattern {
            XCTAssertEqual(after.levels[ex.pattern], 10, "\(ex.pattern) holds — it was not named")
        }
        XCTAssertEqual(after.lessRun, 0, "a named rating does not feed the run")
    }

    /// v2.22 (spec §33): re-marked from `testAHoldTakesTheDeltaItselfAnd…`.
    /// The hold is cancelled, so the named signal here is an exact number below
    /// the plan — and the subject is untouched: whoever is NAMED takes the
    /// session-wide "less" alone and everybody else holds.
    func testANamedFactTakesTheDeltaItselfAndKeepsGoingDown() throws {
        let state = seeded(10)
        let session = Engine.generateSession(state)
        let ex0 = try XCTUnwrap(session.exercises.first)
        let named = ex0.pattern
        let after = Engine.applyFeedback(state: state, session: session, result: .less,
                                         overrides: [named: ex0.load - 2])
        XCTAssertLessThan(after.levels[named] ?? 0, 10, "the named movement goes down")
        for ex in session.exercises where ex.pattern != named {
            XCTAssertEqual(after.levels[ex.pattern], 10, "\(ex.pattern) holds its level")
        }
        XCTAssertEqual(after.lessRun, 0)
    }

    // SNIPPED v2.26 (§37.0): `testADiscomfortReportNamesTheMovementToo`.
    // Discomfort was one of the two named signals; it is gone. The claim it
    // made — "a named movement takes the delta alone and the rest are spared"
    // — is carried word for word by
    // `testAnExactNumberBelowPlanNamesTheMovementAndSparesTheRest` above, on
    // the signal that survived. One named signal is left, and saying so is
    // more honest than keeping a second test that no longer has an input.

    func testTheThirdUnnamedLessInARowGoesBackToEveryone() {
        var state = seeded(20)
        var moved: [Int] = []
        for _ in 0..<4 {
            let session = Engine.generateSession(state)
            // v2.23 (spec §34.1): "moved" is counted on the POSITION — a
            // session delta gives back a sub-step, and the level follows only
            // on every third one. The subject (who gets the delta, §19.2) is
            // untouched.
            let before = Dictionary(uniqueKeysWithValues:
                Pattern.allCases.map { ($0, ordinal(state, $0)) })
            let next = Engine.applyFeedback(state: state, session: session, result: .less)
            moved.append(session.exercises.filter { ordinal(next, $0.pattern) < before[$0.pattern]! }.count)
            state = next
        }
        XCTAssertEqual(Array(moved.prefix(2)), [1, 1], "the first two are targeted")
        XCTAssertEqual(Array(moved.suffix(2)),
                       [EngineConfig.patternsPerSession, EngineConfig.patternsPerSession],
                       "from the third the delta is session-wide")
        XCTAssertEqual(state.lessRun, 4)
    }

    func testPlanMoreAndANamedLessAllResetTheRun() throws {
        for label in ["plan", "more", "named"] {
            var state = seeded(20)
            state = Engine.applyFeedback(state: state, session: Engine.generateSession(state), result: .less)
            state = Engine.applyFeedback(state: state, session: Engine.generateSession(state), result: .less)
            XCTAssertEqual(state.lessRun, 2, "\(label): setup")
            let session = Engine.generateSession(state)
            let after: EngineState
            switch label {
            case "plan": after = Engine.applyFeedback(state: state, session: session, result: .plan)
            case "more": after = Engine.applyFeedback(state: state, session: session, result: .more)
            default:
                // v2.22 (§33): a named "less" is now named by a fact or by pain.
                let ex0 = try XCTUnwrap(session.exercises.first)
                after = Engine.applyFeedback(state: state, session: session, result: .less,
                                             overrides: [ex0.pattern: ex0.load - 2])
            }
            XCTAssertEqual(after.lessRun, 0, "\(label) resets the run")
        }
    }

    func testABreakDoesNotContinueTheRun() {
        var state = seeded(20)
        state = Engine.applyFeedback(state: state, session: Engine.generateSession(state), result: .less)
        XCTAssertEqual(Engine.applyComeback(state: state, gapDays: 30).lessRun, 0)
        XCTAssertEqual(Engine.applySilentDecay(state: state, gapDays: 9).lessRun, 0)
    }

    // MARK: - what must not change

    func testPlanAndMorePathsAreUntouched() {
        for result in [FeedbackResult.plan, .more] {
            let state = seeded(10)
            let session = Engine.generateSession(state)
            let after = Engine.applyFeedback(state: state, session: session, result: result)
            for ex in session.exercises {
                // v2.22 (spec §33): in SUB-STEPS.
                let cap = EngineConfig.maxUp(pattern: ex.pattern, tier: Level.decode(10).tier)
                assertPosition(after, ex.pattern,
                               Level.rise(level: 10, sub: 0, by: min(result.delta, cap)),
                               "\(result) still moves \(ex.pattern)")
            }
            XCTAssertEqual(after.lessRun, 0)
        }
    }

    /// The fixed points the growth-cap cells used to create: on a more/less
    /// rhythm +1 and −1 cancelled, so the calf never left zero and the pull
    /// stopped at the tier-2 boundary for good.
    func testTheGrowthCapFixedPointsAreOpen() {
        var state = EngineState.initial
        for k in 0..<48 {
            let session = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: session,
                                         result: k.isMultiple(of: 2) ? .more : .less)
        }
        // v2.22 (spec §33): "left zero" is measured on the POSITION — on the
        // lowest sub-steps the level is still zero while the fixed point is
        // already broken.
        XCTAssertGreaterThan(Level.ordinal(state.position(.calf)), 0, "the calf leaves zero")
        XCTAssertGreaterThan(Level.ordinal(state.position(.pull)),
                             Level.ordinal(Position(level: EngineConfig.stepsPerTier, sub: 0)),
                             "the pull does not park on the tier-2 boundary")
    }

    /// The do-no-harm gate: an impossible plan must still come down. Without
    /// the run clause of §19.2 this never reached the target at all.
    /// v2.23 (spec §34.5): the METRIC is re-marked, not the threshold.
    /// Sessions can no longer be counted: one session gives back a sub-step,
    /// not a level, and "11 sessions" would be describing a different
    /// quantity — a guarantee has to be measured in the step the regulator
    /// actually takes. A descent EVENT is an appearance the rating took down:
    /// the position fell, or the streak grew on intent (§34.2). The threshold
    /// is the same 11, and what holds it is the deload — on a block floor the
    /// position stands but the streak builds, and every third appearance drops
    /// the pattern a tier: measured, the ladder runs 20 → 19.x → 16 → 8.
    func testAnImpossiblePlanStillDescends() {
        var state = seeded(20)
        let rotating = Pattern.ordered.filter { $0 != .pull }
        var events = Dictionary(uniqueKeysWithValues: rotating.map { ($0, 0) })
        var worstEvents: Int?
        for _ in 1...40 where worstEvents == nil {
            let before = Dictionary(uniqueKeysWithValues:
                rotating.map { ($0, (ordinal(state, $0), state.failStreak[$0] ?? 0)) })
            state = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                         result: .less)
            for p in rotating where ordinal(state, p) < before[p]!.0
                || (state.failStreak[p] ?? 0) > before[p]!.1 {
                events[p]! += 1
            }
            let avg = Double(rotating.reduce(0) { $0 + (state.levels[$1] ?? 0) }) / Double(rotating.count)
            if avg <= 10 { worstEvents = events.values.max() }
        }
        XCTAssertNotNil(worstEvents)
        XCTAssertLessThanOrEqual(worstEvents ?? .max, 11,
                                 "descent to an average of 10 within 11 descent events")
    }

    func testAStateFileWithoutTheFieldDecodesAsZero() throws {
        let legacy = """
        {"counter":3,"levels":["squat",7,"push_h",7,"hinge",7,"pull",7,"push_v",7,\
        "lunge",7,"core_anti_ext",7,"core_rot",7,"calf",7,"pull_bar",7],\
        "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,\
        "lunge",0,"core_anti_ext",0,"core_rot",0,"calf",0,"pull_bar",0],"hasBar":false}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertEqual(state.lessRun, 0, "a file written before v2.9 reads as a zero run")
        let session = Engine.generateSession(state)
        let after = Engine.applyFeedback(state: state, session: session, result: .less)
        let fell = session.exercises.filter { after.levels[$0.pattern]! < state.levels[$0.pattern]! }
        XCTAssertEqual(fell.count, 1, "and goes down the targeted path")
    }
}
