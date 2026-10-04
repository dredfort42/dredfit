import XCTest
import DredfitCore
@testable import Dredfit

/// Holds: the count-in, the clock, Stop, the side switch, the hands-free run
/// and the summary a hold movement ends on.
extension WorkoutSessionTests {

    func holdFlow(_ pattern: Pattern) throws -> (WorkoutSession, AppStore) {
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
                       "a frozen rest is written as the seconds it froze with")
        clock += 300
        flow.tick()
        XCTAssertEqual(flow.phase, .rest(seconds: 60), "nothing runs out under the sheet")
        flow.resumeRestCountdown()
        XCTAssertEqual(flow.restClock.endDate, clock + 40)
    }

    func testARunsRestReadAboutInItsLastSecondsComesBackWithTheWholeCountIn() throws {
        let (flow, store) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, until: { flow.restStartsTheNextSet })
        run(flow, until: { flow.restClock.remaining == 2 })
        flow.freezeRestForTechnique()
        clock += 60
        signals.primes = 0
        signals.events.removeAll()

        flow.resumeRestCountdown()
        let end = clock + TimeInterval(BlockPause.reentrySeconds)
        XCTAssertEqual(flow.restClock.remaining, BlockPause.reentrySeconds,
                       "the end of this rest starts a plank: not two seconds after the page closes")
        XCTAssertEqual(flow.restClock.endDate, end)
        XCTAssertEqual(tile.updates.last?.restEndDate, end, "the lock screen counts to the same moment")
        XCTAssertEqual(store.pendingWorkout?.restEndDate, end)
        XCTAssertEqual(signals.primes, 1, "a minute on the page let the engine go cold")
        run(flow, until: { flow.phase == .work })
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go], "the whole 3-2-1, then the go the hold starts on")
        XCTAssertTrue(flow.holding)
    }

    func testTheSheetsFloorStopsAtTheRestsOwnLength() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, until: { flow.restStartsTheNextSet })
        // No planned rest is shorter than the count-in, so one is started
        // here: the floor must not stretch a rest past its own length.
        flow.startRest(BlockPause.reentrySeconds - 1)
        run(flow, for: 1)
        flow.freezeRestForTechnique()
        clock += 60

        flow.resumeRestCountdown()
        XCTAssertEqual(flow.restClock.remaining, BlockPause.reentrySeconds - 1)
        XCTAssertEqual(flow.restClock.endDate, clock + TimeInterval(BlockPause.reentrySeconds - 1))
    }

    func testAnOrdinaryRestRunsOnUnderTheSheetAndClosingItMovesNothing() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, until: { flow.phase != .work })
        XCTAssertFalse(flow.restStartsTheNextSet, "the premise: this rest hands the screen back and waits")
        run(flow, until: { flow.restClock.remaining == 2 })
        let end = flow.restClock.endDate
        flow.freezeRestForTechnique()
        XCTAssertTrue(flow.restClock.isRunning)

        flow.resumeRestCountdown()
        XCTAssertEqual(flow.restClock.endDate, end, "its end starts nothing, so it takes no floor")
    }

    func testAPausedRunsRestStaysHeldWhenTheSheetCloses() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, until: { flow.restStartsTheNextSet })
        run(flow, until: { flow.restClock.remaining == 2 })
        flow.toggleBlockPause()
        flow.freezeRestForTechnique()
        clock += 60

        flow.resumeRestCountdown()
        XCTAssertTrue(flow.blockPause.isHeld, "the person's own stop outranks the sheet's")
        XCTAssertFalse(flow.restClock.isRunning)
        XCTAssertNil(tile.updates.last?.restEndDate)
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
