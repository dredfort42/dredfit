//
//  GetReadyUITests.swift
//  DredfitUITests
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

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func testGetReadyPrecedesEveryWarmupMoveAndIsSkippable() {
        // Taps "I'm ready" — the transition must outlive the element lookup.
        app.launchArguments.append("--uitest-long-transition")
        app.launch()
        app.buttons["Start"].tap()
        let transition = app.staticTexts["getready-countdown"]
        let move = app.staticTexts["warmup-countdown"]
        XCTAssertTrue(transition.waitForExistence(timeout: 5),
                      "the warm-up must open on the transition, never mid-move")
        XCTAssertFalse(move.exists, "the move must not be running underneath it")

        app.buttons["get-ready-start"].tap()
        XCTAssertTrue(move.waitForExistence(timeout: 3),
                      "“I'm ready” must start the move at once")
        XCTAssertFalse(transition.exists, "the transition is over once the move runs")

        app.buttons["Skip this move"].tap()
        XCTAssertTrue(transition.waitForExistence(timeout: 3),
                      "every position gets its own transition")
        // The label VoiceOver reads: kicker and name are one phrase.
        XCTAssertTrue(app.staticTexts["Get ready: Arm circles"].exists,
                      "the transition must name what is coming")
    }

    /// Runs itself down and hands over without a tap — hence no flag.
    func testGetReadyHandsOverToTheMoveOnItsOwn() {
        app.launch()
        app.buttons["Start"].tap()
        XCTAssertTrue(app.staticTexts["getready-countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["warmup-countdown"].waitForExistence(timeout: 12),
                      "the transition must start the move by itself")
        XCTAssertTrue(app.staticTexts["Marching in place"].exists,
                      "the move that runs must be the one the transition announced")
    }

    func testTheBlockCanStillBeSkippedFromTheTransition() {
        // The escape has to be tapped while the transition is still up.
        app.launchArguments.append("--uitest-long-transition")
        app.launch()
        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["get-ready-start"].waitForExistence(timeout: 5))
        app.buttons["Skip warm-up"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3),
                      "skipping the warm-up from its transition must reach exercise 1")
    }
}
