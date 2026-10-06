import XCTest
import DredfitCore
@testable import Dredfit

/// A number the person entered for a set is never discarded by skipping it —
/// whatever the number, and however the set is skipped.
extension WorkoutSessionTests {

    /// "Went differently" → `value` → OK on the set in front of the person.
    func enter(_ value: Int, _ flow: WorkoutSession) {
        flow.startAdjusting()
        flow.adjustValue = value
        flow.commitSetEdit()
    }

    /// A number on the plan is a number too: "8, entered 8 then Skip this
    /// set, 6" on 3×8 is 8, 8, 6 — 7.33, and the history reads 8-8-6 — though
    /// a record that lands back on the plan leaves nothing in the facts.
    func testANumberEnteredOnThePlanIsKeptBySkippingTheSet() throws {
        let (flow, store) = try squatFlow()
        let squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        enter(8, flow)
        XCTAssertNil(flow.actuals[.squat], "the premise: a number on the plan leaves no record")
        flow.skipSet()
        enter(6, flow)
        XCTAssertEqual(try XCTUnwrap(flow.overrides[.squat]), 22.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(flow.actualSets[.squat], [8, 8, 6])
        flow.completeSet()
        flow.finishNow()
        _ = flow.rate(.plan)
        XCTAssertEqual(HistorySheet.setFacts(squat, in: try XCTUnwrap(store.records.last))?.values, [8, 8, 6])
    }

    /// The number last confirmed is the one entered: 6, corrected back to 8
    /// before the skip, still counts as the person's 8.
    func testANumberCorrectedBackToThePlanBeforeTheSkipStillCounts() throws {
        let (flow, _) = try squatFlow()
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        enter(8, flow)
        XCTAssertNil(flow.actuals[.squat], "the premise: back on the plan, nothing is left in the facts")
        flow.skipSet()
        enter(6, flow)
        XCTAssertEqual(try XCTUnwrap(flow.overrides[.squat]), 22.0 / 3.0, accuracy: 1e-9)
    }

    /// A number turned on the stepper and never confirmed with OK is not
    /// entered: the skip leaves the set out — 8, 6.
    func testANumberNeverConfirmedIsNotEntered() throws {
        let (flow, _) = try squatFlow()
        flow.completeSet()
        flow.skipRest()
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.skipSet()
        XCTAssertNil(flow.editing)
        enter(6, flow)
        XCTAssertEqual(flow.overrides[.squat], 7)
    }

    /// "8, 8, entered 6 on set 3, Skip the remaining sets" on 4×8, where the
    /// screen offers that escape: set 3 keeps its 6, and set 4 is named with
    /// no number and stays out of the fold, the rating's "actual" and the
    /// history line — 8, 8, 6. "Finish now" there folds set 4 at what was in
    /// force instead (7.0): nobody skipped it.
    func testSkippingTheRemainingSetsKeepsTheNumberOfTheSetInFrontOnly() throws {
        let (flow, store) = try fourSetSquatFlow()
        let squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        XCTAssertTrue(!flow.isLastSet && flow.setsPerformedHere >= EngineConfig.setsFloor,
                      "the premise: the screen offers the escape here")
        flow.skipRestOfExercise()
        XCTAssertEqual(flow.skippedSetIndices[.squat], [2, 3])
        XCTAssertEqual(flow.skippedWithNumber[.squat], [2], "set 4 had no number to keep")
        XCTAssertEqual(try XCTUnwrap(flow.overrides[.squat]), 22.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(flow.actualSets[.squat], [8, 8, 6])
        flow.finishNow()
        _ = flow.rate(.plan)
        XCTAssertEqual(HistorySheet.setFacts(squat, in: try XCTUnwrap(store.records.last))?.values, [8, 8, 6])
    }

    /// The same escape with no number for the set in front — 6 was entered
    /// for set 2 — names both remaining sets with none, and both stay out:
    /// 8, 6.
    func testSkippingTheRemainingSetsWithNoNumberLeavesThemOut() throws {
        let (flow, store) = try fourSetSquatFlow()
        let squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        flow.completeSet()
        flow.skipRest()
        flow.skipRestOfExercise()
        XCTAssertEqual(flow.skippedSetIndices[.squat], [2, 3])
        XCTAssertNil(flow.skippedWithNumber[.squat])
        XCTAssertEqual(flow.overrides[.squat], 7)
        XCTAssertEqual(flow.actualSets[.squat], [8, 6])
        flow.finishNow()
        _ = flow.rate(.plan)
        XCTAssertEqual(HistorySheet.setFacts(squat, in: try XCTUnwrap(store.records.last))?.values, [8, 6])
    }

    /// A process death between the OK and the skip: a number off the plan is
    /// still in the facts, and the skip still keeps it — 8, 6, 6.
    func testANumberOffThePlanSurvivesAProcessDeathBeforeTheSkip() throws {
        let (flow, store) = try squatFlow()
        flow.completeSet()
        flow.skipRest()
        enter(6, flow)
        let back = makeFlow(store, resume: try XCTUnwrap(store.pendingWorkout))
        XCTAssertEqual(back.setIndex, 1)
        back.skipSet()
        back.completeSet()
        XCTAssertEqual(try XCTUnwrap(back.overrides[.squat]), 20.0 / 3.0, accuracy: 1e-9)
    }
}
