//
//  PinnedUITests.swift
//  DredfitUITests
//
//  "Hold this level" end to end (issue #78): the toggle during a workout, the
//  HELD section on the rating, the history mark, and the horizon line Today
//  carries — the same line a pain report earns, because the app cannot tell
//  the two entrances apart. The freeze arithmetic itself is unit-tested;
//  three appearances is a slow thing to walk through a UI.
//

import XCTest

@MainActor
final class PinnedUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitest-fast: unlike a skip walk, this test completes real sets,
        // so the rests between them have to collapse.
        app.launchArguments = ["--uitest-reset", "--uitest-fast",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    private func startWorkout() {
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["Skip warm-up"]
        if skipWarmup.waitForExistence(timeout: 3) { skipWarmup.tap() }
    }

    /// The pin confirms itself in place — caption and pill — is undoable with
    /// a second tap, and the pinned exercise is still performed: it reaches
    /// the rating under HELD, not under SKIPPED, and history says "held".
    func testAPinIsToggledCompletedAndMarked() {
        app.launch()
        startWorkout()

        let pin = app.buttons["hold-level"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "the hold action is missing")
        pin.tap()
        XCTAssertTrue(app.staticTexts["level held"].waitForExistence(timeout: 3),
                      "the caption must confirm the request")
        XCTAssertTrue(app.buttons["Holding"].exists, "the action must flip to its pill")

        // The undo: a second tap clears both confirmations.
        app.buttons["Holding"].tap()
        XCTAssertTrue(app.staticTexts["level held"].waitForNonExistence(timeout: 3),
                      "a second tap must cancel the request")
        XCTAssertTrue(app.buttons["Hold this level"].exists,
                      "the action must read as available again")

        // Pin again and finish the workout for real — a held movement is
        // performed, not set aside, and the driver proves the four-action
        // row does not confuse the one sanctioned walk to the rating.
        pin.tap()
        WorkoutDriver(app: app).completeWorkout()
        XCTAssertTrue(app.staticTexts["HELD"].exists,
                      "the request is not called out on the rating screen")
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", ", level held — 3 more times")).count, 1,
            "the held exercise must announce its state and horizon to VoiceOver")
        XCTAssertTrue(app.staticTexts["Your rating can move these down, but not up."].exists,
                      "the section must say what the state means")

        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        // History keeps all three marks apart: "held", not "skipped" or "hurt".
        app.tabBars.buttons["Calendar"].tap()
        let day = Calendar.current.component(.day, from: .now)
        app.buttons["day-\(day)"].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["held"].exists, "the history row is not marked")
        app.buttons["Got it"].tap()
    }

    /// The same quiet line a pain report earns — Today cannot and must not
    /// tell the two entrances apart.
    func testTodayCarriesTheHorizonLine() {
        app.launchArguments.append("--uitest-pinned")
        app.launch()
        let heading = app.staticTexts["resting-line"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "no freeze block on Today")
        XCTAssertEqual(heading.label, "Not getting harder")
        // Named as the list above names it, with the per-movement counter as
        // one VoiceOver phrase.
        XCTAssertTrue(app.staticTexts["Y-T-W raises, not getting harder — 3 more times"].exists,
                      "the row carries neither the name nor the horizon")
    }
}
