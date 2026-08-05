//
//  BlockPauseTests.swift
//  DredfitTests
//

import XCTest
@testable import Dredfit

@MainActor
final class BlockPauseTests: XCTestCase {

    // MARK: - The way back in

    func testTheWayBackInIsTheAppsOneTransitionLength() {
        // A third length would be a third thing to learn: the app already
        // counts you in over five seconds before a position (#52) and between
        // the sides of one (#35).
        XCTAssertEqual(BlockPause.reentrySeconds, GetReady.seconds)
        XCTAssertEqual(BlockPause.reentrySeconds, Cooldown.sideSwitchPauseSec)
    }

    func testTheWayBackInLeavesRoomForTheCountdownItPlays() {
        // The 3-2-1 has to fit inside it with a beat to spare for finding the
        // position again — that is the whole reason it exists rather than
        // dropping the user back mid-count.
        XCTAssertGreaterThan(BlockPause.reentrySeconds, 3)
    }

    // MARK: - Which stages need one

    func testAFrozenTransitionIsItsOwnWayBackIn() {
        // Each still has its own signal ahead of it — the 3-2-1 into the go
        // that starts a position, the go into the second side. A lead-in
        // ending on a go of its own would sound the same thing twice.
        XCTAssertFalse(BlockPause.needsReentry(Warmup.Stage.getReady))
        XCTAssertFalse(BlockPause.needsReentry(Cooldown.Stage.getReady))
        XCTAssertFalse(BlockPause.needsReentry(Cooldown.Stage.switchPause),
                       "the side-switch beat is a transition like any other")
    }

    func testEveryStageThatIsAPositionGetsTheWayBackIn() {
        XCTAssertTrue(BlockPause.needsReentry(Warmup.Stage.move))
        for stage in [Cooldown.Stage.single, .firstSide, .secondSide] {
            XCTAssertTrue(BlockPause.needsReentry(stage),
                          "\(stage) drops the user into a position, so it has to count them in")
        }
    }

    func testAZeroLengthWayBackInJustHolds() {
        // It would otherwise leave an end date no tick can ever retire.
        var state = BlockPause.State()
        state.beginReentry(seconds: 0, now: .now)
        XCTAssertTrue(state.isHeld)
        XCTAssertNil(state.reentryEndDate)
    }

    // MARK: - The state itself

    func testAHeldBlockHasNoDeadlineToRunOut() {
        // Which is why a locked or backgrounded phone costs a paused block
        // nothing: there is no end date left anywhere to expire.
        var state = BlockPause.State()
        state.hold()
        XCTAssertTrue(state.isPaused)
        XCTAssertTrue(state.isHeld)
        XCTAssertFalse(state.isReentering)
        XCTAssertNil(state.reentryEndDate)
        XCTAssertEqual(state.tick(now: .now + 3_600, signalSeconds: 3), .nothing,
                       "an hour away must not move a held block")
    }

    func testTheWayBackInTicksDownAndThenHandsOver() {
        let start = Date(timeIntervalSince1970: 1_000)
        var state = BlockPause.State()
        state.beginReentry(seconds: 5, now: start)
        XCTAssertTrue(state.isReentering)
        XCTAssertFalse(state.isHeld, "counting back in is not standing still")

        XCTAssertEqual(state.tick(now: start + 1, signalSeconds: 3), .redraw)
        XCTAssertEqual(state.reentryRemaining, 4)
        XCTAssertEqual(state.tick(now: start + 2, signalSeconds: 3), .signal,
                       "the last three seconds are the 3-2-1")
        XCTAssertEqual(state.tick(now: start + 2, signalSeconds: 3), .nothing,
                       "the same second twice is not a second")
        XCTAssertEqual(state.tick(now: start + 5, signalSeconds: 3), .over)
    }

    func testPausingAgainMidWayBackInHoldsTheBlock() {
        var state = BlockPause.State()
        state.beginReentry(seconds: 5, now: .now)
        state.hold()
        XCTAssertTrue(state.isHeld)
        XCTAssertEqual(state.reentryRemaining, 0, "the lead-in starts over on the next resume")
    }

    func testThePauseOutranksTheTechniqueSheetsOwnFreeze() {
        // #34 freezes the countdown while the mini-sheet is open and hands it
        // back on dismissal. Over a held block it must hand back nothing.
        var state = BlockPause.State()
        state.hold()
        state.freezeForSheet()
        state.thawAfterSheet(now: .now)
        XCTAssertTrue(state.isHeld, "closing the sheet must not restart a stopped block")
        XCTAssertNil(state.reentryEndDate)
    }

    func testTheSheetFreezesTheWayBackInAndHandsBackWhatItFroze() {
        let start = Date(timeIntervalSince1970: 1_000)
        var state = BlockPause.State()
        state.beginReentry(seconds: 5, now: start)
        _ = state.tick(now: start + 2, signalSeconds: 3)     // 3 left

        state.freezeForSheet()
        XCTAssertEqual(state.tick(now: start + 600, signalSeconds: 3), .nothing,
                       "reading is not getting back into position either")

        state.thawAfterSheet(now: start + 600)
        XCTAssertEqual(state.reentryRemaining, 3)
        XCTAssertEqual(state.tick(now: start + 603, signalSeconds: 3), .over,
                       "it picks up the three seconds it was frozen with")
    }

    // MARK: - Honest numbers

    func testThePauseAddsNothingToWhatTheBlocksPromise() {
        // The pause is user-initiated, so no estimate moves (#61 follows the
        // precedent of #52). What the blocks cost uninterrupted is unchanged
        // by this feature — the stage lengths are the same ones GetReadyTests
        // measures against the reserved minutes.
        XCTAssertEqual(Warmup.stageSeconds(.move), Warmup.moveSeconds)
        XCTAssertEqual(Warmup.stageSeconds(.getReady), GetReady.seconds)
        XCTAssertEqual(Cooldown.stageSeconds(.single), Cooldown.positionSeconds)
        XCTAssertEqual(Cooldown.stageSeconds(.firstSide), Cooldown.sideSeconds)
        XCTAssertEqual(Cooldown.stageSeconds(.switchPause), Cooldown.sideSwitchPauseSec)
    }
}
