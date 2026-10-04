import XCTest
import DredfitCore
@testable import Dredfit

/// Holds: the count-in, the clock, Stop, the side switch, the hands-free run
/// and the summary a hold movement ends on.
extension WorkoutSessionTests {

    private func holdFlow(_ pattern: Pattern) throws -> (WorkoutSession, AppStore) {
        let store = makeStore()
        let flow = makeFlow(store, session: holdSession())
        flow.declineWarmup()
        flow.exIndex = try index(of: pattern, in: flow)
        signals.events.removeAll()
        return (flow, store)
    }

    /// A set at the plan is written as nothing at all, so the clock is set to
    /// 20 s to make what it ran visible.
    private func declare(_ seconds: Int, on flow: WorkoutSession) {
        flow.startDeclaringHoldTime()
        flow.adjustValue = seconds
        flow.commitSetEdit()
    }

    func testAHoldCountsInThenRunsAndRecordsWhatTheClockRan() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(20, on: flow)
        flow.startHold()
        XCTAssertTrue(flow.holdCountingIn)
        XCTAssertEqual(flow.holdCountInClock.remaining, GetReady.countInSeconds)
        XCTAssertFalse(flow.holding)

        run(flow, for: GetReady.countInSeconds)
        XCTAssertTrue(flow.holding)
        XCTAssertEqual(flow.holdClock.remaining, 20)

        run(flow, for: 20)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [20])
        XCTAssertEqual(flow.holdMeasured[0], 20)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go, .tick, .tick, .tick, .done])
    }

    func testAHoldThatRanOutWhileAwayIsCreditedInFull() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(20, on: flow)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds)
        clock += 3_600
        flow.tick()
        XCTAssertEqual(flow.actuals[.coreAntiExt], [20],
                       "a hold that ran to the end of its clock counts as held, whatever came after")
    }

    func testACountInThatEndedOutOfEarshotStartsOver() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        clock += 30
        flow.tick()
        XCTAssertTrue(flow.holdCountingIn, "a go nobody could hear must not start a plank")
        XCTAssertEqual(flow.holdCountInClock.remaining, GetReady.countInSeconds)
        XCTAssertFalse(flow.holding)
    }

    func testAStopInsideTheMisTapGraceHandsTheSetBack() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 2)
        flow.stopHoldEarly()
        XCTAssertFalse(flow.holding)
        XCTAssertEqual(flow.holdClock.remaining, 15, "the set stands at its full length again")
        XCTAssertNil(flow.actuals[.coreAntiExt])
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.setIndex, 0)
    }

    func testAStopPastTheGraceIsRecordedAsAnEstimate() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        let expected = SetFacts.snap(Double(SetFacts.holdEndedByTap(heldSeconds: 10)), unit: .hold)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [expected])
        XCTAssertTrue(flow.holdApproxSets.contains(0), "a number the app guessed at says so")
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
    }

    func testTheSecondSideRunsForWhatTheFirstSideRan() throws {
        let (flow, _) = try holdFlow(.coreRot)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        let firstSide = SetFacts.holdEndedByTap(heldSeconds: 10)
        XCTAssertTrue(flow.holdSwitchPausing)
        XCTAssertEqual(flow.firstSideHeld, firstSide)
        XCTAssertEqual(signals.tones.last, .switchSides)

        run(flow, for: Cooldown.switchPauseSeconds)
        XCTAssertTrue(flow.holding)
        XCTAssertEqual(flow.holdTotal, SetFacts.holdSideSeconds(planned: 15, firstSideHeld: firstSide))

        let secondSide = flow.holdTotal
        run(flow, until: { !flow.holding })
        XCTAssertEqual(flow.actuals[.coreRot],
                       [SetFacts.snap(Double(min(secondSide, firstSide)), unit: .hold)],
                       "one set of a per-side hold is the smaller of its two sides")
        XCTAssertFalse(flow.holdSecondSide)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
    }

    func testTheLastHoldOfAMovementEndsOnItsSummary() throws {
        let (flow, store) = try holdFlow(.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(store.pendingWorkout?.atExerciseSummary, true)
        XCTAssertEqual(signals.tones.last, .done, "the end sounds where the effort stopped")

        signals.events.removeAll()
        flow.leaveExerciseSummary()
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec))
        XCTAssertTrue(flow.holdMeasured.isEmpty)
        XCTAssertEqual(signals.tones, [], "the summary's Done confirms numbers; the end already sounded")
    }

    func testFinishNowOnTheSummaryCountsEverySetOfTheMovementDone() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.phase, .exerciseSummary)
        flow.finishNow()
        XCTAssertNil(flow.setsSkipped[.coreAntiExt],
                     "every set is behind and on the screen — none of them was skipped")
        XCTAssertFalse(flow.skippedPatterns.contains(.coreAntiExt))
        XCTAssertNil(flow.interruptedPattern)
    }

    func testTheSummaryCorrectsOnlyTheCardThatWasTapped() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.setIndex = 2
        flow.actuals[.coreAntiExt] = [15, 15]
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        flow.startSummaryAdjusting(set: 0)
        XCTAssertNil(flow.editing, "only the last card opens the panel")
        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.editing, .summaryCard(2))
        flow.adjustValue = 20
        flow.commitSummaryEdit(set: 2)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [15, 15, 20])
        XCTAssertNil(flow.editing)
    }

    // MARK: - The hands-free run

    func testAHandsFreeRunOpensTheNextSetOnTheRestsOwnGo() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertTrue(flow.restStartsTheNextSet)
        run(flow, for: 60)
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertTrue(flow.holding, "no second count-in: the rest's 3-2-1 was the lead-in")
        XCTAssertFalse(flow.holdCountingIn)
    }

    func testARunStopsWhenItsRestRanOutWithNobodyThere() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        clock += 600
        flow.tick()
        XCTAssertFalse(flow.holdAutoRun)
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertEqual(flow.phase, .work)
        XCTAssertFalse(flow.holding || flow.holdCountingIn,
                       "the work screen comes back with its own button")
    }

    func testSkippingTheRestOfARunCountsTheNextSetIn() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        flow.skipRest()
        XCTAssertTrue(flow.holdCountingIn)
        XCTAssertEqual(flow.holdCountInClock.remaining, GetReady.countInSeconds)
    }

    func testReadingTheTechniqueFreezesOnlyTheRestThatStartsASet() throws {
        let (flow, store) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        run(flow, for: 20)
        flow.freezeRestForTechnique()
        XCTAssertFalse(flow.restClock.isRunning)
        XCTAssertNil(tile.updates.last?.restEndDate)
        XCTAssertEqual(store.pendingWorkout?.restEndDate, clock + 40,
                       "a frozen rest is written as the rest it will be")
        clock += 300
        flow.tick()
        XCTAssertEqual(flow.phase, .rest(seconds: 60), "nothing runs out under the sheet")
        flow.resumeRestCountdown()
        XCTAssertEqual(flow.restClock.endDate, clock + 40)
    }

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
