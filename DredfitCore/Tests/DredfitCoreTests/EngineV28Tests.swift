//
//  EngineV28Tests.swift
//  DredfitCoreTests
//
//  The audit's polish wave (spec §18): a fact equal to the plan steps like
//  "on plan", the rest between sets follows the set band, and the last
//  unspecified input combination — discomfort ∧ pinned — gets its rule.
//  Mirrors the corresponding blocks in the reference verifier.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV28Tests: XCTestCase {

    private func seeded(level: Int, counter: Int = 0) -> EngineState {
        var state = EngineState.initial
        state.counter = counter
        for p in Pattern.allCases { state.levels[p] = level }
        return state
    }

    // MARK: - A fact equal to the plan steps like "on plan" (§18.1)

    /// The diligent logger's bug: exact numbers every session used to mean
    /// no progress ever, while a tap moved. Zero included — doing the first
    /// plan exactly is progress too.
    func testFactEqualToThePlanStepsLikeOnPlan() throws {
        let zero = EngineState.initial
        let session = Engine.generateSession(zero)
        let first = try XCTUnwrap(session.exercises.first)
        let done = Engine.applyFeedback(state: zero, session: session, result: .plan,
                                        overrides: [first.pattern: first.load])
        XCTAssertEqual(done.levels[first.pattern], 1,
                       "a fact of 8 against a plan of 8 is the plan done — level 1")

        for level in [1, 5, 12, 20, 33, 46, 47] {
            let state = seeded(level: level)
            let s = Engine.generateSession(state)
            let ex = s.exercises[0]
            let after = Engine.applyFeedback(state: state, session: s, result: .plan,
                                             overrides: [ex.pattern: ex.load])
            XCTAssertEqual(after.levels[ex.pattern], min(level + 1, EngineConfig.levelMax),
                           "L=\(level): an exact-plan fact steps by one")
        }
    }

    /// A fact below the plan at zero still calibrates to zero — the §18.1
    /// comparison is against the plan's load, so the fromActual clamp can
    /// no longer disguise "below plan" as "equal to plan".
    func testFactBelowThePlanAtZeroStillStays() throws {
        let zero = EngineState.initial
        let session = Engine.generateSession(zero)
        let ex = try XCTUnwrap(session.exercises.first { $0.unit == .reps })
        let after = Engine.applyFeedback(state: zero, session: session, result: .plan,
                                         overrides: [ex.pattern: 5])
        XCTAssertEqual(after.levels[ex.pattern], 0)
        XCTAssertEqual(after.failStreak[ex.pattern], 0)
    }

    /// The fact outranks the tap, as always: "tough" plus an exact-plan fact
    /// is still +1 for that movement.
    func testTheFactOutranksTheRating() {
        let state = seeded(level: 10)
        let session = Engine.generateSession(state)
        let ex = session.exercises[0]
        let after = Engine.applyFeedback(state: state, session: session, result: .less,
                                         overrides: [ex.pattern: ex.load])
        XCTAssertEqual(after.levels[ex.pattern], 11,
                       "the exact-plan fact overrides the session rating")
    }

    /// Under a freeze or a hold the growth still clamps to the old level.
    func testExactPlanFactStillHoldsUnderAFreeze() throws {
        var frozen = seeded(level: 10)
        frozen.frozen[.pull] = 2
        let session = Engine.generateSession(frozen)
        let pull = try XCTUnwrap(session.exercises.first { $0.pattern == .pull })
        let after = Engine.applyFeedback(state: frozen, session: session, result: .plan,
                                         overrides: [.pull: pull.load])
        XCTAssertEqual(after.levels[.pull], 10, "frozen: the +1 clamps to the old level")

        let pinned = Engine.applyFeedback(state: seeded(level: 10), session: session,
                                          result: .plan, overrides: [.pull: pull.load],
                                          pinned: [.pull])
        XCTAssertEqual(pinned.levels[.pull], 10, "held: same clamp")
    }

    // MARK: - Rest between sets follows the set band (§18.2)

    /// The owner's numbers, cell by cell, and every exercise carries its
    /// band's rest across the whole scale — the app timer reads the field
    /// per exercise and needs no change.
    func testRestBetweenSetsFollowsTheSetBand() {
        XCTAssertEqual(EngineConfig.restSetByBand, [3: 60, 4: 90, 5: 120])
        for level in 0...EngineConfig.levelMax {
            let session = Engine.generateSession(seeded(level: level))
            for ex in session.exercises {
                XCTAssertEqual(ex.restSetSec, EngineConfig.restSetByBand[ex.sets],
                               "L=\(level) \(ex.pattern.rawValue): rest must follow the band")
                XCTAssertEqual(ex.restExerciseSec, EngineConfig.restExerciseSec,
                               "the between-exercise pause is not banded")
            }
        }
    }

    // MARK: - discomfort ∧ pinned: discomfort absorbs (§18.3)

    /// The last unspecified combination, now a rule: both inputs on one
    /// pattern behave exactly as pure discomfort — the session is annulled,
    /// the rest is armed, and the pin adds nothing.
    func testDiscomfortAbsorbsThePinOnTheSamePattern() {
        for result in [FeedbackResult.less, .plan, .more] {
            var state = seeded(level: 14)
            state.failStreak[.squat] = 2
            let session = Engine.generateSession(state)
            let p = session.exercises[0].pattern
            let both = Engine.applyFeedback(state: state, session: session, result: result,
                                            discomfort: [p], pinned: [p])
            let pure = Engine.applyFeedback(state: state, session: session, result: result,
                                            discomfort: [p])
            XCTAssertEqual(both, pure,
                           "\(result): the combination must equal pure discomfort")
            XCTAssertEqual(both.frozen[p], EngineConfig.freezeAppearances)
        }
    }

    /// The difference from a lone pin is visible on "tough": a pinned
    /// movement follows the rating down, the combination does not — the
    /// session was annulled.
    func testTheCombinationIsNotPinnedSemantics() {
        let state = seeded(level: 14)
        let session = Engine.generateSession(state)
        let p = session.exercises[0].pattern
        let both = Engine.applyFeedback(state: state, session: session, result: .less,
                                        discomfort: [p], pinned: [p])
        let pinnedOnly = Engine.applyFeedback(state: state, session: session, result: .less,
                                              pinned: [p])
        XCTAssertEqual(both.levels[p], 14, "annulled: the level is untouched")
        XCTAssertEqual(pinnedOnly.levels[p], 13, "a lone pin follows the rating down")
    }
}
