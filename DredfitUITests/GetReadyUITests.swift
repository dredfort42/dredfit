//
//  GetReadyUITests.swift
//  DredfitUITests
//
//  The "Get ready" transition (issue #52): every position of a guided block
//  is preceded by it — the very first one included, because the user has just
//  pressed Start and is still standing by the phone.
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

    /// The block opens on the transition, and anyone already in place taps
    /// straight through it.
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

        // ...and the next position is announced the same way.
        app.buttons["Skip this move"].tap()
        XCTAssertTrue(transition.waitForExistence(timeout: 3),
                      "every position gets its own transition")
        // The label is the one VoiceOver reads: the kicker and the name are
        // one phrase, not two swipes.
        XCTAssertTrue(app.staticTexts["Get ready: Arm circles"].exists,
                      "the transition must name what is coming")
    }

    /// It runs itself down and hands over without a tap: five seconds, wall
    /// clock, exactly like every other countdown in the app.
    func testGetReadyHandsOverToTheMoveOnItsOwn() {
        app.launch()
        app.buttons["Start"].tap()
        XCTAssertTrue(app.staticTexts["getready-countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["warmup-countdown"].waitForExistence(timeout: 12),
                      "the transition must start the move by itself")
        XCTAssertTrue(app.staticTexts["Marching in place"].exists,
                      "the move that runs must be the one the transition announced")
    }

    /// Skipping the whole block from the transition is the same escape it
    /// always was — the transition never traps anyone in front of it.
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
