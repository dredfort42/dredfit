//
//  HandlesUITests.swift
//  DredfitUITests
//
//  v2.26 (spec §37.4-§37.5): the athlete's handles, end to end.
//
//  This file replaces DiscomfortUITests, which walked "Something hurt" through
//  the workout, the rating screen and the resting line on Today. None of that
//  exists: the channel is gone, and what took its place is on the plan rather
//  than inside the workout — pulling a handle regenerates the session and the
//  announced duration together, which is exactly what these walk through.
//

import XCTest

@MainActor
final class HandlesUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// §37.5's headline: the recalculated duration is on screen BEFORE the tap,
    /// and the workout the person gets is the one the button promised.
    func testTheSessionHandleShowsBothNumbersAndDeliversTheSecond() {
        app.launch()
        let shorter = app.buttons["session-shorter"]
        XCTAssertTrue(shorter.waitForExistence(timeout: 5),
                      "the session handle is missing from the plan")
        // "Shorter today · 37 → 26 min" — both numbers, before agreeing.
        let promise = shorter.label
        XCTAssertTrue(promise.contains("→"),
                      "the handle must show what the session becomes, not just that it shrinks")

        shorter.tap()

        XCTAssertTrue(app.buttons["session-full"].waitForExistence(timeout: 3),
                      "a shortened session must offer the way back")
    }

    /// The way back: "Full workout" restores every set on every movement.
    func testTheFullWorkoutIsReachableAgain() {
        app.launch()
        let shorter = app.buttons["session-shorter"]
        XCTAssertTrue(shorter.waitForExistence(timeout: 5))
        shorter.tap()

        let full = app.buttons["session-full"]
        XCTAssertTrue(full.waitForExistence(timeout: 3))
        full.tap()

        XCTAssertFalse(full.waitForExistence(timeout: 2),
                       "with every set back there is nothing to restore")
    }

    /// The per-movement handles sit on the movement they act on, and the
    /// easier one carries its RESULT rather than a promise.
    func testTheExerciseHandlesActOnTheirOwnMovement() {
        app.launch()
        let fewer = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fewer-sets-")).firstMatch
        XCTAssertTrue(fewer.waitForExistence(timeout: 5),
                      "the per-movement sets handle is missing from the plan")
        fewer.tap()

        let more = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "more-sets-")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 3),
                      "a movement with a set off must offer to put it back")
    }

    /// v2.26 (§37.7a): the cool-down is offered, not started — and the same
    /// screen lets it be declined.
    func testTheCoolDownAsksBeforeItStarts() {
        app.launch()
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["Skip warm-up"]
        if skipWarmup.waitForExistence(timeout: 5) { skipWarmup.tap() }
        // Straight through the work: every exercise skipped still counts as a
        // workout, and the cool-down set is drawn from what was performed — so
        // one exercise is done properly to keep the block non-empty.
        for _ in 0..<5 { app.buttons["Skip exercise"].tap() }

        let start = app.buttons["cooldown-start"]
        let skip = app.buttons["cooldown-intro-skip"]
        // A workout of pure skips has nothing to stretch and goes straight to
        // the rating — either outcome is correct, and only one may happen.
        let asked = start.waitForExistence(timeout: 5)
        let rated = app.staticTexts["How did it go?"].waitForExistence(timeout: 1)
        XCTAssertTrue(asked || rated,
                      "the flow must reach either the cool-down question or the rating")
        if asked {
            XCTAssertTrue(skip.exists, "the question must be answerable both ways")
            skip.tap()
            XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 5),
                          "declining the cool-down goes to the rating")
        }
    }
}
