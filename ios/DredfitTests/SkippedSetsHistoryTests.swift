import XCTest
import DredfitCore
@testable import Dredfit

/// The history line of a record that names its skipped sets, beside the sets
/// a workout ended before reaching — counted, never named, and never printed
/// as sets that ran.
extension WorkoutSessionTests {

    /// A 4×8 squat — the top of its ladder, the only rung that takes a fourth
    /// set — in the store's own state: session 1 opens on it.
    func fourSetSquatFlow() throws -> (WorkoutSession, AppStore) {
        var state = EngineState.initial
        state.vars[.squat] = Library.count(.squat)
        state.doses[.squat] = 8
        state.sets[.squat] = 4
        let store = makeStore()
        store.update(refreshWidget: false) { $0.engineState = state }
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = try index(of: .squat, in: flow)
        XCTAssertEqual(flow.exercise.unit, .reps, "the premise: reps")
        XCTAssertEqual([flow.exercise.sets, flow.exercise.load], [4, 8], "the premise: 4×8")
        XCTAssertNil(flow.exercise.loads)
        return (flow, store)
    }

    /// Set 1 at 6, set 2 skipped with nothing entered for it, set 3 done at
    /// the 6 in force for it, and set 4 in front of the person.
    func sixSkippedSixToTheFourthSet(_ flow: WorkoutSession) {
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        flow.skipRest()
        XCTAssertEqual(flow.setIndex, 3)
        XCTAssertEqual(flow.actuals[.squat], [6])
    }

    /// …then "Finish now": set 4 was never reached. The record counts two sets
    /// off and names one; the history line is the two sets that ran, 2×6 —
    /// not a third 6 for a set nobody got to.
    func testTheHistoryLineLeavesOutASetFinishNowNeverReached() throws {
        let (flow, store) = try fourSetSquatFlow()
        let squat = flow.exercise
        sixSkippedSixToTheFourthSet(flow)
        flow.finishNow()
        _ = flow.rate(.plan)
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.setsSkipped?[.squat], 2)
        XCTAssertEqual(record.skippedSetIndices?[.squat], [1])
        XCTAssertEqual(HistorySheet.setFacts(squat, in: record)?.values, [6, 6])
    }

    /// The same workout forgotten on set 4 and settled later.
    func testTheHistoryLineLeavesOutASetAForgottenWorkoutNeverReached() throws {
        let (flow, store) = try fourSetSquatFlow()
        let squat = flow.exercise
        sixSkippedSixToTheFourthSet(flow)
        let snap = try XCTUnwrap(store.pendingWorkout)
        XCTAssertTrue(store.settleAbandonedWorkout(now: snap.savedAt + WorkoutSessionStore.forgottenAfter))
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.setsSkipped?[.squat], 2)
        XCTAssertEqual(HistorySheet.setFacts(squat, in: record)?.values, [6, 6])
    }

    /// A skipped set that kept its number is still a named skip, so the count
    /// past the named ones is still only the set never reached: 8, a skipped
    /// set with its 6, the 6 in force for set 3, set 4 never reached — 8-6-6.
    func testANumberedSkipLeavesTheCountOfSetsNeverReachedRight() throws {
        let (flow, store) = try fourSetSquatFlow()
        let squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        enterSixAndSkipTheSet(flow)
        flow.completeSet()
        flow.skipRest()
        flow.finishNow()
        _ = flow.rate(.plan)
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.setsSkipped?[.squat], 2)
        XCTAssertEqual(HistorySheet.setFacts(squat, in: record)?.values, [8, 6, 6])
    }

    /// The cut never goes below what was recorded: 6 entered for set 4, the
    /// set in progress, then "Finish now" — the line keeps it, 8-8-6.
    func testTheHistoryLineKeepsANumberEnteredForTheSetInProgress() throws {
        let (flow, store) = try fourSetSquatFlow()
        let squat = flow.exercise
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        flow.skipRest()
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.finishNow()
        _ = flow.rate(.plan)
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.setsSkipped?[.squat], 2)
        XCTAssertEqual(HistorySheet.setFacts(squat, in: record)?.values, [8, 8, 6])
    }
}
