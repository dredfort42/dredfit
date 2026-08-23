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

    // SNIPPED v2.26 (§37.0): `testExactPlanFactStillHoldsUnderAFreeze`.
    // The freeze went with the pain channel, and with it the only state in
    // which an exact-plan fact had to clamp instead of growing. The rest of
    // §18.1 — "a fact equal to the plan steps exactly like a tap of plan" —
    // is asserted directly above and is untouched.

    // MARK: - Rest between sets follows the set band (§18.2)

    /// The owner's numbers, cell by cell, and every exercise carries its
    /// band's rest across the whole scale — the app timer reads the field
    /// per exercise and needs no change.
    func testRestBetweenSetsFollowsTheSetBand() {
        // Re-marked for v2.25 (spec §36.9): the table gained the 1–2 rungs.
        // They inherit a triple's pause instead of falling through to the
        // shared default — before the fix a cut handed back 60 s where band 5
        // asks for 120, i.e. a REST SHORTER than before the complaint.
        XCTAssertEqual(EngineConfig.restSetByBand, [1: 60, 2: 60, 3: 60, 4: 90, 5: 120])
        for level in 0...EngineConfig.levelMax {
            let session = Engine.generateSession(seeded(level: level))
            for ex in session.exercises {
                // Re-marked for v2.17 (spec §28.2): the rest reads the TIER as
                // well as the band — a tier-4 movement in band 3 rests 90 s,
                // because the band was never the whole story about difficulty.
                // Re-marked again for v2.25 (§36.9): the BAND IS THE LEVEL'S,
                // not the number of sets shown. The sets handle and the §20.2
                // gate take volume off, not recovery. The expectation is not
                // weakened — it is read off the same level the plan was built
                // from, and the second assertion below pins the direction the
                // old form could not: a trimmed set may never shorten a pause.
                let band = Level.decode(level).sets
                let expected = EngineConfig.restSetByTierBand[ex.tier]?[band]
                    ?? EngineConfig.restSetByBand[band]
                XCTAssertEqual(ex.restSetSec, expected,
                               "L=\(level) \(ex.pattern.rawValue): rest must follow tier and band")
                let ifTrimmed = EngineConfig.restSetByTierBand[ex.tier]?[ex.sets]
                    ?? EngineConfig.restSetByBand[ex.sets] ?? EngineConfig.restSetSec
                XCTAssertGreaterThanOrEqual(ex.restSetSec, ifTrimmed,
                                            "a trimmed set may not shorten the pause")
                XCTAssertEqual(ex.restExerciseSec, EngineConfig.restExerciseSec,
                               "the between-exercise pause is not banded")
            }
        }
    }

    // MARK: - Discomfort is the only way into the freeze (v2.22, §33)

    // SNIPPED v2.26 (§37.0): `testDiscomfortAnnulsAndUnloadsAtEveryRating`.
    // Its subject was the PRIORITY of an input that no longer exists — "a
    // report annuls the session and takes the load off at any rating". §18.3
    // ("discomfort and hold together") had already been dropped in v2.22
    // when the second entrance went; this is the first one going.
}
