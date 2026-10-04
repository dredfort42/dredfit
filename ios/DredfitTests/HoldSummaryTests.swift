import XCTest
import DredfitCore
@testable import Dredfit

/// The summary a hold movement ends on, walked on the engine's own plans:
/// how far its correctable card can go, and what it promises about next time.
extension WorkoutSessionTests {

    /// Knee plank on its ceiling and journalled there, in the store's own
    /// state: session 2 hands it out as 2×45 s and a probe of High plank,
    /// 15 s. The store generated the session, so the summary's preview has
    /// an answer.
    func probingPlankFlow() throws -> (WorkoutSession, AppStore) {
        var state = EngineState.initial
        state.counter = 1
        state.doses[.coreAntiExt] = Dose.hold.max
        state.shown[.coreAntiExt] = [1: Dose.hold.max]
        let store = makeStore()
        store.update(refreshWidget: false) { $0.engineState = state }
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = try index(of: .coreAntiExt, in: flow)
        XCTAssertEqual(flow.exercise.sets, 2, "the premise: two working sets")
        XCTAssertEqual(flow.exercise.probe?.name, Library.name(.coreAntiExt, 2), "the premise: a probe")
        signals.events.removeAll()
        return (flow, store)
    }

    /// "Start exercise", the first working set on its clock, the second one
    /// opened by its rest's go — run out, or stopped by hand at
    /// `secondStoppedAt` seconds on its clock — and the rest before the
    /// probe, up to the probe's own screen.
    func walkToTheProbe(_ flow: WorkoutSession, secondStoppedAt: Int? = nil) {
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + Dose.hold.max)
        run(flow, until: { flow.phase == .work })
        if let secondStoppedAt {
            run(flow, for: secondStoppedAt)
            flow.stopHoldEarly()
        } else {
            run(flow, for: Dose.hold.max)
        }
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restSetSec),
                       "a rest starts on the second working set's signal")
        run(flow, until: { flow.phase == .work })
        XCTAssertTrue(flow.onProbeSet)
    }

    /// The probe held on its own clock for `seconds`, and its Done.
    func holdTheProbe(_ flow: WorkoutSession, for seconds: Int) {
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + seconds)
        XCTAssertTrue(flow.holdSettled)
        flow.completeSet()
    }

    // MARK: - How far the correctable card goes

    /// The last working set of the probing plank ran its 45 s and the rest
    /// before the probe started on its signal: it can be put down, and not
    /// above the 45 the clock ran.
    func testASetARestFollowedCannotBeRaisedAboveItsClock() throws {
        let (flow, _) = try probingPlankFlow()
        walkToTheProbe(flow)
        holdTheProbe(flow, for: 15)
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertTrue(flow.isLastSummarySet(1), "the last working set is still the card that opens")
        XCTAssertFalse(flow.isLastSummarySet(0))
        XCTAssertEqual(flow.summaryRange(set: 1), SetFacts.corridor(for: .hold).lowerBound...45,
                       "set 2's clock ran 45 s and a rest followed it")
        XCTAssertEqual(flow.summaryRange(set: 0), 45...45, "an earlier set stands as it ran")
    }

    /// Stopped by hand at 44 s on its clock, the set recorded ≈41; the
    /// clock's own reading at the tap is the ceiling.
    func testAHandStoppedSetARestFollowedGoesUpToTheClocksReading() throws {
        let (flow, _) = try probingPlankFlow()
        walkToTheProbe(flow, secondStoppedAt: 44)
        holdTheProbe(flow, for: 15)
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [45, 41])
        XCTAssertEqual(flow.summaryRange(set: 1), SetFacts.corridor(for: .hold).lowerBound...44,
                       "≈41 plus the reach allowance it paid")
    }

    /// Nothing followed the last set of a plain hold: both directions stay
    /// open.
    func testAPlainHoldsLastSetKeepsBothDirections() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        XCTAssertNil(flow.exercise.probe, "the premise: nothing after the last set")
        flow.startHoldExercise()
        run(flow, until: { flow.phase == .exerciseSummary })
        XCTAssertTrue(flow.isLastSummarySet(2))
        XCTAssertEqual(flow.summaryRange(set: 2), SetFacts.corridor(for: .hold))
    }

    /// …whoever ended it: a thumb on the last set closes nothing either.
    func testAPlainHoldsHandStoppedLastSetKeepsBothDirections() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(flow.summaryRange(set: 2), SetFacts.corridor(for: .hold))
    }
}
