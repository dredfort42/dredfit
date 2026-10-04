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

    func testACountInThatStartsOverIsPrimedAgain() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        clock += 30
        signals.primes = 0
        flow.tick()
        XCTAssertTrue(flow.holdCountingIn, "the premise")
        XCTAssertEqual(signals.primes, 1, "the absence that ended the first count-in let the engine go cold")
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
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

    // MARK: - What a Stop records

    /// `ticks` seconds of the running hold pass the way the view's timer runs
    /// them, then `plus` more with no tick — where a thumb lands — and Stop is
    /// tapped. Returns the figure the last tick put on the button, read before
    /// the gap: the button is drawn on the tick, and a figure read at the tap
    /// would agree with a record taken off the live clock by moving with it.
    private func tapStop(_ flow: WorkoutSession, afterTicks ticks: Int,
                         plus: TimeInterval) -> Int? {
        run(flow, for: ticks)
        let named = flow.holdStopRecords
        clock += plus
        flow.stopHoldEarly()
        return named
    }

    /// The figure on the button moves only on a tick, and the clock does not
    /// wait for one: seven tenths past the tick it is nearer the next second
    /// than the one the button names, and a tick that comes late leaves the
    /// button more than a second behind it.
    func testAStopBetweenTwoTicksStoresTheFigureTheButtonNamed() throws {
        for gap in [0.7, 1.2] {
            let (flow, _) = try holdFlow(.coreAntiExt)
            flow.startHold()
            run(flow, for: GetReady.countInSeconds)
            let named = try XCTUnwrap(tapStop(flow, afterTicks: 10, plus: gap))
            XCTAssertEqual(flow.holdMeasured[0], named, "\(gap) s past the tick")
        }
    }

    /// On the tick itself: on the whole second, and on a tick the timer
    /// delivered late, as it does when the main thread is busy — that one
    /// puts the clock's ROUNDED second on the button, a second more than a
    /// truncated clock would store.
    func testAStopOnATickStoresTheFigureThatTickPutOnTheButton() throws {
        for late in [0.0, 0.6] {
            let (flow, _) = try holdFlow(.coreAntiExt)
            flow.startHold()
            run(flow, for: GetReady.countInSeconds + 10)
            clock += late
            flow.tick()
            let named = try XCTUnwrap(tapStop(flow, afterTicks: 0, plus: 0))
            XCTAssertEqual(flow.holdMeasured[0], named, "a tick \(late) s late")
        }
    }

    /// A plain "Stop" is the grace, even with the clock already past its
    /// three seconds: the tap does what the button says, and it names nothing.
    func testAStopWhileTheButtonNamesNoFigureStoresNothing() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertNil(tapStop(flow, afterTicks: 3, plus: 0.5), "the button names no figure")
        XCTAssertEqual(flow.holdClock.remaining, 15, "the set stands at its full length again")
        XCTAssertNil(flow.actuals[.coreAntiExt])
        XCTAssertTrue(flow.holdApproxSets.isEmpty)
        XCTAssertEqual(flow.phase, .work)
    }

    /// The first side's figure is what the second side runs for, and the
    /// second side's is what the set stores. Declared at 30 s so both figures
    /// stand clear of the five-second floor, where a second more or less
    /// would not show.
    func testEachSideOfAPerSideHoldStoresTheFigureItsButtonNamed() throws {
        let (flow, _) = try holdFlow(.coreRot)
        declare(30, on: flow)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds)
        let firstSide = try XCTUnwrap(tapStop(flow, afterTicks: 20, plus: 0.7))
        XCTAssertEqual(flow.firstSideHeld, firstSide)

        run(flow, for: Cooldown.switchPauseSeconds)
        XCTAssertTrue(flow.holding, "the second side runs")
        let secondSide = try XCTUnwrap(tapStop(flow, afterTicks: 12, plus: 0.7))
        XCTAssertEqual(flow.holdMeasured[0], secondSide)
    }

    /// A set the hands-free run opened on the rest's own go stops like any
    /// other.
    func testAStopInASetTheRunOpenedStoresTheFigureTheButtonNamed() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15 + 60)
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertTrue(flow.holding, "the rest's go opened the set")
        let named = try XCTUnwrap(tapStop(flow, afterTicks: 10, plus: 0.7))
        XCTAssertEqual(flow.holdMeasured[1], named)
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

    func testTheCountInAfterSkipRestIsPrimedOnceASecondBeforeItsFirstTick() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        signals.primes = 0
        flow.startHoldExercise()
        XCTAssertEqual(signals.primes, 1, "a tap on Start opens the same count-in")
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertTrue(flow.restStartsTheNextSet, "the premise")
        signals.primes = 0
        signals.events.removeAll()

        flow.skipRest()
        XCTAssertTrue(flow.holdCountingIn, "the premise")
        XCTAssertEqual(signals.primes, 1, "Skip rest sounds nothing, and the count-in opens on the second before its 3")
        run(flow, for: 1)
        XCTAssertEqual(signals.tones, [.tick])
        run(flow, for: GetReady.countInSeconds - 1)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testARunsRestResumedInItsLastSecondsIsPrimedOnceASecondBeforeItsFirstTick() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertTrue(flow.restStartsTheNextSet, "the premise")
        run(flow, until: { flow.restClock.remaining == 2 })
        flow.toggleBlockPause()
        clock += 120
        signals.primes = 0
        signals.events.removeAll()

        flow.toggleBlockPause()
        XCTAssertEqual(flow.restClock.remaining, BlockPause.reentrySeconds,
                       "the premise: a resumed rest picks up at no less than the count-in")
        XCTAssertEqual(signals.primes, 1, "two minutes paused let the engine go cold")
        run(flow, for: 1)
        XCTAssertEqual(signals.tones, [.tick])
        run(flow, for: BlockPause.reentrySeconds - 1)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testARunsRestResumedWithTimeLeftIsPrimedOnlyAtItsFour() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertTrue(flow.restStartsTheNextSet, "the premise")
        run(flow, until: { flow.restClock.remaining == 30 })
        flow.toggleBlockPause()
        clock += 120
        signals.primes = 0

        flow.toggleBlockPause()
        XCTAssertEqual(flow.restClock.remaining, 30, "the premise: a rest with time left keeps it")
        XCTAssertEqual(signals.primes, 0, "thirty seconds out, a prime would be cold again by the 3")
        run(flow, until: { flow.restClock.remaining == BlockPause.reentrySeconds })
        XCTAssertEqual(signals.primes, 1)
        run(flow, for: BlockPause.reentrySeconds)
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testNothingIsPrimedWithTheSoundsOff() throws {
        let (flow, store) = try holdFlow(.coreAntiExt)
        store.update(refreshWidget: false) { $0.settings.soundsEnabled = false }
        signals.primes = 0
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertTrue(flow.restStartsTheNextSet, "the premise")
        flow.skipRest()
        XCTAssertTrue(flow.holdCountingIn, "the premise")
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(signals.primes, 0, "the haptic is half of a signal the switch has turned off")
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
