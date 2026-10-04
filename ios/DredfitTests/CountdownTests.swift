import XCTest
@testable import Dredfit

/// The one countdown every clock of the workout flow runs on. What each
/// clock does when it ends is the flow's; these pin what a tick reads.
@MainActor
final class CountdownTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000)

    // MARK: - Reading

    func testAStartedCountdownRunsFromItsLength() {
        var clock = Countdown()
        XCTAssertFalse(clock.isRunning)
        let end = clock.start(30, now: start)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(end, start + 30)
        XCTAssertEqual(clock.endDate, start + 30)
        XCTAssertEqual(clock.remaining, 30)
        XCTAssertEqual(clock.read(now: start), .unchanged, "the second already shown is not news")
    }

    func testReadingChangesNothingUntilTheSecondIsShown() {
        var clock = Countdown()
        clock.start(30, now: start)
        XCTAssertEqual(clock.read(now: start + 4), .second(26))
        XCTAssertEqual(clock.remaining, 30, "the owner decides when, and how animated")
        XCTAssertEqual(clock.read(now: start + 4), .second(26))
        clock.show(26)
        XCTAssertEqual(clock.read(now: start + 4), .unchanged)
    }

    func testSecondsRoundToTheNearestSoZeroIsTheEnd() {
        var clock = Countdown()
        clock.start(2, now: start)
        XCTAssertEqual(clock.read(now: start + 1.4), .second(1), "0.6 s left still shows 1")
        guard case .ended(let overshoot) = clock.read(now: start + 1.6) else {
            return XCTFail("0.4 s left rounds to 0, which is the end")
        }
        XCTAssertEqual(overshoot, -0.4, accuracy: 0.000_1,
                       "a tick just before the end date reads a negative overshoot")
    }

    func testTheEndCarriesHowLateTheTickCame() {
        // The length of an absence is how a clock tells a beat the person was
        // there for from one that went off in a pocket.
        var clock = Countdown()
        clock.start(60, now: start)
        XCTAssertEqual(clock.read(now: start + 60 + 90), .ended(overshoot: 90))
    }

    func testAStoppedCountdownReadsNothingHoweverLongItStands() {
        var clock = Countdown()
        XCTAssertEqual(clock.read(now: start + 3_600), .unchanged)
        clock.start(10, now: start)
        clock.freeze()
        XCTAssertEqual(clock.read(now: start + 3_600), .unchanged,
                       "with no end date there is nothing to run out")
    }

    // MARK: - Freezing and resuming

    func testAFrozenCountdownResumesFromTheSecondItShowed() {
        var clock = Countdown()
        clock.start(30, now: start)
        clock.show(21)
        clock.freeze()
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.remaining, 21)

        clock.resume(now: start + 600)
        XCTAssertEqual(clock.endDate, start + 621, "the 21 s it froze with, not its whole length")
        XCTAssertEqual(clock.read(now: start + 621), .ended(overshoot: 0))
    }

    func testACountdownFrozenAtZeroNeedsTheFloorToEverEnd() {
        // Resumed with no floor, its end date reads as the 0 already shown, so
        // no tick ever reports the end — the clock would hang on the screen.
        var stuck = Countdown()
        stuck.start(0, now: start)
        stuck.freeze()
        stuck.resume(now: start)
        XCTAssertEqual(stuck.read(now: start + 3_600), .unchanged)

        var floored = Countdown()
        floored.start(0, now: start)
        floored.freeze()
        floored.resume(now: start, atLeast: 1)
        XCTAssertEqual(floored.endDate, start + 1)
        XCTAssertEqual(floored.remaining, 0, "the floor moves the date, not the second on screen")
        XCTAssertEqual(floored.read(now: start), .second(1))
        floored.show(1)
        XCTAssertEqual(floored.read(now: start + 1), .ended(overshoot: 0))
    }

    func testTheFloorLeavesALongerCountdownAlone() {
        var clock = Countdown()
        clock.start(30, now: start)
        clock.show(12)
        clock.freeze()
        clock.resume(now: start + 100, atLeast: 1)
        XCTAssertEqual(clock.endDate, start + 112)
    }

    func testStandingStopsTheClockOnTheSecondGiven() {
        // A hold handed back inside the mis-tap grace stands on its full
        // length again; a rest that is skipped stands on 0.
        var clock = Countdown()
        clock.start(30, now: start)
        clock.show(28)
        clock.stand(at: 30)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.remaining, 30)
        clock.stand(at: 0)
        XCTAssertEqual(clock.remaining, 0)
    }

    func testResettingKeepsARunningClockRunningAndAFrozenOneFrozen() {
        var running = Countdown()
        running.start(30, now: start)
        running.reset(to: 8, now: start + 5)
        XCTAssertEqual(running.remaining, 8)
        XCTAssertEqual(running.endDate, start + 13)

        var frozen = Countdown()
        frozen.start(30, now: start)
        frozen.freeze()
        frozen.reset(to: 8, now: start + 5)
        XCTAssertEqual(frozen.remaining, 8)
        XCTAssertNil(frozen.endDate, "a paused block waits for Resume")
    }

    // MARK: - Moving the end

    func testExtendingMovesTheEndAndTheSecondOnScreen() {
        var clock = Countdown()
        clock.start(60, now: start)
        clock.extend(by: 15, now: start + 50)
        XCTAssertEqual(clock.endDate, start + 75)
        XCTAssertEqual(clock.remaining, 25)
    }

    func testExtendingAStoppedClockStartsNothing() {
        var clock = Countdown()
        clock.extend(by: 15, now: start)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.remaining, 0)
    }

    func testRunningUntilARestoredDateShowsWhatIsLeftOfIt() {
        var clock = Countdown()
        clock.run(until: start + 42.6, now: start)
        XCTAssertEqual(clock.endDate, start + 42.6)
        XCTAssertEqual(clock.remaining, 43)
    }

    // MARK: - The 3-2-1

    func testOnlyTheLastSecondsOnTheWayDownSignal() {
        var clock = Countdown()
        clock.start(10, now: start)
        clock.show(5)
        XCTAssertFalse(clock.signals(4, within: 3), "4 is before the window")
        clock.show(4)
        XCTAssertTrue(clock.signals(3, within: 3))
        clock.show(3)
        XCTAssertFalse(clock.signals(3, within: 3), "the same second twice is one signal")
    }

    func testABackgroundedClockSignalsOnlyTheSecondItLandsOn() {
        // No tick spam after backgrounding: from 30 straight to 2 is one tick.
        var clock = Countdown()
        clock.start(30, now: start)
        guard case .second(let second) = clock.read(now: start + 28) else {
            return XCTFail("two seconds are left")
        }
        XCTAssertEqual(second, 2)
        XCTAssertTrue(clock.signals(second, within: 3))
    }

    func testAnExtendedClockSignalsAgainOnItsNewWayDown() {
        var clock = Countdown()
        clock.start(60, now: start)
        clock.show(2)
        clock.extend(by: 15, now: start + 58)
        XCTAssertEqual(clock.remaining, 17)
        clock.show(4)
        XCTAssertTrue(clock.signals(3, within: 3))
    }
}
