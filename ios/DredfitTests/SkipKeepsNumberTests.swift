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
