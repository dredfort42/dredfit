//
//  SetFactsTests.swift
//  DredfitTests
//

import XCTest
import DredfitCore
@testable import Dredfit

final class SetFactsTests: XCTestCase {

    /// Every pattern one step below the top of tier 1, so the plan is 3×15
    /// reps and 3×55 s — level 7 either way, and the whole grid is exact.
    /// Sessions come from the engine: `SessionExercise` has no public
    /// initializer, and a hand-built one would be a plan the app never shows.
    private static let planLevel = 7

    private var state = EngineState.initial
    private var session: Session!
    /// The plan of 3×15 reps.
    private var reps: SessionExercise!
    /// The plan of 3×55 seconds.
    private var hold: SessionExercise!

    override func setUpWithError() throws {
        try super.setUpWithError()
        for p in Pattern.allCases { state.levels[p] = Self.planLevel }
        // The second session, not the first: the rotation puts no hold in
        // session one, and half of what is being tested here is a hold.
        state.counter = 1
        session = Engine.generateSession(state)
        reps = try XCTUnwrap(session.exercises.first { $0.unit == .reps })
        hold = try XCTUnwrap(session.exercises.first { $0.unit == .hold })
        // The numbers below are read off the encoding, not off the fixture:
        // if the generator ever moves, these fail here rather than silently
        // testing arithmetic about some other plan.
        XCTAssertEqual([reps.tier, reps.sets, reps.load], [1, 3, 15])
        XCTAssertEqual([hold.tier, hold.sets, hold.load], [1, 3, 55])
    }

    // MARK: - Nothing said

    func testNoFactsRunToPlan() {
        XCTAssertEqual(SetFacts.inForce([:], reps, set: 0), 15)
        XCTAssertEqual(SetFacts.inForce([:], reps, set: 2), 15)
        XCTAssertEqual(SetFacts.allSets([:], reps), [15, 15, 15])
        XCTAssertNil(SetFacts.override([:], for: reps))
        XCTAssertEqual(SetFacts.overrides([:], in: [reps, hold]), [:])
    }

    // MARK: - The reported bug

    /// The whole reason this shape exists: 10 entered on the LAST set of
    /// 3×15 must leave the two sets already done at 15.
    func testAFactOnTheLastSetLeavesTheEarlierOnesAlone() {
        let facts = SetFacts.recording(10, in: [:], reps, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, reps), [15, 15, 10])
        XCTAssertEqual(SetFacts.override(facts, for: reps), 13)
    }

    /// The same for a hold stopped early — the path that records itself with
    /// no tap at all. Stopping at 40 s of 55 in the third set reports 50,
    /// not 40.
    func testAHoldStoppedEarlyOnTheLastSetReportsTheMean() {
        let facts = SetFacts.recording(SetFacts.snap(40, unit: .hold),
                                       in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [55, 55, 40])
        XCTAssertEqual(SetFacts.override(facts, for: hold), 50)
    }

    /// What the fix is worth, stated as the engine sees it: the old shape
    /// reported the bare 10 and dropped five levels with a failStreak tick;
    /// the mean drops two and the streak still has room.
    func testTheEngineDropsLessAndDeloadsLater() throws {
        let p = reps.pattern
        let facts = SetFacts.recording(10, in: [:], reps, set: 2)
        let mean = try XCTUnwrap(SetFacts.override(facts, for: reps))
        let fixed = Engine.applyFeedback(state: state, session: session,
                                         result: .plan, overrides: [p: mean])
        let old = Engine.applyFeedback(state: state, session: session,
                                       result: .plan, overrides: [p: 10])

        XCTAssertEqual(old.levels[p], 2, "the shape this fix replaces")
        XCTAssertEqual(fixed.levels[p], 5, "two sets on plan are not a full shortfall")
        XCTAssertEqual(fixed.failStreak[p], 1)
    }

    // MARK: - Carrying forward

    /// A number entered on the first set is what the screen then shows and
    /// what the hold then counts down, so it IS what the later sets ran at.
    func testAFactOnTheFirstSetCarriesForward() {
        let facts = SetFacts.recording(10, in: [:], reps, set: 0)
        XCTAssertEqual(SetFacts.allSets(facts, reps), [10, 10, 10])
        XCTAssertEqual(SetFacts.override(facts, for: reps), 10)
    }

    func testTheSecondFactOverridesOnlyFromItsOwnSet() {
        var facts = SetFacts.recording(12, in: [:], reps, set: 0)
        facts = SetFacts.recording(9, in: facts, reps, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, reps), [12, 12, 9])
        XCTAssertEqual(SetFacts.override(facts, for: reps), 11)
    }

    /// Correcting the set under way, twice, must not lengthen the record.
    func testRewritingTheSameSetReplacesIt() {
        var facts = SetFacts.recording(10, in: [:], reps, set: 1)
        facts = SetFacts.recording(12, in: facts, reps, set: 1)
        XCTAssertEqual(SetFacts.allSets(facts, reps), [15, 12, 12])
    }

    // MARK: - Back to the plan

    func testEverythingBackOnPlanIsNothingSaid() {
        var facts = SetFacts.recording(10, in: [:], reps, set: 0)
        facts = SetFacts.recording(15, in: facts, reps, set: 0)
        XCTAssertNil(facts[reps.pattern], "the rating governs the pattern again")
        XCTAssertNil(SetFacts.override(facts, for: reps))
    }

    /// One set corrected back while another still differs is still a fact.
    func testOnePlanSetAmongOthersIsStillAFact() {
        var facts = SetFacts.recording(10, in: [:], reps, set: 0)
        facts = SetFacts.recording(15, in: facts, reps, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, reps), [10, 10, 15])
        XCTAssertEqual(SetFacts.override(facts, for: reps), 12)
    }

    /// A mean landing back ON the plan is still evidence: §18.1 gives it the
    /// "on plan" step rather than letting the rating decide.
    func testAMeanBackOnThePlanIsStillReported() {
        let facts = SetFacts.recording(50, in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [55, 55, 50])
        XCTAssertEqual(SetFacts.override(facts, for: hold), 55)
    }

    // MARK: - The grid

    func testHoldsSnapToTheFiveSecondStepAndRepsToOne() {
        XCTAssertEqual(SetFacts.snap(51.67, unit: .hold), 50)
        XCTAssertEqual(SetFacts.snap(53.0, unit: .hold), 55)
        XCTAssertEqual(SetFacts.snap(13.33, unit: .reps), 13)
        XCTAssertEqual(SetFacts.snap(13.5, unit: .reps), 14)
    }

    func testTheCorridorsHold() {
        XCTAssertEqual(SetFacts.snap(3, unit: .hold), 5)
        XCTAssertEqual(SetFacts.snap(400, unit: .hold), 90)
        XCTAssertEqual(SetFacts.snap(-4, unit: .reps), 0)
        XCTAssertEqual(SetFacts.snap(99, unit: .reps), 30)
        XCTAssertEqual(SetFacts.snap(.nan, unit: .reps), 0)
    }

    // MARK: - The whole session

    func testOverridesCoverOnlyWhatWasSaid() {
        var facts = SetFacts.recording(10, in: [:], reps, set: 2)
        facts = SetFacts.recording(40, in: facts, hold, set: 0)
        XCTAssertEqual(SetFacts.overrides(facts, in: session.exercises),
                       [reps.pattern: 13, hold.pattern: 40],
                       "every other exercise of the session ran to plan")
    }

    /// A set index past the exercise, or below it, must not trap.
    func testIndicesOutsideTheExerciseAreClamped() {
        let facts = SetFacts.recording(10, in: [:], reps, set: 2)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 99), 10)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: -1), 15)
    }
}
