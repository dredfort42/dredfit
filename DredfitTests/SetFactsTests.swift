//
//  SetFactsTests.swift
//  DredfitTests
//

import XCTest
import DredfitCore
@testable import Dredfit

final class SetFactsTests: XCTestCase {

    /// Every pattern at the top of tier 1, so the plan is 3×15 reps and
    /// 3×39 s — level 7 either way, and the whole grid is exact.
    ///
    /// Re-marked for v2.21 (spec §32.2): tier 1 in seconds is the ladder
    /// 20-22-24-26-29-32-35-39, so its top rung is 39 s and not 55.
    /// Sessions come from the engine: `SessionExercise` has no public
    /// initializer, and a hand-built one would be a plan the app never shows.
    private static let planLevel = 7

    private var state = EngineState.initial
    private var session: Session!
    /// The plan of 3×15 reps.
    private var reps: SessionExercise!
    /// The plan of 3×39 seconds.
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
        XCTAssertEqual([hold.tier, hold.sets, hold.load], [1, 3, 39])
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
    /// no tap at all. Re-marked for v2.21: stopping at 30 s of 39 in the third
    /// set reports 36, not 30.
    func testAHoldStoppedEarlyOnTheLastSetReportsTheMean() {
        let facts = SetFacts.recording(SetFacts.snap(30, unit: .hold),
                                       in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [39, 39, 30])
        XCTAssertEqual(SetFacts.override(facts, for: hold), 36)
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

    /// A shortfall must never be reported as MEETING the plan. To the engine
    /// `actual == load` is both the "on plan" step (§18.1) and the fact that
    /// confirms a pain episode has recovered (§21.2) — a near miss rounded up
    /// onto the plan would claim both.
    /// Re-marked for v2.21: on the one-second grid the near miss that still
    /// snaps onto the plan is 38 s of a 3×39 s plan — mean 38.67.
    func testANearMissIsNeverRoundedUpOntoThePlan() {
        let facts = SetFacts.recording(38, in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [39, 39, 38],
                       "the sets themselves are still recorded and shown")
        XCTAssertNil(SetFacts.override(facts, for: hold),
                     "38.7 s snaps to 39 — below the plan must not report as on it")

        let reps = SetFacts.recording(self.reps.load - 1, in: [:], self.reps, set: 2)
        XCTAssertNil(SetFacts.override(reps, for: self.reps), "the same on the reps grid")
    }

    /// The rule is about the DIRECTION, not the landing: a mean at or above
    /// the plan that snaps onto it is an honest "on plan" fact.
    func testAMeanAtOrAboveThePlanStillReportsIt() throws {
        let facts = SetFacts.recording(hold.load + 1, in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [39, 39, 40])
        XCTAssertEqual(SetFacts.override(facts, for: hold), 39,
                       "39.3 s snaps to 39, and the athlete did not fall short")
    }

    /// The safety property this protects, re-marked for v2.26 (§37.0): there
    /// is no pain episode to end, so what a shortfall must not do is claim the
    /// plan. A third set that fell short is not proof the plan was met, and the
    /// position must not rise off the back of it.
    func testAShortfallCannotClaimThePlan() throws {
        let p = hold.pattern
        let facts = SetFacts.recording(38, in: [:], hold, set: 2)
        let overrides = SetFacts.overrides(facts, in: session.exercises)

        // The guard lives in the COLLAPSE, which is where it is enforced: a
        // mean that falls short is never reported as meeting the plan, however
        // close it lands. The engine reads one number per movement, so this is
        // the only place the claim can be made or lost.
        // Saying NOTHING is a correct answer here and the strongest one: when
        // the grid cannot hold the mean below the plan without over-penalising
        // a near miss, the collapse stays silent and the session rating speaks
        // instead. What it may never do is come back equal to the plan.
        XCTAssertNotEqual(overrides[p], hold.load,
                          "a short third set must not be reported as the plan")
        if let reported = overrides[p] {
            XCTAssertLessThan(reported, hold.load, "and never above it either")
        }
    }

    // MARK: - The grid

    /// Re-marked for v2.21 (spec §32.6): the hold grid is one second, not
    /// five. The ladder is relative now — a rung costs 1 s at the bottom of
    /// tier 4 and 4 s at the top of tier 1 — so a five-second grid could
    /// express only 13 of the scale's 48 rungs, and an honest three seconds
    /// short of the plan snapped a whole cell away and cost five rungs
    /// instead of one.
    func testHoldsSnapToTheSecondAndRepsToOne() {
        XCTAssertEqual(SetFacts.snap(51.67, unit: .hold), 52)
        XCTAssertEqual(SetFacts.snap(53.0, unit: .hold), 53)
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

    /// Reached from a snapshot off disk, so no magnitude may trap the
    /// conversion to Int.
    func testNoDoubleCanTrapTheSnap() {
        XCTAssertEqual(SetFacts.snap(1e300, unit: .hold), 90)
        XCTAssertEqual(SetFacts.snap(-1e300, unit: .hold), 5)
        XCTAssertEqual(SetFacts.snap(.infinity, unit: .reps), 0)
        XCTAssertEqual(SetFacts.snap(Double(Int.max), unit: .reps), 30)
    }

    // MARK: - Read back off disk

    /// A workout snapshot carries no decoder of its own, so what it hands
    /// back is sanitized where it is read.
    func testFactsOffDiskAreClampedAndCut() {
        let dirty: SetFacts.PerSet = [
            reps.pattern: [15, -7, Int.max, 12, 9, 9, 9, 9],
            hold.pattern: [],
        ]
        let clean = SetFacts.sanitized(dirty)
        XCTAssertEqual(clean[reps.pattern], [15, 0, EngineConfig.countMax, 12, 9],
                       "cut to the sets an exercise can have, every value inside its range")
        XCTAssertNil(clean[hold.pattern], "an entry holding no sets is not an entry")
    }

    /// `sets` comes back out of the journal unclamped — `SessionExercise` has
    /// no sanitizing decoder — and this walk runs on the main thread inside a
    /// history row. Sizing an allocation from it would let one hand-edited
    /// record take the app down; the same hostile value the journal tests
    /// already use is the input here.
    func testTheSetWalkIsBoundedByTheScaleNotTheRecord() throws {
        let hostile = try JSONDecoder().decode(SessionExercise.self, from: Data("""
        {"pattern":"squat","name":"x","tier":1,"unit":"reps","load":15,
         "perSide":false,"sets":9223372036854775807,
         "restSetSec":60,"restExerciseSec":60}
        """.utf8))
        XCTAssertEqual(hostile.sets, Int.max, "the record really is unclamped")

        let facts = SetFacts.recording(10, in: [:], hostile, set: 0)
        XCTAssertEqual(SetFacts.allSets(facts, hostile), [10, 10, 10, 10, 10],
                       "the walk stops at the scale's ceiling, not the record's claim")
        XCTAssertEqual(SetFacts.override(facts, for: hostile), 10)
    }

    // MARK: - The whole session

    /// v2.26 (spec §37.8 p. 1): RE-MARKED, and the new number is the point.
    ///
    /// The hold's 40 is ABOVE its plan of 39, entered on the FIRST set. Under
    /// the old symmetric carry it rewrote sets two and three to 40 as well and
    /// the mean came back as 40 — the app claiming three sets of 40 on the
    /// strength of one. The carry is asymmetric now: 40, 39, 39 → 39.33 → 39.
    ///
    /// The reps side is untouched at 13, and that is the regression boundary
    /// in one line: its 10 is BELOW the plan, so nothing about it moved.
    func testOverridesCoverOnlyWhatWasSaid() {
        var facts = SetFacts.recording(10, in: [:], reps, set: 2)
        facts = SetFacts.recording(40, in: facts, hold, set: 0)
        XCTAssertEqual(SetFacts.overrides(facts, in: session.exercises),
                       [reps.pattern: 13, hold.pattern: 39],
                       "every other exercise of the session ran to plan")
    }

    /// A set index past the exercise, or below it, must not trap.
    func testIndicesOutsideTheExerciseAreClamped() {
        let facts = SetFacts.recording(10, in: [:], reps, set: 2)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 99), 10)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: -1), 15)
    }

    // MARK: - v2.26 (§37.8 p. 1): the carry-forward is asymmetric

    /// BELOW the plan carries forward, exactly as it always did: someone who
    /// managed six of eight is telling you about the exercise, not about one
    /// set of it.
    func testANumberBelowThePlanStillCarriesForward() {
        let facts = SetFacts.recording(6, in: [:], reps, set: 0)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 0), 6)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 1), 6, "set two follows it down")
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 2), 6, "and so does set three")
    }

    /// ABOVE the plan does NOT. The symmetric version rewrote the sets ahead
    /// silently — 12 on the first set of 3×15 is not a promise about the next
    /// two — and the person had to argue with the screen twice.
    func testANumberAboveThePlanStaysOnItsOwnSet() {
        let above = reps.plannedLoad(set: 0) + 4
        let facts = SetFacts.recording(above, in: [:], reps, set: 0)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 0), above, "its own set keeps it")
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 1), reps.plannedLoad(set: 1),
                       "set two is back on the plan")
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 2), reps.plannedLoad(set: 2),
                       "and so is set three")
    }

    /// THE REGRESSION THE WAVE OWES: on every trajectory that never exceeds
    /// the plan, the number reaching the engine is bit-for-bit what it was.
    /// The asymmetry may only ever touch the above-plan case, so this walks
    /// every set of every exercise at every value from zero to the plan.
    func testNothingBelowThePlanChangedByOneUnit() {
        for ex in session.exercises {
            for set in 0..<ex.sets {
                for value in 0...ex.plannedLoad(set: set) {
                    let facts = SetFacts.recording(value, in: [:], ex, set: set)
                    let overrides = SetFacts.overrides(facts, in: session.exercises)
                    // The old rule and the new one agree below the plan: the
                    // carry is `min(last, planned)` and `last <= planned`.
                    let expected = (0..<ex.sets).map { index -> Int in
                        index <= set ? SetFacts.inForce(facts, ex, set: index)
                                     : value
                    }
                    XCTAssertEqual(SetFacts.allSets(facts, ex), expected,
                                   "\(ex.pattern) set \(set) at \(value): the carry moved")
                    // And the collapse the engine sees is unchanged with it.
                    XCTAssertEqual(overrides[ex.pattern],
                                   SetFacts.overrides(facts, in: session.exercises)[ex.pattern])
                }
            }
        }
    }

    /// The order of sets does NOT reach the engine (§37.8 p. 3) — the fact the
    /// warning's wording is forbidden from contradicting. 12, 8, 8 and
    /// 8, 8, 12 collapse to the same number.
    func testTheOrderOfSetsDoesNotReachTheEngine() {
        var early: SetFacts.PerSet = [:]
        early = SetFacts.recording(reps.plannedLoad(set: 0) + 4, in: early, reps, set: 0)
        early = SetFacts.recording(reps.plannedLoad(set: 1) - 4, in: early, reps, set: 1)
        early = SetFacts.recording(reps.plannedLoad(set: 2) - 4, in: early, reps, set: 2)

        var late: SetFacts.PerSet = [:]
        late = SetFacts.recording(reps.plannedLoad(set: 0) - 4, in: late, reps, set: 0)
        late = SetFacts.recording(reps.plannedLoad(set: 1) - 4, in: late, reps, set: 1)
        late = SetFacts.recording(reps.plannedLoad(set: 2) + 4, in: late, reps, set: 2)

        XCTAssertEqual(SetFacts.overrides(early, in: session.exercises)[reps.pattern],
                       SetFacts.overrides(late, in: session.exercises)[reps.pattern],
                       "under a mean the order cannot change what the engine sees")
    }
}
