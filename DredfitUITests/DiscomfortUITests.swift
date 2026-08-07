//
//  DiscomfortUITests.swift
//  DredfitUITests
//
//  "Something hurt" end to end: the report during a workout, what the rating
//  and the history say about it, and the line Today carries while the
//  movement rests (issue #66). The freeze arithmetic itself is unit-tested —
//  three appearances is a slow thing to walk through a UI.
//

import XCTest

@MainActor
final class DiscomfortUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    private func startWorkout() {
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["Skip warm-up"]
        if skipWarmup.waitForExistence(timeout: 3) { skipWarmup.tap() }
    }

    /// Reporting pain ends the exercise like a skip does, but the rating
    /// screen and the history say something else about it.
    func testDiscomfortIsReportedAndMarkedOnTheRating() {
        app.launch()
        startWorkout()
        // Walk to the pull slot: it is in every session, so the rest it earns
        // is visible on the next plan rather than three workouts later.
        for _ in 0..<3 { app.buttons["Skip exercise"].tap() }
        app.buttons["report-discomfort"].tap()
        for _ in 0..<2 { app.buttons["Skip exercise"].tap() }

        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3),
                      "a reported exercise must end like a skip does")
        XCTAssertTrue(app.staticTexts["DISCOMFORT"].exists,
                      "the report is not called out on the rating screen")
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", ", hurt — resting")).count, 1,
            "the painful exercise must announce its state to VoiceOver")

        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        // History keeps the two apart: "hurt", not "skipped".
        app.tabBars.buttons["Calendar"].tap()
        let day = Calendar.current.component(.day, from: .now)
        app.buttons["day-\(day)"].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["hurt"].exists, "the history row is not marked")
        app.buttons["Got it"].tap()
    }

    /// While a movement is frozen, Today says so quietly — by movement name,
    /// as a fact rather than a warning, and with the horizon the engine
    /// already knows.
    func testTodayCarriesTheRestingLine() {
        app.launchArguments.append("--uitest-discomfort")
        app.launch()
        let heading = app.staticTexts["resting-line"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "no freeze block on Today")
        XCTAssertEqual(heading.label, "Not getting harder")
        // Named as the list above names it, not by movement, and carrying the
        // per-movement counter as one VoiceOver phrase.
        XCTAssertTrue(app.staticTexts["Y-T-W raises, not getting harder — 3 more times"].exists,
                      "the row carries neither the name nor the horizon")
    }
}
