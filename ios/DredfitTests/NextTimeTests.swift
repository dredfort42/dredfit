//
//  The two tenses of a finished hold's summary (§41.13): the clock as the
//  ceiling of a correction, and the addition "for next time" — where it is
//  kept, where it lands, and how every screen after it names it.
//
//  Every rule here is a pure function or a store call on purpose. The
//  summary itself is a SwiftUI view that nothing automated drives; what it
//  prints comes from these, and these are what a gating test can reach.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class NextTimeTests: AppStoreTestCase {

    // MARK: - The clock is the ceiling

    /// Every set but the last: down only, to what the clock recorded. The
    /// last: the whole corridor — nothing follows it, and the person may
    /// have kept holding.
    func testACorrectionCannotExceedTheClockExceptOnTheLastSet() {
        let corridor = SetFacts.corridor(for: .hold)
        XCTAssertEqual(SetFacts.correctionRange(measured: 30, isLastSet: false),
                       corridor.lowerBound...30)
        XCTAssertEqual(SetFacts.correctionRange(measured: 30, isLastSet: true), corridor)
        // Off the corridor either way, the ceiling is still a number the
        // panel can stand on.
        XCTAssertEqual(SetFacts.correctionRange(measured: 2, isLastSet: false),
                       corridor.lowerBound...corridor.lowerBound)
        XCTAssertEqual(SetFacts.correctionRange(measured: 500, isLastSet: false), corridor)
    }

    // MARK: - The addition through the store

    /// A session with a hold in it, and the store that generated it.
    private struct HoldFixture {
        let store: AppStore
        let session: Session
        let hold: SessionExercise
    }

    private func storeWithHold() throws -> HoldFixture {
        let store = AppStore(storageURL: tempURL)
        // The second session is the first with a hold in it (the rotation).
        store.completeWorkout(session: store.nextSession, result: .plan)
        let session = store.nextSession
        let hold = try XCTUnwrap(session.exercises.first { $0.unit == .hold })
        return HoldFixture(store: store, session: session, hold: hold)
    }

    /// The raise lands over the rating and is written down: the record
    /// carries it, and the position after is one step above what the
    /// rating alone would have set.
    func testTheAdditionLandsOverTheRatingAndIsRecorded() throws {
        let fx = try storeWithHold()
        let (store, session, hold) = (fx.store, fx.session, fx.hold)
        let alone = AppStore(storageURL: tempURL)
        alone.completeWorkout(session: session, result: .plan)
        store.completeWorkout(session: session, result: .plan, raised: [hold.pattern: 1])

        let without = try XCTUnwrap(alone.currentPositions[hold.pattern])
        let with = try XCTUnwrap(store.currentPositions[hold.pattern])
        XCTAssertEqual(Engine.progress(hold.pattern, variation: with.variation, sets: with.sets,
                                       dose: with.dose, sub: with.sub ?? 0, cut: with.cut ?? 0),
                       Engine.progress(hold.pattern, variation: without.variation,
                                       sets: without.sets, dose: without.dose,
                                       sub: without.sub ?? 0, cut: without.cut ?? 0) + 1,
                       "one step for next time is one growth event over the rating's")
        let record = try XCTUnwrap(AppStore(storageURL: tempURL).records.last)
        XCTAssertEqual(record.raisedSteps, [hold.pattern: 1], "the journal keeps the decision")
        // …and the store the record came from says so on tomorrow's plan.
        XCTAssertEqual(store.raisedForNextPlan(hold.pattern), 1)
        XCTAssertEqual(store.raisedForNextPlan(session.exercises[0].pattern), 0)
    }

    /// The preview is the rating's own arithmetic, not a second copy of it:
    /// what the summary promises under "on plan" is what "on plan" then sets.
    func testThePreviewIsWhatTheRatingWillSet() throws {
        let fx = try storeWithHold()
        let (store, session, hold) = (fx.store, fx.session, fx.hold)
        let overrides: [Pattern: Double] = [hold.pattern: Double(hold.load) - 5]
        let preview = try XCTUnwrap(store.previewPosition(
            after: session, pattern: hold.pattern, overrides: overrides, skipped: [],
            setsSkipped: [:], probes: [:], raised: [hold.pattern: 2]))
        store.completeWorkout(session: session, result: .plan, overrides: overrides,
                              raised: [hold.pattern: 2])
        XCTAssertEqual(preview, store.currentPositions[hold.pattern])
        XCTAssertNil(store.previewPosition(after: session, pattern: hold.pattern,
                                           overrides: [:], skipped: [], setsSkipped: [:],
                                           probes: [:], raised: [:]),
                     "a session the state no longer generates previews nothing")
    }

    /// Changing the rating afterwards keeps the addition: it was a decision
    /// about the movement, not about the rating.
    func testChangingTheRatingKeepsTheAddition() throws {
        let fx = try storeWithHold()
        let (store, session, hold) = (fx.store, fx.session, fx.hold)
        store.completeWorkout(session: session, result: .plan, raised: [hold.pattern: 1])
        let before = store.currentPositions[hold.pattern]
        store.changeLastRating(to: .less)
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.result, .less)
        XCTAssertEqual(record.raisedSteps, [hold.pattern: 1])
        XCTAssertNotEqual(store.currentPositions[hold.pattern], before,
                          "the rating moved the position; the addition stayed on top of it")
        XCTAssertEqual(store.raisedForNextPlan(hold.pattern), 1)
    }

    /// The journal names the share that LANDED and keeps the decision apart
    /// from it. On the grid's ceiling the engine parks the steps (§41.13):
    /// "+10 s" on a plan of 3×40 s rated "easy" lands five — the rating's two
    /// events take the base to 45-45-40, one step turns that into 3×45 and
    /// the other burns — so tomorrow's plan and the history say five, while
    /// a changed rating replays the two the person asked for and, under "on
    /// plan", lands both (review, 12.09.2026).
    func testTheJournalNamesTheShareThatLandedAndKeepsTheDecision() throws {
        let store = AppStore(storageURL: tempURL)
        let pattern = Pattern.coreAntiExt
        var tries = 0
        while !store.nextSession.exercises.contains(where: { $0.pattern == pattern }), tries < 12 {
            store.completeWorkout(session: store.nextSession, result: .plan)
            tries += 1
        }
        // One rung under the top of the hold grid, and never shown there:
        // the plan reads 3×40 s with no gate in the way.
        store.engineState.doses[pattern] = Dose.hold.max - Dose.hold.step
        let session = store.nextSession
        let hold = try XCTUnwrap(session.exercises.first { $0.pattern == pattern })
        XCTAssertEqual(hold.load, Dose.hold.max - Dose.hold.step, "the premise: 3×40 s")
        XCTAssertNil(hold.loads, "the premise: a uniform plan")
        XCTAssertEqual(hold.sets, EngineConfig.setsBase)

        store.completeWorkout(session: session, result: .more, raised: [pattern: 2])
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.raisedSteps, [pattern: 2], "the decision is kept as tapped")
        XCTAssertEqual(record.raisedLanded, [pattern: 1], "one step landed, the other burned")
        let after = try XCTUnwrap(store.currentPositions[pattern])
        XCTAssertEqual(after.dose, Dose.hold.max)
        XCTAssertNil(after.sub)
        XCTAssertEqual(store.raisedForNextPlan(pattern), 1, "tomorrow's note names the landed share")
        let base = String(localized: "history.after",
                          defaultValue: "After: \(hold.withLoads(nil, load: Dose.hold.max).display)")
        XCTAssertEqual(HistorySheet.afterLine(hold, in: record),
                       String(localized: "history.afterRaised",
                              defaultValue: "\(base) · \(RaiseLabel.text(steps: 1, unit: .hold)) of it is your addition"))

        // Under "on plan" the base is 45-40-40 and both steps land.
        store.changeLastRating(to: .plan)
        let redone = try XCTUnwrap(store.records.last)
        XCTAssertEqual(redone.raisedSteps, [pattern: 2], "the decision survived the change")
        XCTAssertEqual(redone.raisedLanded, [pattern: 2])
        XCTAssertEqual(store.raisedForNextPlan(pattern), 2)
        XCTAssertEqual(store.currentPositions[pattern]?.dose, Dose.hold.max)
    }

    /// The share is what the screens read; a record written before the share
    /// existed falls back to the decision, and a record that says nothing
    /// landed says so even though the decision is on it.
    func testTheShareFallsBackToTheDecisionOnlyWhereThereIsNone() {
        var record = WorkoutRecord(sessionNumber: 1, date: .now, result: .plan,
                                   raisedSteps: [.squat: 2])
        XCTAssertEqual(record.raisedShare(.squat), 2)
        record.raisedLanded = [:]
        XCTAssertEqual(record.raisedShare(.squat), 0)
        record.raisedLanded = [.squat: 1]
        XCTAssertEqual(record.raisedShare(.squat), 1)
        XCTAssertEqual(record.raisedShare(.pushH), 0)
    }

    /// The summary's count after a correction: steps whose plan equals the
    /// plan one step below are steps the engine will park, and they come off
    /// the count from the top. A preview that cannot be had leaves the count
    /// alone — an unknown is not "nothing moves".
    func testTheStepperCountsOnlyTheStepsThatStillMoveThePlan() {
        let flat = SessionExercise(pattern: .coreAntiExt, name: "Plank", variation: 1,
                                   unit: .hold, load: 40, perSide: false, sets: 3,
                                   restSetSec: 60, restExerciseSec: 60, loads: nil, probe: nil)
        let raised = flat.withLoads([45, 40, 40])
        let top = flat.withLoads(nil, load: 45)
        // 0 → 45-40-40, 1 → 3×45, 2 → 3×45: the second step burns.
        let plans = [raised, top, top]
        XCTAssertEqual(NextTimeBlock.stepsThatStillMove(2, preview: { plans[min($0, 2)] }), 1)
        XCTAssertEqual(NextTimeBlock.stepsThatStillMove(1, preview: { plans[min($0, 2)] }), 1)
        // Everything parked: the count goes to zero.
        XCTAssertEqual(NextTimeBlock.stepsThatStillMove(2, preview: { _ in top }), 0)
        // Every step live: nothing comes off.
        let live = [raised, top, top.withLoads(nil, load: 50)]
        XCTAssertEqual(NextTimeBlock.stepsThatStillMove(2, preview: { live[min($0, 2)] }), 2)
        XCTAssertEqual(NextTimeBlock.stepsThatStillMove(2, preview: { _ in nil }), 2)
        XCTAssertEqual(NextTimeBlock.stepsThatStillMove(-1, preview: { _ in top }), 0)
    }

    /// The note on tomorrow's plan belongs to a rise that is still standing:
    /// once something else moves the movement, the note stands down. A
    /// fresh store's hold sits on the first variation, where "easier" is
    /// inert, so the mover here is the state itself — what a decay or a
    /// comeback would do between the rating and the next plan.
    func testTheAdditionNoteStandsDownWhenTheMovementMovedSince() throws {
        let fx = try storeWithHold()
        let (store, session, hold) = (fx.store, fx.session, fx.hold)
        store.completeWorkout(session: session, result: .plan, raised: [hold.pattern: 1])
        XCTAssertEqual(store.raisedForNextPlan(hold.pattern), 1)
        store.engineState = Engine.raiseDose(state: store.engineState,
                                             pattern: hold.pattern, steps: 1)
        XCTAssertEqual(store.raisedForNextPlan(hold.pattern), 0)
    }

    /// The clock's numbers come back off disk bounded like the estimate
    /// marks: a set the scale does not have, or a number outside the
    /// corridor, is dropped rather than shown as "what the clock saw".
    func testTheClocksNumbersOffDiskAreBounded() {
        var snap = WorkoutSnapshot(sessionNumber: 3, exIndex: 0, setIndex: 0,
                                   restEndDate: nil, restTotalSec: nil,
                                   workoutStart: .now, savedAt: .now)
        XCTAssertEqual(snap.measuredHold, [:])
        snap.holdMeasuredSec = [0: 30, 1: 7, 9: 30, 2: 400, 3: -1]
        XCTAssertEqual(snap.measuredHold, [0: 30, 1: 7])
    }

    /// Off disk the count is clamped to what the engine accepts, like every
    /// other stored number.
    func testARaiseOffDiskIsClampedToWhatTheEngineTakes() throws {
        let json = """
        {"sessionNumber": 3, "date": 1000, "result": "plan",
         "raisedSteps": ["core_anti_ext", 40, "squat", -2],
         "raisedLanded": ["core_anti_ext", 9]}
        """
        let record = try JSONDecoder().decode(WorkoutRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.raisedSteps?[.coreAntiExt], EngineConfig.raiseStepsMax)
        XCTAssertEqual(record.raisedSteps?[.squat], 0)
        XCTAssertEqual(record.raisedLanded?[.coreAntiExt], EngineConfig.raiseStepsMax)
    }

    // MARK: - The words

    func testTheAdditionIsPrintedInTheMovementsOwnUnit() {
        XCTAssertEqual(RaiseLabel.text(steps: 1, unit: .hold), "+5 s")
        XCTAssertEqual(RaiseLabel.text(steps: 2, unit: .hold), "+10 s")
        XCTAssertEqual(RaiseLabel.text(steps: 1, unit: .reps), "+1")
        XCTAssertNil(ExerciseRow.raisedNote(steps: 0, unit: .hold))
        // Built through the same key and the same placeholder the note uses,
        // so the comparison holds in whichever locale the runner speaks.
        XCTAssertEqual(ExerciseRow.raisedNote(steps: 1, unit: .hold),
                       String(localized: "plan.raised", defaultValue: "\("+5 s") — your addition"))
    }

    /// The three lines of a history row are three named lines: the fact in
    /// the plan's own spelling, and "After:" naming the person's share.
    func testTheHistoryRowNamesTheFactAndTheAddition() throws {
        let hold = SessionExercise(pattern: .coreAntiExt, name: "Plank", variation: 3,
                                   unit: .hold, load: 25, perSide: false, sets: 3,
                                   restSetSec: 60, restExerciseSec: 60,
                                   loads: [30, 25, 25], probe: nil)
        let record = WorkoutRecord(
            sessionNumber: 37, date: Date(timeIntervalSince1970: 1_000), result: .plan,
            exercises: [hold], setActuals: [.coreAntiExt: [30, 22, 25]],
            positionsAfter: [.coreAntiExt: RecordedPosition(variation: 3, sets: 3, dose: 30)],
            raisedSteps: [.coreAntiExt: 1])
        XCTAssertEqual(HistorySheet.factLine(hold, in: record),
                       String(localized: "history.held", defaultValue: "Held: \(hold.withLoads([30, 22, 25]).display)"))
        // Without a raise the line is what it always was; with one, the
        // same line carries the person's share, through the same key.
        var plain = record
        plain.raisedSteps = nil
        let base = try XCTUnwrap(HistorySheet.afterLine(hold, in: plain))
        XCTAssertEqual(base, String(localized: "history.after",
                                    defaultValue: "After: \(hold.withLoads(nil, load: 30).display)"))
        XCTAssertEqual(HistorySheet.afterLine(hold, in: record),
                       String(localized: "history.afterRaised",
                              defaultValue: "\(base) · \("+5 s") of it is your addition"))
        // A plain uniform shortfall prints the way a uniform plan does.
        let short = WorkoutRecord(
            sessionNumber: 38, date: Date(timeIntervalSince1970: 2_000), result: .plan,
            exercises: [hold], setActuals: [.coreAntiExt: [20, 20, 20]])
        XCTAssertEqual(HistorySheet.factLine(hold, in: short),
                       String(localized: "history.held", defaultValue: "Held: \(hold.withLoads(nil, load: 20).display)"))
    }
}

private extension SessionExercise {
    func withLoads(_ loads: [Int]?, load: Int? = nil) -> SessionExercise {
        SessionExercise(pattern: pattern, name: name, variation: variation, unit: unit,
                        load: load ?? self.load, perSide: perSide, sets: sets,
                        restSetSec: restSetSec, restExerciseSec: restExerciseSec,
                        loads: loads, probe: probe)
    }
}
