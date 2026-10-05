//
//  A workout in progress while the app updates to the build that keeps the
//  pull-cap memory. The build before held a push the pulls had once capped at
//  the count it showed then, and the first plan drawn without that memory
//  hands the push its sets back. The snapshot of the workout is keyed on the
//  plan it was started on, so the plan drawn now no longer matches it: without
//  care the resume card disappears and the work done so far is never recorded.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class ResumeAcrossUpdateTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-resume-update" }

    /// The state a build without the memory left: the horizontal push stands
    /// on its top variation's five sets and was last shown at four, under a
    /// pull that stood on four. The pull has five since, and nothing says what
    /// the push was capped at. Workout 1 carries the pull slot and both pushes.
    private func frozenPushState(barTop: Bool = false) -> EngineState {
        var seed = EngineState.initial
        let pullTop = Library.count(.pull)
        let pushTop = Library.count(.pushH)
        let pullDose = Dose.grid(Library.unit(.pull, pullTop)).min
        let pushDose = Dose.grid(Library.unit(.pushH, pushTop)).max
        seed.vars[.pull] = pullTop
        seed.sets[.pull] = 4
        seed.doses[.pull] = pullDose
        seed.shown[.pull] = [pullTop: pullDose]
        if barTop {
            let barTopVar = Library.count(.pullBar)
            let barDose = Dose.grid(Library.unit(.pullBar, barTopVar)).min
            seed.vars[.pullBar] = barTopVar
            seed.sets[.pullBar] = 5
            seed.doses[.pullBar] = barDose
            seed.shown[.pullBar] = [barTopVar: barDose]
        }
        seed.vars[.pushH] = pushTop
        seed.sets[.pushH] = 5
        seed.doses[.pushH] = pushDose
        seed.shown[.pushH] = [pushTop: pushDose]
        var legacy = Engine.recordShown(state: seed, session: Engine.generateSession(seed))
        legacy.sets[.pull] = 5
        legacy.shownCap = [:]
        legacy.shownOwn = [:]
        legacy.shownSkip = []
        return legacy
    }

    /// The plan the build before drew from that state: the same plan with no
    /// push handed anything back. Drawn here by marking both pushes as having
    /// lost a set since their showing — the one mark under which the repair
    /// lifts nothing — rather than by the query the store uses, so the test
    /// does not grade the fix with the fix.
    private func planBeforeTheUpdate(_ state: EngineState) -> Session {
        var held = state
        held.shownSkip = [.pushH, .pushV]
        return Engine.generateSession(held)
    }

    private func pushH(_ session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == .pushH },
                      "workout 1 must carry the horizontal push — the rotation moved")
    }

    /// Two exercises behind and a set into the third, saved `age` ago.
    private func snapshot(of plan: Session, age: TimeInterval) -> WorkoutSnapshot {
        WorkoutSnapshot(sessionNumber: plan.sessionNumber,
                        exIndex: 2,
                        setIndex: 1,
                        workoutStart: Date.now.addingTimeInterval(-age - 20 * 60),
                        savedAt: Date.now.addingTimeInterval(-age),
                        fingerprint: WorkoutSnapshot.fingerprint(of: plan))
    }

    /// The store as the new build opens it: the old state and the workout it
    /// had in progress, read from the file.
    private func launch(_ state: EngineState, pending: WorkoutSnapshot) throws -> AppStore {
        try JSONEncoder().encode(AppData(engineState: state, records: [],
                                         settings: AppSettings(), pendingWorkout: pending))
            .write(to: tempURL)
        let store = makeStore()
        XCTAssertEqual(store.engineState, state,
                       "the seed did not load — everything below would be about a clean start")
        XCTAssertEqual(store.pendingWorkout, pending, "the workout in progress did not load")
        return store
    }

    func testTheSeedIsAPushTheUpdateWouldHandItsSetBack() throws {
        let state = frozenPushState()
        XCTAssertEqual(try pushH(planBeforeTheUpdate(state)).sets, 4,
                       "the build before must hold the push at the four sets it showed")
        XCTAssertEqual(try pushH(Engine.generateSession(state)).sets, 5,
                       "the plan drawn now must hand the push its fifth set back")
    }

    func testAWorkoutInProgressAcrossTheUpdateIsStillOfferedBack() throws {
        let state = frozenPushState()
        let started = planBeforeTheUpdate(state)
        let snap = snapshot(of: started, age: 5 * 60)
        let store = try launch(state, pending: snap)

        XCTAssertEqual(store.resumableWorkout(), snap,
                       "the workout in progress across the update must still be offered back")
        XCTAssertEqual(WorkoutSnapshot.fingerprint(of: store.nextSession), snap.fingerprint,
                       "it carries on as it was started — the snapshot's indices belong to that plan")
        XCTAssertEqual(try pushH(store.nextSession).sets, 4,
                       "no set appears under the person's hands in the middle of the workout")
    }

    /// Today records every plan it puts on screen, and the plan on screen
    /// beside the card is the one in progress. Recording it must not cost the
    /// card.
    func testRecordingThePlanOnScreenKeepsTheCard() throws {
        let state = frozenPushState()
        let snap = snapshot(of: planBeforeTheUpdate(state), age: 5 * 60)
        let store = try launch(state, pending: snap)

        store.recordPlanShown(store.nextSession)
        XCTAssertEqual(store.resumableWorkout(), snap,
                       "the plan on screen was written down, and the workout must still be offered back")
    }

    func testPastTheOccasionTheCardStillAsks() throws {
        let state = frozenPushState()
        let snap = snapshot(of: planBeforeTheUpdate(state), age: WorkoutSessionStore.resumeWindow + 60)
        let store = try launch(state, pending: snap)

        XCTAssertNil(store.resumableWorkout(), "the occasion is over — it is not offered to carry on")
        XCTAssertEqual(store.unfinishedWorkoutAwaitingAnswer(), snap,
                       "but the person must still be asked whether to keep it")
    }

    /// A workout nobody came back to is recorded with what was done — on the
    /// plan that was trained, not cleared as a snapshot of a plan nobody has.
    func testAForgottenWorkoutIsRecordedOnThePlanItWasTrainedOn() throws {
        let state = frozenPushState()
        let snap = snapshot(of: planBeforeTheUpdate(state), age: WorkoutSessionStore.forgottenAfter + 60)
        let store = try launch(state, pending: snap)

        XCTAssertTrue(store.settleAbandonedWorkout(), "the workout happened and must be settled")
        XCTAssertEqual(store.records.count, 1, "it must exist in the journal")
        let pushRecord = try XCTUnwrap(store.records.last?.exercises?.first { $0.pattern == .pushH })
        XCTAssertEqual(pushRecord.sets, 4, "recorded on the four sets that were trained")
        XCTAssertNil(store.pendingWorkout)
    }

    /// Only the workout in progress keeps its plan. Once nothing is in
    /// progress, the plan is the one drawn now — with the set handed back.
    func testWithNothingInProgressThePlanIsTheOneDrawnNow() throws {
        let state = frozenPushState()
        let store = try launch(state, pending: snapshot(of: planBeforeTheUpdate(state), age: 5 * 60))

        store.clearWorkoutSnapshot()
        XCTAssertEqual(try pushH(store.nextSession).sets, 5,
                       "starting over runs the plan drawn now, and the push has its set back")
    }

    /// A snapshot that is not this state's workout in progress holds nothing
    /// back, though it was taken on the plan the build before drew: the plan
    /// is the one drawn now.
    func testASnapshotOfAnotherWorkoutLeavesThePlanDrawnNow() throws {
        let state = frozenPushState()
        var stale = snapshot(of: planBeforeTheUpdate(state), age: 5 * 60)
        stale.sessionNumber += 1
        let store = try launch(state, pending: stale)

        XCTAssertNil(store.resumableWorkout(), "a snapshot of another workout is not offered back")
        XCTAssertEqual(try pushH(store.nextSession).sets, 5,
                       "and it must not keep the push off the set the plan drawn now hands back")
    }

    /// The settings row asks before the bar switch throws a workout away, and
    /// it must ask about the plan the workout is actually on. Here the bar
    /// stands on five sets too, so switching it on moves nothing in this plan.
    func testTheBarSwitchKnowsTheWorkoutSurvivesIt() throws {
        let state = frozenPushState(barTop: true)
        let snap = snapshot(of: planBeforeTheUpdate(state), age: 5 * 60)
        let store = try launch(state, pending: snap)

        XCTAssertNotNil(store.resumableWorkout(), "the workout must be resumable to begin with")
        XCTAssertFalse(store.barToggleWouldDiscardWorkout(true),
                       "the switch keeps this workout's plan, and the warning would be false")
    }
}
