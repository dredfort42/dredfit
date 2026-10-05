import XCTest
import DredfitCore
@testable import Dredfit

/// The hands-free run of a hold movement: the rest that opens the next set
/// on its own go — when it drops the run, what a tap, a pause and the
/// technique sheet do to that rest, and the prime before its 3-2-1.
extension WorkoutSessionTests {

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

    func testAPausedRunsRestStaysHeldAndSaysSoUnderTheSheet() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, until: { flow.restStartsTheNextSet })
        run(flow, until: { flow.restClock.remaining == 2 })
        flow.toggleBlockPause()
        XCTAssertEqual(tile.updates.last?.detail, String(localized: "Paused"), "the premise")
        flow.freezeRestForTechnique()
        XCTAssertEqual(tile.updates.last?.detail, String(localized: "Paused"),
                       "the lock screen must not promise that a held rest starts by itself")
        clock += 60

        flow.resumeRestCountdown()
        XCTAssertTrue(flow.blockPause.isHeld, "the person's own stop outranks the sheet's")
        XCTAssertFalse(flow.restClock.isRunning)
        XCTAssertNil(tile.updates.last?.restEndDate)
        XCTAssertEqual(tile.updates.last?.detail, String(localized: "Paused"))
    }
}
