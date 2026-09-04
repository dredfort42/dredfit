import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class BlockPauseTests: XCTestCase {

    // MARK: - The way back in

    func testTheWayBackInIsTheCountIn() {
        // A third length would be a third thing to learn: the app counts you
        // in over five seconds before a position (#52), between the sides of
        // one (#35), and after every start tap. The way back in is the same
        // beat — Resume is tapped by someone already standing in place, so
        // there is no travel to pay for. It followed the TRANSITION until
        // 27.08.2026, which made it ten and put two opposite reasons in the
        // tree at once; owner's decision settled it on the count-in.
        //
        // Pinned twice, per §41.8: once against the constant it is wired to,
        // and once against the NUMBER — a pin that only says "equals that
        // other symbol" moves silently when the symbol does.
        XCTAssertEqual(BlockPause.reentrySeconds, GetReady.countInSeconds)
        XCTAssertEqual(BlockPause.reentrySeconds, 5)
        XCTAssertEqual(BlockPause.reentrySeconds, Cooldown.sideSwitchPauseSec,
                       "the side-switch pause is the same beat, and they are one number again")
        XCTAssertLessThan(BlockPause.reentrySeconds, GetReady.seconds,
                          "travel to a position is longer than being counted back into one")
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
        // And in the warm-up too since §41.12. Asked of BOTH blocks on
        // purpose: the rule lived in one of two identical stage machines, and
        // "applied to one branch of two" is the defect class the whole
        // reference audit is built around.
        XCTAssertFalse(BlockPause.needsReentry(Warmup.Stage.switchPause),
                       "the warm-up's side-switch beat is a transition too")
    }

    func testEveryStageThatIsAPositionGetsTheWayBackIn() {
        for stage in [Warmup.Stage.move, .firstSide, .secondSide] {
            XCTAssertTrue(BlockPause.needsReentry(stage),
                          "\(stage) drops the user into a move, so it has to count them in")
        }
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
        let positions = Cooldown.positions(performed: [.pull])
        let warmup = Warmup.moves(sessionNumber: 1)
        XCTAssertEqual(Warmup.stageSeconds(.move, of: warmup[0]), Warmup.moveSeconds)
        XCTAssertEqual(Warmup.stageSeconds(.getReady, of: warmup[0]), GetReady.seconds)
        XCTAssertEqual(Warmup.stageSeconds(.firstSide, of: warmup[0]), Warmup.sideSeconds)
        XCTAssertEqual(Warmup.stageSeconds(.switchPause, of: warmup[0]),
                       Cooldown.sideSwitchPauseSec,
                       "§41.12: one gesture, one length — the cool-down's constant")
        XCTAssertEqual(Cooldown.stageSeconds(.single, of: positions[0]),
                       Cooldown.positionSeconds)
        XCTAssertEqual(Cooldown.stageSeconds(.firstSide, of: positions[0]),
                       Cooldown.sideSeconds)
        XCTAssertEqual(Cooldown.stageSeconds(.switchPause, of: positions[0]),
                       Cooldown.sideSwitchPauseSec)
    }
}
