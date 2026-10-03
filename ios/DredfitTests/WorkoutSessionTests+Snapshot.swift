import XCTest
import DredfitCore
@testable import Dredfit

/// What survives a backgrounded phone and a process death, and the two
/// guided blocks with their pause.
extension WorkoutSessionTests {

    // MARK: - Restoring after a process death

    func testARestorePicksUpInsideARestStillRunning() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        clock += 10
        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertEqual(flow.restClock.remaining, 50)
        XCTAssertEqual(flow.awaySec, 0, "a rest running on schedule is training, not absence")
    }

    func testARestoreAfterTheRestRanOutLandsOnTheNextSetAndCountsTheAbsence() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        clock += 60 + 300
        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.setIndex, 1, "the advance the timer would have made")
        XCTAssertEqual(flow.awaySec, 300, "measured from the end of the rest, not from the last write")
    }

    func testARestorePastTheLastSetsRestOpensTheNextMovementWithoutItsDeclaration() throws {
        let store = makeStore()
        let first = makeFlow(store, session: holdSession())
        first.declineWarmup()
        let index = try index(of: .coreAntiExt, in: first)
        XCTAssertLessThan(index, first.exercises.count - 1, "a movement must follow it")
        first.exIndex = index
        first.holdDeclared = 45
        first.setIndex = 2
        first.completeSet()
        XCTAssertEqual(first.phase, .exerciseSummary)
        first.leaveExerciseSummary()
        let snapshot = try XCTUnwrap(store.pendingWorkout)
        XCTAssertEqual(snapshot.holdDeclaredSec, 45)

        clock += 600
        let flow = makeFlow(store, session: holdSession(), resume: snapshot)
        XCTAssertEqual(flow.exIndex, index + 1)
        XCTAssertEqual(flow.setIndex, 0)
        XCTAssertNil(flow.holdDeclared, "the declaration belongs to the movement behind")
    }

    func testARestoreFromTheCoolDownLandsOnTheRating() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.exIndex = first.exercises.count - 1
        first.setIndex = 2
        first.completeSet()
        XCTAssertEqual(first.phase, .cooldownIntro)
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .feedback)
    }

    func testTheSummaryOfAFinishedHoldSurvivesAProcessDeath() throws {
        let store = makeStore()
        let first = makeFlow(store, session: holdSession())
        first.declineWarmup()
        first.exIndex = try index(of: .coreAntiExt, in: first)
        first.setIndex = 2
        first.startHold()
        run(first, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(first.phase, .exerciseSummary)

        let flow = makeFlow(store, session: holdSession(), resume: try XCTUnwrap(store.pendingWorkout))
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(flow.holdMeasured[2], 15)
    }

    func testKeepingTheWorkoutFromTodayCataloguesItWithoutRunningIt() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)
        tile.started = nil

        let flow = makeFlow(store, resume: snapshot, settle: true)
        XCTAssertEqual(flow.phase, .feedback)
        XCTAssertNil(tile.started, "nothing for the lock screen to describe on the rating")
    }

    // MARK: - An absence the process lived through

    func testAnAbsenceIsSubtractedAndARunningRestIsNot() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.sceneLeft()
        clock += 1_800
        flow.sceneCameBack()
        XCTAssertEqual(flow.awaySec, 1_800)

        flow.completeSet()
        flow.sceneLeft()
        clock += 600
        flow.sceneCameBack()
        XCTAssertEqual(flow.awaySec, 1_800 + 540, "the 60 s rest that was running is training")
    }

    func testOnlyTheFirstLeavingCounts() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.sceneLeft()
        clock += 100
        flow.sceneLeft()
        clock += 100
        flow.sceneCameBack()
        XCTAssertEqual(flow.awaySec, 200)
    }

    // MARK: - The guided blocks

    func testTheWarmUpWaitsToBeAskedAndNoMeansStraightToTheWork() {
        let store = makeStore()
        let flow = makeFlow(store)
        XCTAssertEqual(flow.phase, .warmupIntro)
        XCTAssertEqual(tile.started?.title, String(localized: "WARM-UP"))
        flow.declineWarmup()
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.warmupSec, 0, "a declined block bills nothing")
        XCTAssertEqual(store.pendingWorkout?.warmupSec, 0)
    }

    func testTheWarmUpRunsToTheWorkAndBillsTheTimeItRan() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        XCTAssertEqual(flow.phase, .warmup)
        XCTAssertEqual(flow.warmupClock.remaining, GetReady.countInSeconds,
                       "a start tap opens on the count-in")
        let ran = run(flow, until: { flow.phase == .work }, limit: 1_000)
        XCTAssertEqual(flow.warmupSec, ran)
        XCTAssertEqual(signals.tones.last, .done)
    }

    func testAWarmUpBoundaryCrossedWhileAwayFreezesTheBlockAndBillsNothingOfIt() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        clock += 600
        flow.tick()
        XCTAssertTrue(flow.blockPause.isHeld)
        XCTAssertEqual(flow.phase, .warmup)
        XCTAssertFalse(flow.warmupClock.isRunning)
        XCTAssertEqual(flow.warmupClock.remaining, GetReady.countInSeconds,
                       "frozen on the second it showed")
        XCTAssertEqual(flow.blockPausedSec, 600 - GetReady.countInSeconds)
        XCTAssertTrue(signals.events.contains(.announce(String(localized: "Paused"))))

        clock += 100
        flow.tick()
        XCTAssertTrue(flow.blockPause.isHeld, "a held block has nothing left to run out")
        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused, "a frozen transition is its own way back in")
        XCTAssertTrue(flow.warmupClock.isRunning)
        XCTAssertEqual(flow.blockPausedSec, 700 - GetReady.countInSeconds)
    }

    func testAPausedMoveCountsTheAthleteBackInBeforeItRunsOn() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, until: { flow.warmupStage != .getReady })
        run(flow, for: 3)
        let frozen = flow.warmupClock.remaining
        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isHeld)
        clock += 50
        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isReentering)
        XCTAssertEqual(flow.blockPause.reentryRemaining, BlockPause.reentrySeconds)

        signals.events.removeAll()
        run(flow, for: BlockPause.reentrySeconds)
        XCTAssertFalse(flow.blockPause.isPaused)
        XCTAssertEqual(flow.warmupClock.remaining, frozen, "the move picks up the seconds it froze with")
        XCTAssertEqual(flow.warmupClock.endDate, clock + TimeInterval(frozen))
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(flow.blockPausedSec, 50, "the way back in is the block again")
    }

    func testTheCoolDownIsOfferedAfterTheLastSetAndEndsOnTheRating() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        XCTAssertEqual(flow.phase, .cooldownIntro)
        flow.beginCooldown()
        XCTAssertEqual(flow.phase, .cooldown)
        let ran = run(flow, until: { flow.phase == .feedback }, limit: 1_000)
        XCTAssertEqual(flow.cooldownSec, ran)
        XCTAssertEqual(signals.tones.last, .workoutDone)
        XCTAssertEqual(tile.ended, 1)
    }

    func testDecliningTheCoolDownGoesStraightToTheRating() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.declineCooldown()
        XCTAssertEqual(flow.phase, .feedback)
        XCTAssertEqual(flow.cooldownSec, 0)
    }
}
