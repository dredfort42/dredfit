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

    func testARestRestoredInItsLastHalfSecondStillEnds() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        clock += 59.7
        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertEqual(flow.restClock.remaining, 0)
        run(flow, for: 1)
        XCTAssertEqual(flow.phase, .work, "the rest ends instead of hanging on 0")
        XCTAssertEqual(flow.setIndex, 1)
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
        XCTAssertEqual(flow.warmup.clock.remaining, GetReady.countInSeconds,
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
        XCTAssertFalse(flow.warmup.clock.isRunning)
        XCTAssertEqual(flow.warmup.clock.remaining, GetReady.countInSeconds,
                       "frozen on the second it showed")
        XCTAssertEqual(flow.blockPausedSec, 600 - GetReady.countInSeconds)
        XCTAssertTrue(signals.events.contains(.announce(String(localized: "Paused"))))

        clock += 100
        flow.tick()
        XCTAssertTrue(flow.blockPause.isHeld, "a held block has nothing left to run out")
        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused, "a frozen transition is its own way back in")
        XCTAssertTrue(flow.warmup.clock.isRunning)
        XCTAssertEqual(flow.blockPausedSec, 700 - GetReady.countInSeconds)
    }

    func testAPausedMoveCountsTheAthleteBackInBeforeItRunsOn() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, until: { flow.warmup.stage != .getReady })
        run(flow, for: 3)
        let frozen = flow.warmup.clock.remaining
        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isHeld)
        clock += 50
        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isReentering)
        XCTAssertEqual(flow.blockPause.reentryRemaining, BlockPause.reentrySeconds)

        signals.events.removeAll()
        run(flow, for: BlockPause.reentrySeconds)
        XCTAssertFalse(flow.blockPause.isPaused)
        XCTAssertEqual(flow.warmup.clock.remaining, frozen, "the move picks up the seconds it froze with")
        XCTAssertEqual(flow.warmup.clock.endDate, clock + TimeInterval(frozen))
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(flow.blockPausedSec, 50, "the way back in is the block again")
    }

    func testATransitionFrozenByAnAbsenceNearItsEndGetsItsWholeCountBack() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, for: GetReady.countInSeconds - 2)
        XCTAssertEqual(flow.warmup.clock.remaining, 2)
        clock += 60
        flow.tick()
        XCTAssertTrue(flow.blockPause.isHeld)
        XCTAssertEqual(flow.warmup.stage, .getReady)

        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused, "a frozen transition is its own way back in")
        XCTAssertEqual(flow.warmup.clock.endDate, clock + TimeInterval(GetReady.countInSeconds),
                       "two seconds would put someone who has just come back into the move with no count")
        signals.events.removeAll()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertNotEqual(flow.warmup.stage, .getReady)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
    }

    func testASideSwitchPausedNearItsEndGetsTheCountInBack() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, until: { flow.warmup.stage == .switchPause }, limit: 1_000)
        run(flow, until: { flow.warmup.clock.remaining == 1 })
        flow.toggleBlockPause()
        clock += 30
        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused, "the switch is a transition too")
        XCTAssertEqual(flow.warmup.clock.endDate, clock + TimeInterval(GetReady.countInSeconds))
        signals.events.removeAll()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(flow.warmup.stage, .secondHalf)
        XCTAssertEqual(signals.tones, [.go], "no 3-2-1 inside the switch: its go is its signal")
    }

    func testACoolDownTransitionPausedNearItsEndGetsTheCountInBack() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow, until: { flow.cooldown.clock.remaining == 1 })
        XCTAssertEqual(flow.cooldown.stage, .getReady)
        flow.toggleBlockPause()
        clock += 30
        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused)
        XCTAssertEqual(flow.cooldown.clock.endDate, clock + TimeInterval(GetReady.countInSeconds))
        signals.events.removeAll()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
    }

    func testAMovePausedNearItsEndKeepsItsSecondsAfterTheWayBackIn() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, until: { BlockPause.needsReentry(flow.warmup.stage) && flow.warmup.clock.remaining == 2 },
            limit: 1_000)
        flow.toggleBlockPause()
        clock += 30
        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isReentering)
        run(flow, for: BlockPause.reentrySeconds)
        XCTAssertFalse(flow.blockPause.isPaused)
        XCTAssertEqual(flow.warmup.clock.endDate, clock + 2, "the floor is a transition's, never a position's")
    }

    func testACoolDownStretchPausedNearItsEndKeepsItsSecondsAfterTheWayBackIn() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow, until: { BlockPause.needsReentry(flow.cooldown.stage) && flow.cooldown.clock.remaining == 2 })
        flow.toggleBlockPause()
        clock += 30
        flow.toggleBlockPause()
        run(flow, for: BlockPause.reentrySeconds)
        XCTAssertFalse(flow.blockPause.isPaused)
        XCTAssertEqual(flow.cooldown.clock.endDate, clock + 2,
                       "the cool-down's own stage decides, whatever the warm-up was left on")
    }

    func testTheTechniqueSheetHandsATransitionBackExactlyWhatItFroze() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, for: GetReady.countInSeconds - 1)
        XCTAssertEqual(flow.warmup.clock.remaining, 1)
        flow.freezeForPositionTechnique()
        clock += 30
        flow.resumePositionCountdown()
        XCTAssertEqual(flow.warmup.clock.endDate, clock + 1,
                       "reading is not a pause: the floor belongs to the way back from one")
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
