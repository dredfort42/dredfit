//
//  Deliberately NOT run under --uitest-fast: collapsing the transition to a
//  second would turn every assertion here into a race.
//
//  Anything that TAPS the transition runs under --uitest-long-transition
//  instead — "I'm ready" is on screen only while the transition runs, and at
//  its real length resolve-element-then-tap must fit inside five seconds on a
//  saturated runner (I-5). Only the hand-over test keeps the real length,
//  because expiring on its own is what it asserts.
//

import XCTest

@MainActor
final class GetReadyUITests: XCTestCase {

    private var app: XCUIApplication!

    // `async throws`: a synchronous `setUp()` override inherits XCTestCase's
    // non-isolated declaration whatever the class is annotated with, so
    // main-actor `XCUIApplication` was reached from a non-isolated context.
    // Only the async form may add the class's isolation.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.seedLaunchArguments()
    }

    func testGetReadyPrecedesEveryWarmupMoveAndIsSkippable() {
        // Taps "I'm ready" — the transition must outlive the element lookup.
        // The flag holds the AUTOMATIC transitions open; the one the offer's
        // own tap opens is the count-in and lasts five seconds whatever the
        // flag says, so this walks onto the second position's first.
        app.seedLaunchArguments("--uitest-long-transition")
        app.launch()
        app.buttons[AX.startWorkout].tap()
        app.buttons[AX.warmupStart].tap()
        let transition = app.staticTexts[AX.getReadyCountdown]
        let move = app.staticTexts[AX.warmupCountdown]
        XCTAssertTrue(transition.waitForExistence(timeout: 5),
                      "the warm-up must open on the transition, never mid-move")
        XCTAssertFalse(move.exists, "the move must not be running underneath it")
        XCTAssertTrue(move.waitForExistence(timeout: 10),
                      "the count-in must hand the first move over on its own")

        app.buttons["Skip this position"].tap()
        XCTAssertTrue(transition.waitForExistence(timeout: 3),
                      "every position gets its own transition")
        // The label VoiceOver reads: kicker and name are one phrase.
        XCTAssertTrue(app.staticTexts["Get ready: Arm circles"].exists,
                      "the transition must name what is coming")

        // "I'm ready" counts you in rather than dropping the move under the
        // thumb: the transition's own screen stays up for the five seconds of
        // GetReady.countInSeconds, then hands over.
        //
        // Single-snapshot checks FIRST and the timed one last, deliberately:
        // every claim here is only true while those five seconds run, and the
        // negative `waitForExistence(timeout: 2)` this walk used to open with
        // spent two of them before the other two checks were even asked. The
        // margin measured on a healthy runner was 2.89 s — the narrowest in
        // the suite — against the 9.5 s this project has seen one XCUITest
        // answer take (nightly 2026-08-04, run 30875292377).
        let tappedAt = Date.now
        app.buttons[AX.getReadyStart].tap()
        XCTAssertTrue(transition.exists, "the count-in runs on the transition's own screen")
        XCTAssertFalse(app.buttons[AX.getReadyStart].exists,
                       "the tap is spent — a control that can no longer cut anything must go")
        XCTAssertFalse(move.exists,
                       "“I'm ready” must count in, not start the move under the thumb")
        XCTAssertTrue(move.waitForExistence(timeout: 15),
                      "the count-in must hand over to the move")
        // The claim, measured rather than raced: the move began LATER than the
        // tap. A lower bound cannot be broken by a slow runner — only by an
        // app that dropped the move under the thumb.
        XCTAssertGreaterThan(Date.now.timeIntervalSince(tappedAt), 3,
                             "the move started too soon after the tap for a count-in to have run")
        XCTAssertFalse(transition.exists, "the transition is over once the move runs")
    }

    /// Runs itself down and hands over without a tap — hence no flag.
    func testGetReadyHandsOverToTheMoveOnItsOwn() {
        app.launch()
        app.buttons[AX.startWorkout].tap()
        app.buttons[AX.warmupStart].tap()
        XCTAssertTrue(app.staticTexts[AX.getReadyCountdown].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[AX.warmupCountdown].waitForExistence(timeout: 12),
                      "the transition must start the move by itself")
        XCTAssertTrue(app.staticTexts["Marching in place"].exists,
                      "the move that runs must be the one the transition announced")
    }

    func testTheBlockCanStillBeSkippedFromTheTransition() {
        // The escape has to be tapped while the transition is still up, so
        // this walks onto an automatic one: the block's first transition is
        // the offer's own count-in and lasts five seconds whatever the flag
        // says.
        app.seedLaunchArguments("--uitest-long-transition")
        app.launch()
        app.buttons[AX.startWorkout].tap()
        app.buttons[AX.warmupStart].tap()
        XCTAssertTrue(app.staticTexts[AX.warmupCountdown].waitForExistence(timeout: 10),
                      "the count-in must hand the first move over on its own")
        app.buttons["Skip this position"].tap()
        XCTAssertTrue(app.buttons[AX.getReadyStart].waitForExistence(timeout: 5))
        app.buttons[AX.skipWarmup].tap()
        XCTAssertTrue(app.buttons[AX.exerciseDone].waitForExistence(timeout: 3),
                      "skipping the warm-up from its transition must reach exercise 1")
    }
}
