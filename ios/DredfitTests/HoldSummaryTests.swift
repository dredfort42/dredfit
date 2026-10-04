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

    // MARK: - What is promised about next time

    /// The plan the engine hands `pattern` on its next appearance.
    func nextAppearance(of pattern: Pattern, in store: AppStore) -> SessionExercise? {
        var state = store.engineState
        for _ in Pattern.allCases {
            if let ex = Engine.generateSession(state).exercises.first(where: { $0.pattern == pattern }) {
                return ex
            }
            state.counter += 1
        }
        return nil
    }

    /// The probe stopped by hand at 8 s of its 15: it records 5 and falls
    /// short, with the working sets behind it on plan.
    func failTheProbe(_ flow: WorkoutSession) {
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 8)
        flow.stopHoldEarly()
        XCTAssertEqual(flow.probeActuals[.coreAntiExt], 5, "the premise: the probe fell short")
    }

    /// The probe fell short after working sets that met the plan: the plank
    /// stays on its ceiling and its next appearance probes again — two
    /// working sets and the probe, which is what the summary must promise
    /// rather than three working sets.
    func testTheNextPlanCarriesTheProbeTheEngineWillHandOut() throws {
        let (flow, store) = try probingPlankFlow()
        walkToTheProbe(flow)
        failTheProbe(flow)
        flow.completeSet()
        XCTAssertEqual(flow.phase, .exerciseSummary)
        let promised = try XCTUnwrap(flow.nextPlan(withAdditions: 0))

        flow.leaveExerciseSummary()
        _ = flow.rate(.plan, overrides: SetFacts.overrides(flow.actuals, skipping: flow.skippedSetIndices, in: flow.exercises))
        let next = try XCTUnwrap(nextAppearance(of: .coreAntiExt, in: store))
        XCTAssertNotNil(next.probe, "the premise: the engine probes again")
        XCTAssertEqual(promised.probe, next.probe)
        XCTAssertEqual(promised.display, next.display)
    }

    /// "Set the time" 30 on the probing plank: both working sets ran 30 of
    /// the 45 asked and the probe met its target — and the plank steps down
    /// whatever the probe showed. The caption names the movement of the plan
    /// it steps down to, instead of saying the plan stays.
    func testAProbeAfterWorkingSetsThatFellShortNamesWhereThePlanGoes() throws {
        let (flow, _) = try probingPlankFlow()
        flow.startDeclaringHoldTime()
        flow.adjustValue = 30
        flow.commitSetEdit()
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 30)
        run(flow, until: { flow.phase == .work })
        run(flow, for: 30)
        run(flow, until: { flow.phase == .work })
        XCTAssertTrue(flow.onProbeSet)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.probeActuals[.coreAntiExt], 15, "the premise: the probe met its target")

        let next = try XCTUnwrap(flow.nextPlan(withAdditions: 0))
        XCTAssertEqual(next.load, 30, "the premise: the plan steps down to what was held")
        XCTAssertNil(next.probe)
        XCTAssertEqual(flow.probeOutcome, .planMoves(Library.name(.coreAntiExt, 1)))
    }

    /// Working sets that met the plan leave the outcome to the probe: met,
    /// it names the probe's own movement.
    func testAProbePassedAfterWorkingSetsThatMetThePlanNamesItsMovement() throws {
        let (flow, _) = try probingPlankFlow()
        walkToTheProbe(flow)
        XCTAssertNil(flow.probeOutcome, "nothing to say before the probe has a number")
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.probeOutcome, .passed(Library.name(.coreAntiExt, 2)))
    }

    /// …short of its target, the plan stays as it is — and there it does.
    func testAProbeShortAfterWorkingSetsThatMetThePlanLeavesThePlan() throws {
        let (flow, _) = try probingPlankFlow()
        walkToTheProbe(flow)
        failTheProbe(flow)
        XCTAssertEqual(flow.probeOutcome, .stays)
    }

    // MARK: - A skipped probe

    /// Set 2 stopped by hand at 44 s on its clock (≈41), then the probe
    /// skipped. "The working sets lose nothing": their summary still comes,
    /// with the estimate on its card to put right, and its Done leads into
    /// the rest between movements, as after a probe done.
    func testSkippingAHoldsProbeOpensTheMovementsSummary() throws {
        let (flow, _) = try probingPlankFlow()
        walkToTheProbe(flow, secondStoppedAt: 44)
        flow.skipSet()
        XCTAssertEqual(flow.phase, .exerciseSummary,
                       "the plank's summary, with its ≈41 card, after the probe is skipped")
        XCTAssertEqual(flow.exercise.pattern, .coreAntiExt)
        XCTAssertTrue(flow.summaryCardIsApproximate(set: 1), "the estimate is still there to put right")
        XCTAssertEqual(flow.summaryMeasured(set: 1), 41)
        XCTAssertNil(flow.probeActuals[.coreAntiExt])

        flow.leaveExerciseSummary()
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec),
                       "the rest between movements, as after a probe done")
        XCTAssertNil(flow.probeActuals[.coreAntiExt], "a skipped probe records nothing on the way out")
    }

    /// The summary's Done is not the probe's: nothing records the skipped
    /// probe at its target, so the engine sees it unresolved — no pass, and
    /// the plank's next appearance probes again.
    func testASkippedProbeReachesTheEngineUnresolved() throws {
        let (flow, store) = try probingPlankFlow()
        walkToTheProbe(flow)
        flow.skipSet()
        flow.leaveExerciseSummary()
        _ = flow.rate(.plan, overrides: SetFacts.overrides(flow.actuals, skipping: flow.skippedSetIndices, in: flow.exercises))
        let record = try XCTUnwrap(store.records.last)
        XCTAssertNil(record.probes?[.coreAntiExt], "no number for a probe nobody did")
        XCTAssertEqual(store.engineState.position(.coreAntiExt).variation, 1, "not promoted")
        let next = try XCTUnwrap(nextAppearance(of: .coreAntiExt, in: store))
        XCTAssertEqual(next.probe?.variation, 2, "the probe comes back")
    }

    /// A process death on that summary comes back to it — the estimate mark
    /// and the clock's number with it — and its Done still records no probe.
    func testTheSummaryAfterASkippedProbeSurvivesAProcessDeath() throws {
        let (flow, store) = try probingPlankFlow()
        walkToTheProbe(flow, secondStoppedAt: 44)
        flow.skipSet()
        let snap = try XCTUnwrap(store.pendingWorkout)
        XCTAssertEqual(snap.atExerciseSummary, true)

        let back = makeFlow(store, resume: snap)
        XCTAssertEqual(back.phase, .exerciseSummary)
        XCTAssertEqual(back.exercise.pattern, .coreAntiExt)
        XCTAssertTrue(back.summaryCardIsApproximate(set: 1))
        XCTAssertEqual(back.summaryMeasured(set: 1), 41)
        XCTAssertNil(back.probeActuals[.coreAntiExt])
        back.leaveExerciseSummary()
        XCTAssertNil(back.probeActuals[.coreAntiExt], "the restored summary's Done records no probe either")
        XCTAssertEqual(back.phase, .rest(seconds: back.exercise.restExerciseSec))
    }

    /// A movement in reps has no summary to open: skipping its probe goes
    /// straight on to the next movement, as it always has.
    func testSkippingARepsProbeGoesStraightOn() throws {
        let flow = makeFlow(makeStore(), session: try probeSession())
        flow.declineWarmup()
        XCTAssertEqual(flow.exercise.unit, .reps, "the premise: a movement in reps")
        let pattern = flow.exercise.pattern
        flow.setIndex = flow.exercise.sets
        XCTAssertTrue(flow.onProbeSet)
        flow.skipSet()
        XCTAssertEqual(flow.phase, .work)
        XCTAssertNotEqual(flow.exercise.pattern, pattern)
        XCTAssertNil(flow.probeActuals[pattern])
    }
}
