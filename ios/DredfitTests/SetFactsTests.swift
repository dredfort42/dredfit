import XCTest
import DredfitCore
@testable import Dredfit

final class SetFactsTests: XCTestCase {

    /// Everything at the ceiling of its first variation: 3×15 reps and
    /// 3×45 s, the plan the arithmetic below is written against. Sessions
    /// come from the engine: a hand-built one would be a plan the app never
    /// shows.
    private static let planDose = 15

    private var state = EngineState.initial
    private var session: Session!
    /// The plan of 3×15 reps.
    private var reps: SessionExercise!
    /// The plan of 3×45 seconds.
    private var hold: SessionExercise!

    override func setUpWithError() throws {
        try super.setUpWithError()
        for p in Pattern.allCases {
            state.doses[p] = Dose.grid(Library.unit(p, 1)).max
            // A ceiling offers a PROBE, and a probe would change what
            // "the last set" of these exercises even is. "Hard" was said, so
            // the plan here is three working sets and nothing else.
            state.lastHard.insert(p)
        }
        // The second session, not the first: the rotation puts no hold in
        // session one, and half of what is being tested here is a hold.
        state.counter = 1
        session = Engine.generateSession(state)
        reps = try XCTUnwrap(session.exercises.first { $0.unit == .reps })
        hold = try XCTUnwrap(session.exercises.first { $0.unit == .hold })
        // The plan is checked against what the generator produced, not
        // assumed: if the generator ever moves, these fail here rather than
        // silently testing arithmetic about some other plan.
        XCTAssertEqual([reps.variation, reps.sets, reps.load], [1, 3, Self.planDose])
        XCTAssertEqual([hold.variation, hold.sets, hold.load], [1, 3, 45])
        XCTAssertNil(reps.probe)
        XCTAssertNil(hold.probe)
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
    ///
    /// The mean of 15-15-10 is 13⅓, and the fraction is what travels: it is
    /// the only thing that tells "took the top set of an uneven plan" apart
    /// from "did not". Rounded here, the engine would have to substitute the
    /// plan's top into the journal instead — a dose that was in none of the
    /// sets. The integer is what gets STORED, one step later, so the second
    /// assert keeps 13 where it belongs.
    func testAFactOnTheLastSetLeavesTheEarlierOnesAlone() throws {
        let facts = SetFacts.recording(10, in: [:], reps, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, reps), [15, 15, 10])
        let mean = try XCTUnwrap(SetFacts.override(facts, for: reps))
        XCTAssertEqual(mean, 40.0 / 3.0, accuracy: 1e-9, "the fraction reaches the engine")
        XCTAssertEqual(SetFacts.snap(mean, unit: reps.unit), 13, "and an integer is stored")
    }

    /// The same for a hold stopped early — the path that records itself with
    /// no tap at all. Stopping at 30 s of 45 in the third set reports the mean
    /// of 40, not the 30.
    func testAHoldStoppedEarlyOnTheLastSetReportsTheMean() {
        let facts = SetFacts.recording(SetFacts.snap(30, unit: .hold),
                                       in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [45, 45, 30])
        XCTAssertEqual(SetFacts.override(facts, for: hold), 40)
    }

    /// What the mean is worth, stated as the engine sees it: a bare 10 would
    /// drop the dose five rungs; the mean drops it two, and the streak still
    /// has room.
    func testTheEngineDropsLessAndDeloadsLater() throws {
        let p = reps.pattern
        let facts = SetFacts.recording(10, in: [:], reps, set: 2)
        let mean = try XCTUnwrap(SetFacts.override(facts, for: reps))
        let fixed = Engine.applyFeedback(state: state, session: session,
                                         result: .plan, overrides: [p: mean])
        let old = Engine.applyFeedback(state: state, session: session,
                                       result: .plan, overrides: [p: 10])

        // The mean of 15/15/10 lands as 13; a flat 10 is the shape the mean
        // replaces. The next showing IS the number reported.
        XCTAssertEqual(old.doses[p], 10, "the shape this fix replaces")
        XCTAssertEqual(fixed.doses[p], 13, "two sets on plan are not a full shortfall")
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
    ///
    /// 10-10-15 means 11⅔. What the test is about is the DIRECTION — this fell
    /// short of the plan — so that is asserted in its own right rather than
    /// left to be read off a rounded number.
    func testOnePlanSetAmongOthersIsStillAFact() throws {
        var facts = SetFacts.recording(10, in: [:], reps, set: 0)
        facts = SetFacts.recording(15, in: facts, reps, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, reps), [10, 10, 15])
        let mean = try XCTUnwrap(SetFacts.override(facts, for: reps))
        XCTAssertEqual(mean, 35.0 / 3.0, accuracy: 1e-9)
        XCTAssertLessThan(mean, Double(reps.load), "and it is still short of the plan")
    }

    /// A shortfall must never be reported as MEETING the plan. On the
    /// one-second reporting grid the near miss that still snaps onto the plan
    /// is 44 s of a 3×45 s plan — mean 44⅔. Rounded up to 45 it would read to
    /// the engine as the plan met; handed over raw it misses `metPlan`, which
    /// compares the raw value, and the engine snaps a fact DOWN to its grid —
    /// one second short would cost the plan a whole rung, 45 s to 40. So the
    /// collapse reports nothing, and the session rating governs.
    func testANearMissIsNeverRoundedUpOntoThePlan() {
        let facts = SetFacts.recording(44, in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [45, 45, 44],
                       "the sets themselves are still recorded and shown")
        XCTAssertNil(SetFacts.override(facts, for: hold),
                     "44.7 s snaps to 45 — below the plan must not report as on it")

        let reps = SetFacts.recording(self.reps.load - 1, in: [:], self.reps, set: 2)
        XCTAssertNil(SetFacts.override(reps, for: self.reps), "the same on the reps grid")
    }

    /// The rule is about the DIRECTION, not the landing: a mean at or above
    /// the plan that snaps onto it is an honest "on plan" fact.
    ///
    /// The mean is 45⅓ and travels as 45⅓; what the rule is about is that it
    /// is not BELOW the plan, so that is what the second assert says.
    func testAMeanAtOrAboveThePlanStillReportsIt() throws {
        let facts = SetFacts.recording(hold.load + 1, in: [:], hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [45, 45, 46])
        let mean = try XCTUnwrap(SetFacts.override(facts, for: hold))
        XCTAssertEqual(mean, 136.0 / 3.0, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(mean, Double(hold.load),
                                    "the athlete did not fall short")
    }

    /// The safety property this protects: a shortfall must not claim the
    /// plan. A third set that fell short is not proof the plan was met, and
    /// the position must not rise off the back of it.
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
        // The collapse hands over the RAW mean, a Double, and the engine puts
        // it on the grid. The comparison is in the same units: a shortfall
        // cannot be reported as the plan done.
        XCTAssertNotEqual(overrides[p], Double(hold.load),
                          "a short third set must not be reported as the plan")
        if let reported = overrides[p] {
            XCTAssertLessThan(reported, Double(hold.load), "and never above it either")
        }
    }

    // MARK: - The grid

    /// The reporting grid for holds is one second, finer than the five-second
    /// grid the plan is set on.
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

    /// The hold's 46 is ABOVE its plan of 45, entered on the FIRST set. The
    /// carry is asymmetric: a surplus stays on its own set, so the hold runs
    /// 46, 45, 45 and its mean is 45⅓. A symmetric carry would rewrite sets
    /// two and three to 46 as well — the app claiming three sets of 46 on the
    /// strength of one.
    ///
    /// The reps side is the control: its 10 is BELOW the plan and on the last
    /// set, so the carry has nothing to decide there — 15, 15, 10, mean 13⅓.
    func testOverridesCoverOnlyWhatWasSaid() throws {
        var facts = SetFacts.recording(10, in: [:], reps, set: 2)
        facts = SetFacts.recording(46, in: facts, hold, set: 0)
        let overrides = SetFacts.overrides(facts, in: session.exercises)
        XCTAssertEqual(Set(overrides.keys), [reps.pattern, hold.pattern],
                       "every other exercise of the session ran to plan")
        XCTAssertEqual(try XCTUnwrap(overrides[reps.pattern]), 40.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(overrides[hold.pattern]), 136.0 / 3.0, accuracy: 1e-9)
    }

    // MARK: - The probe set

    /// A probe tapped through on a plain "Done" counts as its target — "tapped
    /// Done" means "did as asked" everywhere in the app. If it recorded
    /// nothing, a probe in reps could only be resolved through the adjust
    /// panel, and anyone who simply taps would never enter a new variation.
    func testTappingThroughAProbeRecordsItsTarget() {
        let probes = SetFacts.recordingProbe([:], reps.pattern, isProbe: true, target: 5)
        XCTAssertEqual(probes[reps.pattern], 5, "a tapped probe did the target it asked for")
    }

    /// The other half, and the one a refactor is likelier to lose: nothing
    /// ELSE records itself. An ordinary set tapped through says nothing, and
    /// the session's rating governs the movement.
    func testAnOrdinarySetStillRecordsNothing() {
        XCTAssertEqual(SetFacts.recordingProbe([:], reps.pattern, isProbe: false, target: 5), [:],
                       "only the probe reports itself on a bare tap")
    }

    /// A number entered by hand is more precise than "as asked" and wins —
    /// including a shortfall, which is the whole point of the adjust panel.
    func testANumberEnteredForTheProbeIsNotOverwritten() {
        let entered: [Pattern: Int] = [reps.pattern: 3]
        XCTAssertEqual(SetFacts.recordingProbe(entered, reps.pattern, isProbe: true, target: 5),
                       entered, "the panel's number outranks the target")
    }

    /// A set index past the exercise, or below it, must not trap.
    func testIndicesOutsideTheExerciseAreClamped() {
        let facts = SetFacts.recording(10, in: [:], reps, set: 2)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 99), 10)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: -1), 15)
    }

    // MARK: - The carry-forward is asymmetric

    /// BELOW the plan carries forward: someone who managed six of eight is
    /// telling you about the exercise, not about one set of it.
    func testANumberBelowThePlanStillCarriesForward() {
        let facts = SetFacts.recording(6, in: [:], reps, set: 0)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 0), 6)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 1), 6, "set two follows it down")
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 2), 6, "and so does set three")
    }

    /// ABOVE the plan does NOT. Carried, it would rewrite the sets ahead
    /// silently — 12 on the first set of 3×15 is not a promise about the next
    /// two — and the person would have to argue with the screen twice.
    func testANumberAboveThePlanStaysOnItsOwnSet() {
        let above = reps.plannedLoad(set: 0) + 4
        let facts = SetFacts.recording(above, in: [:], reps, set: 0)
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 0), above, "its own set keeps it")
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 1), reps.plannedLoad(set: 1),
                       "set two is back on the plan")
        XCTAssertEqual(SetFacts.inForce(facts, reps, set: 2), reps.plannedLoad(set: 2),
                       "and so is set three")
    }

    /// On every trajectory that never exceeds the plan, the carry is the plain
    /// one and the engine is handed the mean of the sets that ran — or
    /// nothing, when every set ran on plan or the mean is a near miss that
    /// snaps back onto it. The asymmetry may only ever touch the above-plan
    /// case, so this walks every set of every exercise at every value from
    /// zero to the plan.
    ///
    /// Both expected values are computed here, from the trajectory, not from
    /// `SetFacts.inForce` — the very function `allSets` is a map over — or
    /// from a second call of `SetFacts.overrides`: either way the sweep would
    /// be `f(x) == f(x)` and could not fail. Whether the engine is expected to
    /// get the mean or nothing is read off the record and `SetFacts.snap`.
    func test_nothingBelowThePlan_atEverySetAndValue_reachesTheEngineUnchanged() throws {
        for ex in session.exercises {
            // Spelling the expectation out per set is only legitimate on a
            // UNIFORM plan: `setUp` puts no sub-step in the state, so every set
            // asks for the same dose. An uneven plan would need the carry's own
            // fill rule, which is what made reading it back off `inForce`
            // tempting in the first place.
            XCTAssertNil(ex.loads, "\(ex.pattern): the sweep assumes a uniform plan")
            for set in 0..<ex.sets {
                for value in 0...ex.plannedLoad(set: set) {
                    let facts = SetFacts.recording(value, in: [:], ex, set: set)
                    // Below the plan the carry is the plain one: the
                    // sets before ran silently on plan, the set itself ran at
                    // `value`, and `value <= planned` carries onto every set
                    // after it (`min(last, planned) == last`).
                    let expected = (0..<ex.sets).map { index in
                        index < set ? ex.plannedLoad(set: index) : value
                    }
                    XCTAssertEqual(SetFacts.allSets(facts, ex), expected,
                                   "\(ex.pattern) set \(set) at \(value): the carry moved")

                    // And the collapse is the mean of exactly those sets —
                    // counted here, never asked for a second time.
                    let mean = Double(expected.reduce(0, +)) / Double(expected.count)
                    let overrides = SetFacts.overrides(facts, in: session.exercises)
                    // Two ways to report nothing, both correct: every set landed
                    // on the plan, so there is no fact at all; or the mean falls
                    // short of the plan yet snaps back onto it, and a shortfall
                    // must never be reported as MEETING the plan.
                    let nearMiss = mean < Double(ex.load)
                        && SetFacts.snap(mean, unit: ex.unit) >= ex.load
                    if facts[ex.pattern] == nil || nearMiss {
                        XCTAssertNil(overrides[ex.pattern],
                                     "\(ex.pattern) set \(set) at \(value): "
                                     + "nothing was said, so nothing may be reported")
                    } else {
                        XCTAssertEqual(try XCTUnwrap(overrides[ex.pattern]), mean, accuracy: 1e-9,
                                       "\(ex.pattern) set \(set) at \(value): "
                                       + "the engine is handed the mean of the sets that ran")
                    }
                }
            }
        }
    }

    /// The order of sets does NOT reach the engine — the fact the warning's
    /// wording is forbidden from contradicting. 12, 8, 8 and 8, 8, 12 collapse
    /// to the same number.
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

    // MARK: - "The whole plan, or more" (the gate on the "easy" rating)

    private func didFullPlan(_ facts: SetFacts.PerSet = [:],
                             skips: SetFacts.Skips = [:],
                             skipped: Set<Pattern> = []) -> Bool {
        SetFacts.didFullPlan(facts, skips: skips, skipped: skipped, in: session.exercises)
    }

    func testSayingNothingIsTheWholePlan() {
        // The convention the whole app rests on: a tap through means the plan
        // was done. Nothing recorded is therefore the passing case, not the
        // failing one — a gate that read silence as a shortfall would dim the
        // card for everyone who never opens the adjuster.
        XCTAssertTrue(didFullPlan())
    }

    func testANumberAbovePlanIsStillTheWholePlan() {
        let facts = SetFacts.recording(Self.planDose + 3, in: [:], reps, set: 0)
        XCTAssertTrue(didFullPlan(facts), "“or more” has to mean more")
    }

    func testOneSetUnderPlanClosesTheGate() {
        let facts = SetFacts.recording(Self.planDose - 1, in: [:], reps, set: 2)
        XCTAssertFalse(didFullPlan(facts))
    }

    func testASurplusOnOneExerciseDoesNotPayForAShortfallOnAnother() {
        // Volume is judged PER EXERCISE. Fourteen extra reps of one movement
        // do not buy a missing rep of another: they are different tissues, and
        // the rating they would unlock speaks about all six at once.
        var facts = SetFacts.recording(Self.planDose - 1, in: [:], reps, set: 0)
        facts = SetFacts.recording(hold.plannedLoad(set: 0) + 20, in: facts, hold, set: 0)
        XCTAssertFalse(didFullPlan(facts))
    }

    func testASkippedSetClosesTheGateEvenWithNothingElseSaid() {
        // The one shortfall the engine does NOT already keep the rating away
        // from: a dropped set never becomes an override, so without this the
        // tap would buy the full rise on a movement that lost a third of its
        // volume. This assertion is the whole reason the screen is handed the
        // skips at all.
        XCTAssertFalse(didFullPlan(skips: [reps.pattern: 1]))
        XCTAssertTrue(didFullPlan(skips: [reps.pattern: 0]),
                      "a count of no skipped sets is not a skip")
    }

    func testASkippedExerciseClosesTheGate() {
        XCTAssertFalse(didFullPlan(skipped: [reps.pattern]))
    }

    func testAnUnevenPlanNeedsItsTopSet() {
        // In the gate's own terms: 9-8-8 done as written passes, and 8-8-8
        // does not. The mean would let the top set be traded against the
        // two below it — volume will not.
        // Off a CLEAN state, not this suite's: the sub-step is disabled on the
        // top rung of a grid, which is exactly where `setUp` puts
        // everything, so an uneven plan cannot be built there at all.
        var uneven = EngineState.initial
        uneven.counter = 1
        uneven.sub[reps.pattern] = 1                      // one rung split across sets
        let session = Engine.generateSession(uneven)
        guard let ex = session.exercises.first(where: { $0.pattern == reps.pattern }),
              let loads = ex.loads, Set(loads).count > 1 else {
            return XCTFail("the sub-step did not produce an uneven plan")
        }
        let asWritten = (0..<ex.sets).reduce(SetFacts.PerSet()) {
            SetFacts.recording(ex.plannedLoad(set: $1), in: $0, ex, set: $1)
        }
        XCTAssertTrue(SetFacts.didFullPlan(asWritten, skips: [:], skipped: [],
                                           in: [ex]))
        let flattened = (0..<ex.sets).reduce(SetFacts.PerSet()) {
            SetFacts.recording(loads.min()!, in: $0, ex, set: $1)
        }
        XCTAssertFalse(SetFacts.didFullPlan(flattened, skips: [:], skipped: [],
                                            in: [ex]),
                       "the top set is part of the plan")
    }
}
