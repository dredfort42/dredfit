import XCTest
import DredfitCore
@testable import Dredfit

/// A skipped set does not count: it has no card on the summary, and no part
/// in the fold the engine takes, the rating screen's "actual" or the history
/// line. A set the workout ended before reaching is not a skipped one.
extension WorkoutSessionTests {

    /// "Plank" 3×30 s in the store's own state: session 2 carries it.
    func plankFlow() throws -> (WorkoutSession, AppStore) {
        var state = EngineState.initial
        state.counter = 1
        state.vars[.coreAntiExt] = 3
        state.doses[.coreAntiExt] = 30
        let store = makeStore()
        store.update(refreshWidget: false) { $0.engineState = state }
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = try index(of: .coreAntiExt, in: flow)
        XCTAssertEqual(flow.exercise.sets, 3, "the premise: three sets")
        XCTAssertEqual(flow.exercise.load, 30, "the premise: 30 s each")
        XCTAssertNil(flow.exercise.loads)
        XCTAssertNil(flow.exercise.probe)
        return (flow, store)
    }

    /// "Set the time" 45, set 1 on its clock, the rest after it run out with
    /// nobody there — the run drops, and set 2 waits on its own screen, where
    /// it is skipped — and set 3 on its clock to the summary.
    func declareAndSkipTheMiddleSet(_ flow: WorkoutSession) {
        flow.startDeclaringHoldTime()
        flow.adjustValue = 45
        flow.commitSetEdit()
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 45)
        clock += 600
        flow.tick()
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertFalse(flow.holdUnderWay, "set 2 waits on its own button")
        flow.skipSet()
        flow.startHoldExercise()
        run(flow, until: { flow.phase == .exerciseSummary })
        XCTAssertEqual(flow.actuals[.coreAntiExt], [45, 30, 45], "the premise: the gap reads the plan")
    }

    /// A 3×8 squat in the store's own state: session 1 opens on it.
    func squatFlow() throws -> (WorkoutSession, AppStore) {
        var state = EngineState.initial
        state.doses[.squat] = 8
        let store = makeStore()
        store.update(refreshWidget: false) { $0.engineState = state }
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = try index(of: .squat, in: flow)
        XCTAssertEqual(flow.exercise.unit, .reps, "the premise: reps")
        XCTAssertEqual(flow.exercise.sets, 3, "the premise: three sets")
        XCTAssertEqual(flow.exercise.load, 8, "the premise: 8 each")
        XCTAssertNil(flow.exercise.loads)
        return (flow, store)
    }

    // MARK: - The fold

    /// Set 2 skipped under "Set the time" 45: what the engine takes is the
    /// 45 the two sets held, not the mean of 45, a skipped 30 and 45 — the
    /// summary's preview is the engine's own answer to the honest number.
    func testASkippedHoldSetIsNotFoldedIntoWhatTheEngineTakes() throws {
        let (flow, store) = try plankFlow()
        declareAndSkipTheMiddleSet(flow)
        let honest = try XCTUnwrap(store.previewPlan(
            after: flow.session, pattern: .coreAntiExt, overrides: [.coreAntiExt: 45],
            skipped: [], setsSkipped: [.coreAntiExt: 1], probes: [:], raised: [:]))
        XCTAssertEqual(flow.nextPlan(withAdditions: 0), honest,
                       "the plan from the 45 the two sets held, not from 40")
    }

    /// The same in reps, where the fold is the same code: 3×8 done as "10,
    /// skipped, 8" folds to 9, not 8.67.
    func testASkippedRepsSetIsNotFoldedEither() throws {
        let (flow, store) = try squatFlow()
        flow.startAdjusting()
        flow.adjustValue = 10
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec))
        let honest = try XCTUnwrap(store.previewPlan(
            after: flow.session, pattern: .squat, overrides: [.squat: 9],
            skipped: [], setsSkipped: [.squat: 1], probes: [:], raised: [:]))
        XCTAssertEqual(flow.nextPlan(withAdditions: 0), honest, "10, skipped, 8 is a 9")
    }

    // MARK: - The journal

    /// The history line is the sets that were done: 45 and 45, with no 30
    /// for the set nobody held — and it still is once the journal has been
    /// written to disk and read back.
    func testTheHistoryLineIsTheSetsThatWereDone() throws {
        let (flow, store) = try plankFlow()
        declareAndSkipTheMiddleSet(flow)
        let plank = flow.exercise
        flow.leaveExerciseSummary()
        _ = flow.rate(.plan)
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(HistorySheet.setFacts(plank, in: record)?.values, [45, 45])
        let reread = try XCTUnwrap(makeStore().records.last)
        XCTAssertEqual(reread.skippedSetIndices, [.coreAntiExt: [1]])
        XCTAssertEqual(HistorySheet.setFacts(plank, in: reread)?.values, [45, 45])
    }

    /// A changed rating folds the record again — from the sets that were
    /// done, which the record has to say.
    func testAChangedRatingFoldsOnlyTheSetsThatWereDone() throws {
        let (flow, store) = try plankFlow()
        declareAndSkipTheMiddleSet(flow)
        flow.leaveExerciseSummary()
        _ = flow.rate(.plan)
        store.changeLastRating(to: .less)
        XCTAssertEqual(store.records.last?.actuals?[.coreAntiExt], 45)
    }

    /// The rating hands the engine the session's own fold, the skipped set
    /// left out, and the screen prints the same sets: no view argument
    /// carries the skipped sets to either.
    func testTheRatingHandsTheEngineTheFoldWithoutTheSkippedSet() throws {
        let (flow, store) = try plankFlow()
        declareAndSkipTheMiddleSet(flow)
        flow.leaveExerciseSummary()
        XCTAssertEqual(flow.overrides[.coreAntiExt], 45)
        XCTAssertEqual(flow.actualSets[.coreAntiExt], [45, 45])
        _ = flow.rate(.plan)
        XCTAssertEqual(store.records.last?.actuals?[.coreAntiExt], 45)
    }

    // MARK: - A number entered before a skip

    /// "Went differently" → 6 on the set in front of the person, then "Skip
    /// this set".
    func enterSixAndSkipTheSet(_ flow: WorkoutSession) {
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        flow.skipSet()
    }

    /// "8, entered 6 then Skip this set, 6" on 3×8: the 6 the person entered
    /// is theirs and counts — 8, 6, 6 is 6.67 — while the set still goes off
    /// the plan as a skipped one. A workout settled from there folds the same.
    func testASkippedSetKeepsTheNumberEnteredForIt() throws {
        let (flow, store) = try squatFlow()
        flow.completeSet()
        flow.skipRest()
        enterSixAndSkipTheSet(flow)
        flow.completeSet()
        XCTAssertEqual(flow.setsSkipped[.squat], 1)
        XCTAssertEqual(flow.skippedSetIndices[.squat], [1], "still a skipped set, for the count and the cut")
        XCTAssertEqual(try XCTUnwrap(flow.overrides[.squat]), 20.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(flow.actualSets[.squat], [8, 6, 6])

        let snap = try XCTUnwrap(store.pendingWorkout)
        let back = makeFlow(store, resume: snap)
        XCTAssertEqual(try XCTUnwrap(back.overrides[.squat]), 20.0 / 3.0, accuracy: 1e-9,
                       "a process death keeps the number")
        let settled = WorkoutSessionStore.settlement(of: snap, in: flow.session)
        XCTAssertEqual(try XCTUnwrap(settled.overrides[.squat]), 20.0 / 3.0, accuracy: 1e-9)
        XCTAssertTrue(store.settleAbandonedWorkout(now: snap.savedAt + WorkoutSessionStore.forgottenAfter))
        let squat = try XCTUnwrap(flow.exercises.first { $0.pattern == .squat })
        XCTAssertEqual(HistorySheet.setFacts(squat, in: try XCTUnwrap(store.records.last))?.values, [8, 6, 6])
    }

    /// "8, 8, entered 6 then Skip this set" on the last set: 8, 8, 6 is 7.33,
    /// the history reads 8-8-6, and a changed rating folds it the same.
    func testTheLastSetSkippedKeepsTheNumberEnteredForIt() throws {
        let (flow, store) = try squatFlow()
        for _ in 0..<2 {
            flow.completeSet()
            flow.skipRest()
        }
        enterSixAndSkipTheSet(flow)
        XCTAssertNotEqual(flow.exercise.pattern, .squat, "the last set skipped moves on")
        XCTAssertEqual(try XCTUnwrap(flow.overrides[.squat]), 22.0 / 3.0, accuracy: 1e-9)
        let squat = try XCTUnwrap(flow.exercises.first { $0.pattern == .squat })
        flow.finishNow()
        _ = flow.rate(.plan)
        XCTAssertEqual(HistorySheet.setFacts(squat, in: try XCTUnwrap(store.records.last))?.values, [8, 8, 6])
        store.changeLastRating(to: .less)
        XCTAssertEqual(store.records.last?.actuals?[.squat], 7, "8, 8, 6 again, not 8, 8")
        XCTAssertEqual(HistorySheet.setFacts(squat, in: try XCTUnwrap(store.records.last))?.values, [8, 8, 6],
                       "and the changed record still keeps the number")
    }

    /// A number entered before a skip counts beside the sets after it: "8,
    /// entered 6 then skipped, entered 8" on 3×8 is 8, 6, 8 — 7.33.
    func testANumberEnteredBeforeASkipCountsBesideTheSetsAfterIt() throws {
        let (flow, _) = try squatFlow()
        flow.completeSet()
        flow.skipRest()
        enterSixAndSkipTheSet(flow)
        flow.startAdjusting()
        flow.adjustValue = 8
        flow.commitSetEdit()
        XCTAssertEqual(flow.actuals[.squat], [8, 6, 8])
        XCTAssertEqual(try XCTUnwrap(flow.overrides[.squat]), 22.0 / 3.0, accuracy: 1e-9)
    }

    /// "Skip the remaining sets" called on the last set of 3×8 after 6 was
    /// entered for it — the screen offers "Skip this set" there, which names
    /// the same set — keeps the 6: 8, 8, 6, 7.33.
    func testSkippingTheRemainingSetsKeepsTheNumberEnteredForTheSetInFront() throws {
        let (flow, _) = try squatFlow()
        doTwoSetsAtPlanAndEnterSixOnTheThird(flow)
        flow.skipRestOfExercise()
        XCTAssertEqual(flow.skippedSetIndices[.squat], [2])
        XCTAssertEqual(try XCTUnwrap(flow.overrides[.squat]), 22.0 / 3.0, accuracy: 1e-9)
    }

    /// No number for the skipped set: what a later set's record fills its gap
    /// with is what was in force, not the person's, and stays out — "10,
    /// skipped, entered 8" is 9, though the facts read 10, 8, 8.
    func testAGapFilledAfterASkipIsNotANumberEnteredForIt() throws {
        let (flow, _) = try squatFlow()
        flow.startAdjusting()
        flow.adjustValue = 10
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.startAdjusting()
        flow.adjustValue = 8
        flow.commitSetEdit()
        XCTAssertEqual(flow.actuals[.squat], [10, 8, 8], "the premise: the gap reads what was in force")
        XCTAssertEqual(flow.overrides[.squat], 9)
    }

    // MARK: - The summary's cards

    /// No card for the skipped set, and the others keep their own numbers:
    /// "set 1", "set 3". The last working set is still the one that opens.
    func testTheSummaryHasNoCardForTheSkippedSet() throws {
        let (flow, _) = try plankFlow()
        declareAndSkipTheMiddleSet(flow)
        XCTAssertEqual(flow.heldSets, [
            HeldSet(index: 0, seconds: 45, planned: 30, approximate: false, correctable: false),
            HeldSet(index: 2, seconds: 45, planned: 30, approximate: false, correctable: true),
        ])
    }

    /// 30 on the clock, set 2 skipped, set 3 stopped by hand at 20 s (≈17):
    /// the hand-stopped card carries its mark and opens, and the fold is the
    /// 23.5 the two sets ran rather than 25.67 with a 30 nobody held.
    func testAHandStoppedCardAfterASkippedSetIsMarkedAndOpens() throws {
        let (flow, _) = try plankFlow()
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 30)
        clock += 600
        flow.tick()
        flow.skipSet()
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 20)
        flow.stopHoldEarly()
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(flow.heldSets, [
            HeldSet(index: 0, seconds: 30, planned: 30, approximate: false, correctable: false),
            HeldSet(index: 2, seconds: 17, planned: 30, approximate: true, correctable: true),
        ])
        XCTAssertEqual(SetFacts.override(flow.actuals, for: flow.exercise, skipping: flow.leftOutHere), 23.5)
    }

    /// A process death on that summary keeps the set off it: the indices
    /// travel in the snapshot.
    func testTheSkippedSetStaysOffTheSummaryAcrossAProcessDeath() throws {
        let (flow, store) = try plankFlow()
        declareAndSkipTheMiddleSet(flow)
        let snap = try XCTUnwrap(store.pendingWorkout)
        XCTAssertEqual(snap.skippedSetIndices, [.coreAntiExt: [1]])
        let back = makeFlow(store, resume: snap)
        XCTAssertEqual(back.phase, .exerciseSummary)
        XCTAssertEqual(back.skippedSetIndices, [.coreAntiExt: [1]])
        XCTAssertEqual(back.heldSets.map(\.index), [0, 2])
    }

    // MARK: - Every way a set is skipped

    /// 10 entered on the first two sets of the 3×8 squat; set 3 is next.
    func doTwoSetsOfTen(_ flow: WorkoutSession) {
        for _ in 0..<2 {
            flow.startAdjusting()
            flow.adjustValue = 10
            flow.commitSetEdit()
            flow.completeSet()
            flow.skipRest()
        }
        XCTAssertEqual(flow.setIndex, 2)
        XCTAssertEqual(flow.actuals[.squat], [10, 10])
    }

    /// "Skip the remaining sets": the set taken off is named, and the fold
    /// is the 10 the two sets ran — not 9.33, with the plan's 8 for the third.
    func testTheSetsSkipTheRemainingSetsTakesOffAreNotFolded() throws {
        let (flow, _) = try squatFlow()
        doTwoSetsOfTen(flow)
        flow.skipRestOfExercise()
        XCTAssertEqual(flow.skippedSetIndices[.squat], [2])
        XCTAssertEqual(SetFacts.overrides(flow.actuals, skipping: flow.skippedSetIndices,
                                          in: flow.exercises)[.squat], 10)
    }

    /// Sets 1 and 2 of the 3×8 squat on plan, and 6 entered for set 3, the
    /// set in progress ("Went differently" → OK).
    func doTwoSetsAtPlanAndEnterSixOnTheThird(_ flow: WorkoutSession) {
        for _ in 0..<2 {
            flow.completeSet()
            flow.skipRest()
        }
        flow.startAdjusting()
        flow.adjustValue = 6
        flow.commitSetEdit()
        XCTAssertEqual(flow.setIndex, 2)
        XCTAssertEqual(flow.actuals[.squat], [8, 8, 6])
    }

    /// The fold the rating would hand the engine for the squat.
    func squatFold(_ flow: WorkoutSession) throws -> Double {
        try XCTUnwrap(SetFacts.overrides(flow.actuals, skipping: flow.skippedSetIndices,
                                         in: flow.exercises)[.squat])
    }

    /// "Finish now" on set 3: the set it never reached travels as a skipped
    /// set — the count — but nobody skipped it, and it folds at what was in
    /// force for it: "10, 10, Finish now" on 3×8 is 9.33, with the plan's 8
    /// for the third.
    func testFinishNowFoldsTheSetItNeverReachedAtWhatWasInForce() throws {
        let (flow, store) = try squatFlow()
        doTwoSetsOfTen(flow)
        flow.finishNow()
        XCTAssertEqual(flow.phase, .feedback)
        XCTAssertEqual(flow.setsSkipped[.squat], 1)
        XCTAssertNil(flow.skippedSetIndices[.squat], "a set never reached is not a set skipped")
        XCTAssertEqual(try squatFold(flow), 28.0 / 3.0, accuracy: 1e-9)
        XCTAssertNil(store.pendingWorkout?.skippedSetIndices)
    }

    /// The number entered for the set in progress is a fact about that set,
    /// and "Finish now" folds it: 8, 8, 6 is 7.33, not the 8 of the two sets
    /// before it.
    func testFinishNowFoldsTheNumberEnteredForTheSetInProgress() throws {
        let (flow, _) = try squatFlow()
        doTwoSetsAtPlanAndEnterSixOnTheThird(flow)
        flow.finishNow()
        XCTAssertEqual(flow.setsSkipped[.squat], 1)
        XCTAssertNil(flow.skippedSetIndices[.squat])
        XCTAssertEqual(try squatFold(flow), 22.0 / 3.0, accuracy: 1e-9)
    }

    /// A workout left on set 3 and never come back to settles by the same
    /// rule, and the journal names no skipped set for it.
    func testAForgottenWorkoutFoldsTheSetItNeverReachedAtWhatWasInForce() throws {
        let (flow, store) = try squatFlow()
        doTwoSetsOfTen(flow)
        let snap = try XCTUnwrap(store.pendingWorkout)
        let settled = WorkoutSessionStore.settlement(of: snap, in: flow.session)
        XCTAssertEqual(settled.setsSkipped[.squat], 1)
        XCTAssertNil(settled.skippedSets[.squat])
        XCTAssertEqual(try XCTUnwrap(settled.overrides[.squat]), 28.0 / 3.0, accuracy: 1e-9)

        XCTAssertTrue(store.settleAbandonedWorkout(now: snap.savedAt + WorkoutSessionStore.forgottenAfter))
        let record = try XCTUnwrap(store.records.last)
        XCTAssertNil(record.skippedSetIndices)
        XCTAssertEqual(record.actuals?[.squat], 9)
    }

    /// …and folds the number entered for the set in progress: 7.33.
    func testAForgottenWorkoutFoldsTheNumberEnteredForTheSetInProgress() throws {
        let (flow, store) = try squatFlow()
        doTwoSetsAtPlanAndEnterSixOnTheThird(flow)
        let snap = try XCTUnwrap(store.pendingWorkout)
        let settled = WorkoutSessionStore.settlement(of: snap, in: flow.session)
        XCTAssertNil(settled.skippedSets[.squat])
        XCTAssertEqual(try XCTUnwrap(settled.overrides[.squat]), 22.0 / 3.0, accuracy: 1e-9)
    }

    /// A forgotten workout still leaves out the set the person skipped:
    /// "10, skipped, 8" on 3×8, left on the rest after set 3, settles at 9 and
    /// the journal names the skipped set.
    func testAForgottenWorkoutLeavesOutTheSetThePersonSkipped() throws {
        let (flow, store) = try squatFlow()
        flow.startAdjusting()
        flow.adjustValue = 10
        flow.commitSetEdit()
        flow.completeSet()
        flow.skipRest()
        flow.skipSet()
        flow.completeSet()
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec))
        let snap = try XCTUnwrap(store.pendingWorkout)
        let settled = WorkoutSessionStore.settlement(of: snap, in: flow.session)
        XCTAssertEqual(settled.skippedSets[.squat], [1])
        XCTAssertEqual(settled.overrides[.squat], 9)

        XCTAssertTrue(store.settleAbandonedWorkout(now: snap.savedAt + WorkoutSessionStore.forgottenAfter))
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.skippedSetIndices, [.squat: [1]])
        XCTAssertEqual(record.actuals?[.squat], 9)
    }

    /// A movement "Finish now" calls not finished keeps none of the sets
    /// skipped in it, like the count: there is no trained movement to name
    /// them for. The same for a forgotten workout.
    func testAMovementLeftUntrainedKeepsNoSkippedSets() throws {
        let (flow, store) = try squatFlow()
        enterSixAndSkipTheSet(flow)
        XCTAssertEqual(flow.skippedSetIndices[.squat], [0])
        XCTAssertEqual(flow.skippedWithNumber[.squat], [0])
        let snap = try XCTUnwrap(store.pendingWorkout)
        let settled = WorkoutSessionStore.settlement(of: snap, in: flow.session)
        XCTAssertTrue(settled.skipped.contains(.squat))
        XCTAssertNil(settled.skippedSets[.squat])
        XCTAssertNil(settled.skippedWithNumber[.squat])

        flow.finishNow()
        XCTAssertEqual(flow.interruptedPattern, .squat)
        XCTAssertNil(flow.skippedSetIndices[.squat])
        XCTAssertNil(flow.skippedWithNumber[.squat])
    }

    /// Leaving the movement takes its skipped sets with it, like the count:
    /// a movement not trained has no sets to name, numbered or not.
    func testLeavingAMovementDropsItsSkippedSets() throws {
        let (flow, _) = try squatFlow()
        enterSixAndSkipTheSet(flow)
        XCTAssertEqual(flow.skippedSetIndices[.squat], [0])
        XCTAssertEqual(flow.skippedWithNumber[.squat], [0])
        flow.leaveExercise()
        XCTAssertNil(flow.skippedSetIndices[.squat])
        XCTAssertNil(flow.skippedWithNumber[.squat])
        XCTAssertTrue(flow.skippedPatterns.contains(.squat))
    }
}

/// The fold without the sets the person skipped, without a flow around it.
@MainActor
final class PerformedSetsFoldTests: AppStoreTestCase {

    /// 3×8 squats, as the engine hands them out.
    private func squat() throws -> SessionExercise {
        var state = EngineState.initial
        state.doses[.squat] = 8
        let ex = try XCTUnwrap(Engine.generateSession(state).exercises.first { $0.pattern == .squat })
        XCTAssertEqual([ex.sets, ex.load], [3, 8], "the premise: 3×8")
        return ex
    }

    /// "Plank" 3×30 s, as the engine hands it out.
    private func plank() throws -> SessionExercise {
        var state = EngineState.initial
        state.counter = 1
        state.vars[.coreAntiExt] = 3
        state.doses[.coreAntiExt] = 30
        let ex = try XCTUnwrap(Engine.generateSession(state).exercises.first { $0.pattern == .coreAntiExt })
        XCTAssertEqual([ex.sets, ex.load], [3, 30], "the premise: 3×30 s")
        return ex
    }

    /// "10, skipped, 8" on 3×8 is a 9 — not 8.67, which reads the skipped
    /// set as the 8 the plan asked.
    func testTheFoldIsTheMeanOfTheSetsThatWereDone() throws {
        let ex = try squat()
        let facts = SetFacts.recording(10, in: [:], ex, set: 0)
        let done = SetFacts.performed(facts, ex, skipping: [1])
        XCTAssertEqual(done.map(\.set), [0, 2])
        XCTAssertEqual(done.map(\.value), [10, 8])
        XCTAssertEqual(SetFacts.override(facts, for: ex, skipping: [1]), 9)
        XCTAssertEqual(SetFacts.overrides(facts, skipping: [.squat: [1]], in: [ex]), [.squat: 9])
        let unnamed = try XCTUnwrap(SetFacts.override(facts, for: ex, skipping: []))
        XCTAssertEqual(unnamed, 26.0 / 3.0, accuracy: 1e-9, "without the index the gap reads the plan")
    }

    /// With every set skipped there is nothing to set apart: the sets read as
    /// they always did.
    func testEverySetSkippedReadsAsBefore() throws {
        let ex = try squat()
        let facts = SetFacts.recording(10, in: [:], ex, set: 0)
        XCTAssertEqual(SetFacts.performed(facts, ex, skipping: [0, 1, 2]).map(\.value),
                       SetFacts.allSets(facts, ex))
        XCTAssertEqual(SetFacts.override(facts, for: ex, skipping: [0, 1, 2]),
                       SetFacts.override(facts, for: ex, skipping: []))
    }

    /// The probe caption's half of the fold: 5, a skipped set and 12 on 3×8
    /// is 8.5 — the plan met, though the skipped set read as a 5 would take
    /// the mean under it.
    func testASkippedSetDoesNotMakeTheFoldFallShort() throws {
        let ex = try squat()
        let facts = SetFacts.recording(12, in: SetFacts.recording(5, in: [:], ex, set: 0), ex, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, ex), [5, 5, 12], "the premise: the gap carries the 5")
        XCTAssertTrue(SetFacts.foldFallsShort(facts, of: ex, skipping: []))
        XCTAssertFalse(SetFacts.foldFallsShort(facts, of: ex, skipping: [1]))
    }

    /// Off disk, an index is kept or dropped — never moved onto another set.
    func testSkippedSetsOffDiskAreKeptOrDropped() throws {
        var snap = WorkoutSnapshot(sessionNumber: 3, exIndex: 0, setIndex: 0,
                                   restEndDate: nil, restTotalSec: nil,
                                   workoutStart: .now, savedAt: .now)
        XCTAssertEqual(snap.skippedSets, [:])
        snap.skippedSetIndices = [.squat: [1, 9, -1], .pushH: []]
        XCTAssertEqual(snap.skippedSets, [.squat: [1]])
        let json = """
        {"sessionNumber": 3, "date": 1000, "result": "plan",
         "skippedSetIndices": ["core_anti_ext", [1, 7, -2]],
         "skippedWithNumberIndices": ["core_anti_ext", [1, 6]]}
        """
        let record = try JSONDecoder().decode(WorkoutRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.skippedSetIndices, [.coreAntiExt: [1]])
        XCTAssertEqual(record.skippedSets, [.coreAntiExt: [1]])
        XCTAssertEqual(record.skippedWithNumberIndices, [.coreAntiExt: [1]])
    }

    /// A record written without the indices reads as it always did: the
    /// history keeps the set the old reading kept, and a changed rating
    /// folds every set.
    func testARecordWithoutTheIndicesReadsAsItAlwaysDid() throws {
        let plank = try plank()
        let json = """
        {"sessionNumber": 3, "date": 1000, "result": "plan",
         "setActuals": ["core_anti_ext", [45, 30, 45]], "setsSkipped": ["core_anti_ext", 1]}
        """
        let record = try JSONDecoder().decode(WorkoutRecord.self, from: Data(json.utf8))
        XCTAssertNil(record.skippedSetIndices)
        XCTAssertEqual(record.skippedSets, [:])
        XCTAssertEqual(HistorySheet.setFacts(plank, in: record)?.values, [45, 30, 45])

        var state = EngineState.initial
        state.counter = 1
        state.vars[.coreAntiExt] = 3
        state.doses[.coreAntiExt] = 30
        let store = makeStore()
        store.update(refreshWidget: false) { $0.engineState = state }
        store.completeWorkout(session: store.nextSession, result: .plan,
                              setActuals: [.coreAntiExt: [45, 30, 45]], setsSkipped: [.coreAntiExt: 1])
        XCTAssertNil(store.records.last?.skippedSetIndices)
        store.changeLastRating(to: .less)
        XCTAssertEqual(store.records.last?.actuals?[.coreAntiExt], 40, "every set, as before")
    }
}
