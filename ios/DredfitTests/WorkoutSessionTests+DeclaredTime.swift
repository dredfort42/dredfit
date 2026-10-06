import XCTest
import DredfitCore
@testable import Dredfit

/// The time a hold is declared to run, and the number the work screen
/// names: whatever it shows is what the clock then counts.
extension WorkoutSessionTests {

    // MARK: - The declared time

    func testTheDeclaredTimeSetsTheClockAndRecordsNothing() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startDeclaringHoldTime()
        XCTAssertEqual(flow.editing, .holdTime)
        flow.adjustValue = 45
        flow.commitSetEdit()
        XCTAssertEqual(flow.holdDeclared, 45)
        XCTAssertNil(flow.actuals[.coreAntiExt], "a target, not a record")
        flow.startHold()
        XCTAssertEqual(flow.holdTotal, 45)
    }

    func testStartingTheExerciseClosesTheDeclarationUnsaid() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startDeclaringHoldTime()
        flow.adjustValue = 45
        flow.startHoldExercise()
        XCTAssertNil(flow.editing)
        XCTAssertNil(flow.holdDeclared)
        XCTAssertEqual(flow.holdTotal, 15)
    }

    // MARK: - The number the screen names, and the clock then counts

    /// The rest ran out with nobody there, so the run stopped and set 2 waits
    /// on its own button — showing the number its clock will count.
    func testASetTheRunNoLongerOpensShowsTheDeclaredTimeItWillRun() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(45, on: flow)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 45)
        clock += 600
        flow.tick()
        XCTAssertFalse(flow.holdAutoRun)
        XCTAssertEqual(flow.setIndex, 1)

        XCTAssertEqual(flow.workNumber, 45, "the screen names the declared time, not the plan of 15")
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(flow.holdClock.remaining, 45, "and the clock counts what the screen named")
    }

    func testAStopInsideTheGraceHandsBackTheDeclaredTimeTheClockWillRun() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(45, on: flow)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 45 + 60)
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertTrue(flow.holding, "the run opened set 2 on its rest's go")
        run(flow, for: 2)
        flow.stopHoldEarly()
        XCTAssertFalse(flow.holding)

        XCTAssertEqual(flow.workNumber, 45, "the set handed back names the declared time, not the plan of 15")
        flow.startHold()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(flow.holdClock.remaining, 45, "and the clock counts what the screen named")
    }

    /// Below the plan, and with nothing recorded yet: the declaration alone
    /// is what the set after a skipped one runs at.
    func testASetAfterASkipShowsTheDeclaredTimeItWillRun() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(10, on: flow)
        flow.skipSet()
        XCTAssertEqual(flow.setIndex, 1)

        XCTAssertEqual(flow.workNumber, 10, "the screen names the declared time, not the plan of 15")
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(flow.holdClock.remaining, 10, "and the clock counts what the screen named")
    }

    /// Nothing on a reps movement can declare a time, so one found there came
    /// off a snapshot, and the set goes on naming the reps it asks for.
    func testARepsMovementNamesItsOwnNumberWhateverIsDeclared() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        XCTAssertEqual(flow.exercise.unit, .reps)
        flow.holdDeclared = 45
        XCTAssertEqual(flow.workNumber, flow.exercise.plannedLoad(set: 0))
    }

    /// The probe is one set of another movement: it names the probe's own
    /// target, then the number entered for it — never the working sets'.
    func testTheProbeSetNamesTheProbesOwnNumber() throws {
        let flow = makeFlow(makeStore(), session: try probeSession())
        flow.declineWarmup()
        flow.setIndex = flow.exercise.sets
        let probe = try XCTUnwrap(flow.exercise.probe)
        XCTAssertNotEqual(probe.load, flow.exercise.plannedLoad(set: flow.setIndex),
                          "the probe and the working sets must ask for different numbers to be told apart")
        XCTAssertEqual(flow.workNumber, probe.load)

        flow.startAdjusting()
        flow.adjustValue = probe.load + 1
        flow.commitSetEdit()
        XCTAssertEqual(flow.workNumber, probe.load + 1, "the number entered for the probe is the one it names")
    }

    /// While a clock is on the person the big number is that clock: the
    /// count-in, the hold itself and the pause between the sides each show
    /// the seconds they have left, never the set's 15.
    func testWhileAClockRunsTheScreenNamesItsSecondsLeft() throws {
        let (flow, _) = try holdFlow(.coreRot)
        flow.startHoldExercise()
        run(flow, for: 1)
        XCTAssertTrue(flow.holdCountingIn)
        XCTAssertEqual(flow.workNumber, GetReady.countInSeconds - 1)

        run(flow, for: GetReady.countInSeconds - 1 + 3)
        XCTAssertTrue(flow.holding)
        XCTAssertEqual(flow.workNumber, 15 - 3)

        run(flow, until: { flow.holdSwitchPausing })
        XCTAssertEqual(flow.workNumber, Cooldown.switchPauseSeconds)
    }

    /// The panel reopens on the time already declared — what the clock would
    /// run now — not on the plan.
    func testTheDeclarationReopensOnTheTimeTheClockWouldRun() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(45, on: flow)
        flow.startDeclaringHoldTime()
        XCTAssertEqual(flow.adjustValue, 45)
    }

    /// A Stop inside the grace on the SECOND side hands that side back, and it
    /// still runs for what the first side ran — so that is the number it
    /// names, not the set's own: the plan's 15, or a declared 45. Under a
    /// declaration a first side past the plan counts in full.
    func testASecondSideHandedBackNamesWhatTheFirstSideRan() throws {
        // The time declared before the run, and the seconds the first side
        // ran before the Stop that cut it short.
        let cases: [(declared: Int?, held: Int)] = [(nil, 10), (45, 13), (45, 33)]
        for (declared, held) in cases {
            let (flow, _) = try holdFlow(.coreRot)
            if let declared { declare(declared, on: flow) }
            flow.startHoldExercise()
            run(flow, for: GetReady.countInSeconds + held)
            flow.stopHoldEarly()
            let firstSide = SetFacts.holdEndedByTap(heldSeconds: held)
            XCTAssertEqual(flow.firstSideHeld, firstSide)
            run(flow, for: Cooldown.switchPauseSeconds + 2)
            flow.stopHoldEarly()
            XCTAssertTrue(flow.holdSecondSide, "the side is handed back, not the set")
            XCTAssertFalse(flow.holding)

            XCTAssertEqual(flow.workNumber, firstSide,
                           "declared \(String(describing: declared)): the side names what the first side ran")
            flow.startHold()
            run(flow, for: GetReady.countInSeconds)
            XCTAssertEqual(flow.holdClock.remaining, firstSide, "and the clock counts what the screen named")
        }
    }
}
