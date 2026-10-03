import XCTest
import DredfitCore
@testable import Dredfit

/// The second tap of a double tap. The settle window keeps it off the next
/// screen; these pin the other half — a transition reached a second time
/// from a screen that has already moved on does nothing.
extension WorkoutSessionTests {

    func testASecondSkipRestDoesNotSkipASet() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipRest()
        flow.skipRest()
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertEqual(flow.phase, .work)
    }

    func testASecondDoneDoesNotRestartTheRest() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        let end = flow.restClock.endDate
        clock += 1
        flow.completeSet()
        XCTAssertEqual(flow.restClock.endDate, end)
        XCTAssertEqual(flow.setIndex, 0)
    }

    func testStartingTheWarmUpTwiceDoesNotStartItOver() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        let began = flow.warmupBeganAt
        run(flow, for: 2)
        flow.beginWarmup()
        XCTAssertEqual(flow.warmupBeganAt, began)
        XCTAssertEqual(flow.warmup.clock.remaining, GetReady.countInSeconds - 2)
    }

    func testDecliningTheWarmUpTwiceLeavesTheWorkAlone() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.declineWarmup()
        XCTAssertEqual(flow.phase, .rest(seconds: 60), "a stale decline must not pull the flow out of a rest")
    }

    func testSkippingTheCoolDownTwiceEndsItOnce() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        flow.finishCooldown()
        flow.finishCooldown()
        flow.declineCooldown()
        XCTAssertEqual(flow.phase, .feedback)
        XCTAssertEqual(tile.ended, 1)
    }

    func testTheSummarysDoneTwiceDoesNotTouchTheRestAfterIt() throws {
        let store = makeStore()
        let flow = makeFlow(store, session: holdSession())
        flow.declineWarmup()
        flow.exIndex = try index(of: .coreAntiExt, in: flow)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.phase, .exerciseSummary)
        flow.leaveExerciseSummary()
        let end = flow.restClock.endDate
        clock += 1
        flow.leaveExerciseSummary()
        XCTAssertEqual(flow.restClock.endDate, end)
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec))
    }

    func testAStaleStartHoldDoesNotStartOneInsideTheRest() throws {
        let store = makeStore()
        let flow = makeFlow(store, session: holdSession())
        flow.declineWarmup()
        flow.exIndex = try index(of: .coreAntiExt, in: flow)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        flow.startHold()
        XCTAssertFalse(flow.holdCountingIn || flow.holding)
    }

    func testAStaleSkipLandsOnNothingOnceTheSetHasMovedOn() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipSet()
        flow.skipRestOfExercise()
        flow.leaveExercise()
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertTrue(flow.setsSkipped.isEmpty)
        XCTAssertTrue(flow.skippedPatterns.isEmpty)
    }

    // Each guard on its own. The pairs above (skipRest → advanceAfterRest,
    // declineWarmup → finishWarmup, leaveExerciseSummary → completeSet,
    // declineCooldown → finishCooldown) stop a second tap with either guard
    // alone; these reach each one where its partner cannot.

    func testASkipRestOutsideARestLeavesAPausedBlockPaused() {
        let flow = makeFlow(makeStore())
        flow.beginWarmup()
        flow.pauseBlock()
        XCTAssertTrue(flow.blockPause.isPaused, "the premise")
        flow.skipRest()
        XCTAssertTrue(flow.blockPause.isPaused)
    }

    func testAnAdvanceOutsideARestLeavesTheSetWhereItIs() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.advanceAfterRest(countIn: true)
        XCTAssertEqual(flow.setIndex, 0)
        XCTAssertEqual(flow.phase, .work)
    }

    func testADeclineDuringTheWarmUpDoesNotEndIt() {
        let flow = makeFlow(makeStore())
        flow.beginWarmup()
        flow.declineWarmup()
        XCTAssertEqual(flow.phase, .warmup)
    }

    func testAStaleWarmUpEndingLeavesTheRestAlone() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.completeSet()
        flow.finishWarmup()
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
    }

    func testTheSummarysDoneOnTheWorkScreenLogsNoSet() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.leaveExerciseSummary()
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.setIndex, 0)
    }

    func testStartingTheCoolDownTwiceDoesNotStartItOver() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        let began = flow.cooldownBeganAt
        run(flow, for: 2)
        flow.beginCooldown()
        XCTAssertEqual(flow.cooldownBeganAt, began)
        XCTAssertEqual(flow.cooldown.clock.remaining, GetReady.countInSeconds - 2)
    }

    func testADeclineDuringTheCoolDownDoesNotEndIt() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        flow.declineCooldown()
        XCTAssertEqual(flow.phase, .cooldown)
    }

    func testAStaleSkipOfTheRestOfAMovementTakesNoSetsOff() {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.setIndex = 2
        flow.completeSet()
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec), "the premise")
        flow.skipRestOfExercise()
        XCTAssertTrue(flow.setsSkipped.isEmpty)
    }
}
