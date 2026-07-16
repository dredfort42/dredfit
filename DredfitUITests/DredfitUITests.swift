//
//  DredfitUITests.swift
//  UI tests of the full feature set. Run on the English locale
//  with clean state (--uitest-reset), except the persistence test.
//

import XCTest

@MainActor
final class DredfitUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    // MARK: - Helpers

    /// Runs the whole workout: Done on every set, Skip rest on every rest.
    /// Returns control on the "How did it go?" screen.
    private func completeWorkout(adjustFirstExercise: Bool = false) {
        app.buttons["Start"].tap()

        if adjustFirstExercise {
            app.buttons["Went differently"].tap()
            let minus = app.buttons["minus"]
            XCTAssertTrue(minus.waitForExistence(timeout: 2), "the stepper did not open")
            minus.tap(); minus.tap(); minus.tap()   // plan 8 → 5
            app.buttons["OK"].tap()
            XCTAssertTrue(app.staticTexts["actual 5"].exists, "the actual marker did not appear")
        }

        let done = app.buttons["Done"]
        let skipRest = app.buttons["Skip rest"]
        let rating = app.staticTexts["How did it go?"]
        // 6 exercises × 3 sets = 18 Done; between them — Skip rest
        var guardCounter = 0
        while !rating.exists && guardCounter < 80 {
            if done.waitForExistence(timeout: 3) && done.isHittable {
                done.tap()
            } else if skipRest.exists && skipRest.isHittable {
                skipRest.tap()
            }
            guardCounter += 1
        }
        XCTAssertTrue(rating.waitForExistence(timeout: 5), "did not reach the rating screen")
    }

    // MARK: - Full pass

    func testFullWorkoutFlowWithAdjustment() {
        app.launch()

        // starting screen: the plan and the button
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 5))
        let start = app.buttons["Start"]
        XCTAssertTrue(start.isHittable, "the Start button is unavailable (covered by the tab bar?)")

        completeWorkout(adjustFirstExercise: true)

        // the rating screen shows the summary of adjustments
        XCTAssertTrue(app.staticTexts["ADJUSTED"].exists, "no actuals summary on the rating screen")
        XCTAssertTrue(app.staticTexts["actual 5"].exists)

        app.staticTexts["Easy, could do more"].tap()

        // done state: no Start button, with the next-workout card
        XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start"].exists, "Start must not show after completion")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Workout 2 ·'")).firstMatch.exists,
            "no next-workout card")
    }

    func testNextWorkoutPreviewHasNoStartButton() {
        app.launch()
        completeWorkout()
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        // next-workout preview
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Workout 2 ·'"))
            .firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Start"].exists, "the preview must not have Start")
        app.buttons["Got it"].tap()
    }

    // MARK: - Technique

    func testTechniqueSheetFromTodayList() {
        app.launch()
        _ = app.staticTexts["Workout 1"].waitForExistence(timeout: 5)
        // tap the first row of the exercise list
        app.buttons.matching(NSPredicate(format: "label CONTAINS '3 ×'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["COMMON MISTAKES"].exists)
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3))
    }

    func testTechniqueSheetDuringWorkout() {
        app.launch()
        app.buttons["Start"].tap()
        app.buttons["technique"].tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3))
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
    }

    // MARK: - Exit and data integrity

    func testExitDiscardsWorkout() {
        app.launch()
        app.buttons["Start"].tap()
        app.buttons["Done"].tap()          // one set
        app.buttons["Exit"].firstMatch.tap()
        // the workout is not recorded — Start is back in place
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3),
                      "after Exit the workout must not count as completed")
    }

    func testSkipAllExercisesStillReachesRating() {
        app.launch()
        app.buttons["Start"].tap()
        for _ in 0..<6 { app.buttons["Skip exercise"].tap() }
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3),
                      "skipping all exercises should lead to the rating")
    }

    // MARK: - Calendar and history

    func testCalendarShowsHistoryAfterWorkout() {
        app.launch()
        completeWorkout(adjustFirstExercise: true)
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["Completed today ✓"].waitForExistence(timeout: 3))

        // tapping today's (filled) day opens the history
        let day = Calendar.current.component(.day, from: .now)
        app.buttons.matching(NSPredicate(format: "label == '\(day)'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3),
                      "history did not open on the day tap")
        XCTAssertTrue(app.staticTexts["actual 5"].exists, "the actual is not shown in the history")
        app.buttons["Got it"].tap()
    }

    func testCalendarColdStartWhenDoneToday() {
        app.launch()
        completeWorkout()
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        // relaunch WITHOUT a reset — the app should open on the calendar
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        relaunch.terminate()
        relaunch.launch()
        XCTAssertTrue(relaunch.staticTexts["Completed today ✓"].waitForExistence(timeout: 5),
                      "a cold start with a completed workout should open the calendar")
    }

    // MARK: - Progress

    func testProgressReflectsCompletedWorkout() {
        app.launch()
        completeWorkout()
        app.staticTexts["Easy, could do more"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["total level"].waitForExistence(timeout: 3))
        // 6 patterns × (+2) = 12
        XCTAssertTrue(app.staticTexts["12"].exists, "the total level after \"easy\" should be 12")
        XCTAssertTrue(app.staticTexts["1 workouts"].exists)
    }

    // MARK: - Persistence across relaunch

    func testStateSurvivesRelaunch() {
        app.launch()
        completeWorkout()
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        relaunch.terminate()
        relaunch.launch()
        relaunch.tabBars.buttons["Today"].tap()
        XCTAssertTrue(relaunch.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5),
                      "state did not survive the relaunch")
    }
}
