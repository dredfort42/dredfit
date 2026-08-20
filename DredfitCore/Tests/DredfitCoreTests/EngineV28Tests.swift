//
//  EngineV28Tests.swift
//  DredfitCoreTests
//
//  The audit's polish wave (spec §18): a fact equal to the plan steps like
//  "on plan" and the rest between sets follows the set band.
//  Mirrors the corresponding blocks in the reference verifier.
//
//  v2.22 (spec §33): §18.3 — the rule for "discomfort ∧ hold this level" — is
//  cancelled together with the second input, so the two tests that carried it
//  are gone and what they also covered (discomfort annuls and unloads at any
//  rating) is asserted directly below.
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
        // v2.22 (spec §33): the plan done is worth one SUB-STEP, not a level.
        assertPosition(done, first.pattern, Level.rise(level: 0, sub: 0, by: 1),
                       "a fact of 8 against a plan of 8 is the plan done")

        for level in [1, 5, 12, 20, 33, 46, 47] {
            let state = seeded(level: level)
            let s = Engine.generateSession(state)
            let ex = s.exercises[0]
            let after = Engine.applyFeedback(state: state, session: s, result: .plan,
                                             overrides: [ex.pattern: ex.load])
            assertPosition(after, ex.pattern, Level.rise(level: level, sub: 0, by: 1),
                           "L=\(level): an exact-plan fact steps by one sub-step")
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
        assertPosition(after, ex.pattern, Level.rise(level: 10, sub: 0, by: 1),
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

        // v2.22 (spec §33): the clamp is on the POSITION — a sub-step is growth
        // too, so a frozen pattern may not collect one either.
        XCTAssertEqual(after.sub[.pull] ?? 0, 0, "frozen: no sub-step either")
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
                // Re-marked for v2.17 (spec §28.2): the rest reads the TIER as
                // well as the band — a tier-4 movement in band 3 rests 90 s,
                // because the band was never the whole story about difficulty.
                let expected = EngineConfig.restSetByTierBand[ex.tier]?[ex.sets]
                    ?? EngineConfig.restSetByBand[ex.sets]
                XCTAssertEqual(ex.restSetSec, expected,
                               "L=\(level) \(ex.pattern.rawValue): rest must follow tier and band")
                XCTAssertEqual(ex.restExerciseSec, EngineConfig.restExerciseSec,
                               "the between-exercise pause is not banded")
            }
        }
    }

    // MARK: - Discomfort is the only way into the freeze (v2.22, §33)

    /// §18.3 existed to settle one combination of two inputs. The second input
    /// is cancelled, so the combination cannot be formed — and what the pair of
    /// tests also asserted survives here: a discomfort report annuls the
    /// session, unloads to the current tier's floor and arms the rest at ANY
    /// rating, sub-step included.
    func testDiscomfortAnnulsAndUnloadsAtEveryRating() {
        for result in [FeedbackResult.less, .plan, .more] {
            var state = seeded(level: 14)
            state.failStreak[.squat] = 2
            state.sub[.squat] = 2
            let session = Engine.generateSession(state)
            let p = session.exercises[0].pattern
            let after = Engine.applyFeedback(state: state, session: session, result: result,
                                             discomfort: [p])
            XCTAssertEqual(after.frozen[p], EngineConfig.freezeAppearances,
                           "\(result): the rest is armed")
            XCTAssertEqual(after.levels[p], Level.tierFloor(14),
                           "\(result): unloaded to the current tier's floor")
            XCTAssertEqual(after.sub[p] ?? 0, 0,
                           "\(result): a descent zeroes the sub-step")
            XCTAssertEqual(after.failStreak[p], 0, "\(result): the streak resets")
        }
    }
}
