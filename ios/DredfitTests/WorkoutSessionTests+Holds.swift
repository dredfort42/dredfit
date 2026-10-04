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

    /// A set a thumb ended at 33 s on the clock records 30, the clock less the
    /// reach allowance, and the line above its panel names that number as the
    /// estimate it is. A correction does not change who ended the set, so the
    /// line says the same after one — "the clock saw 30 s" would pass the
    /// estimate off as a measurement. The card's "≈" stands while the card
    /// carries the thumb's number: OK on it keeps the mark, a number of the
    /// person's own takes it off.
    func testACorrectedSetStoppedByHandIsNotPassedOffAsTheClocksCount() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(45, on: flow)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 33)
        flow.stopHoldEarly()
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [15, 15, 30], "33 s on the clock less the 3 s reach")
        let estimate = String(localized: "set \(3) · stopped by hand at about \(30) s")

        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.summaryPanelLine(set: 2), estimate)
        XCTAssertTrue(flow.summaryCardIsApproximate(set: 2))

        flow.commitSummaryEdit(set: 2)   // OK on the number as it stands
        XCTAssertTrue(flow.summaryCardIsApproximate(set: 2), "the card still carries the thumb's number")
        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.summaryPanelLine(set: 2), estimate)

        flow.adjustValue = 35   // one "+" on the panel's five-second grid
        flow.commitSummaryEdit(set: 2)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [15, 15, 35])
        XCTAssertFalse(flow.summaryCardIsApproximate(set: 2), "the card carries the person's number now")
        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.summaryPanelLine(set: 2), estimate, "the clock saw neither 30 nor 35")
    }

    /// A per-side set whose first side a thumb ended is marked as an estimate
    /// before it has recorded anything. A second side stopped inside the
    /// mis-tap grace hands the set back with "Skip this set" live, and a set
    /// skipped from there records nothing — its card on the summary shows the
    /// number it falls back to, and must not print "≈ · stopped by hand" over
    /// it. A set that did record an estimate keeps its mark through the skip.
    func testASkippedSetLeavesNoEstimateOnTheSummary() throws {
        let (flow, _) = try holdFlow(.coreRot)
        // Set one: a thumb ends the first side, the clock the second.
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        run(flow, until: { flow.phase != .work })
        flow.skipRest()

        // Set two: a thumb ends the first side, the second is handed back.
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 5)
        flow.stopHoldEarly()
        run(flow, for: Cooldown.switchPauseSeconds + 2)
        flow.stopHoldEarly()
        XCTAssertTrue(flow.holdSecondSide, "the grace handed the second side back")
        flow.skipSet()

        // Set three runs on the clock to the summary.
        flow.startHold()
        run(flow, until: { flow.phase == .exerciseSummary })
        XCTAssertTrue(flow.summaryCardIsApproximate(set: 0), "set one recorded an estimate")
        XCTAssertFalse(flow.summaryCardIsApproximate(set: 1), "set two recorded nothing")
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

    /// The same threshold as the blocks', to the fraction
    /// (`testAWarmUpBoundaryMissedByAFractionPastTheThresholdFreezes`).
    func testARestMissedByAFractionPastTheThresholdDropsTheRun() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        let end = try XCTUnwrap(flow.restClock.endDate, "the premise: a rest is running")
        clock = end.addingTimeInterval(Double(BlockPause.absenceSeconds) + 0.6)
        flow.tick()
        XCTAssertFalse(flow.holdAutoRun)
    }

    func testARestMissedByExactlyTheThresholdKeepsTheRun() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        let end = try XCTUnwrap(flow.restClock.endDate, "the premise: a rest is running")
        clock = end.addingTimeInterval(Double(BlockPause.absenceSeconds))
        flow.tick()
        XCTAssertTrue(flow.holdAutoRun)
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
}
