//
//  "Went differently" end to end, on the set it is actually tapped on. The
//  arithmetic is unit-tested in SetFactsTests; what only a walk can prove is
//  that the flow hands the CURRENT set index to it — the bug was that it
//  never did, so a number entered on the last set was recorded for all of
//  them and reached the engine as a full shortfall.
//

import XCTest

@MainActor
final class SetFactsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitest-fast: this test completes real sets, so the rests between
        // them have to collapse.
        app.launchArguments = ["--uitest-reset", "--uitest-fast",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// Workout 1 opens at 3×4 reps (§40.8). Two sets on plan, the third at 1:
    /// the rating screen must show the three sets as they were, not one number
    /// standing in for all of them.
    func testAFactOnTheLastSetLeavesTheEarlierSetsOnPlan() {
        app.launch()
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["warmup-intro-skip"]
        if skipWarmup.waitForExistence(timeout: 3) { skipWarmup.tap() }

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the first work screen never came up")
        // Two sets exactly as planned. The rest collapses to a second and
        // advances itself, so the caption is the thing to wait on.
        for set in 2...3 {
            done.tap()
            XCTAssertTrue(app.staticTexts["set \(set) of 3"].waitForExistence(timeout: 8),
                          "the flow did not reach set \(set)")
        }

        app.buttons["Went differently"].tap()
        let minus = app.buttons["minus"]
        XCTAssertTrue(minus.waitForExistence(timeout: 3), "the stepper did not open")
        // Down to the bottom of the corridor, and that is not zeal: on a plan
        // of 4 a last set of 3 averages 3.67, which snaps back ONTO the plan,
        // and `SetFacts.override` then says nothing at all rather than
        // over-penalise a near miss. The exercise would drop off the rating
        // screen entirely and this test would prove nothing.
        minus.tap(); minus.tap(); minus.tap()   // plan 4 → 1
        app.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["actual 1"].waitForExistence(timeout: 3),
                      "the caption must confirm the number on this set")

        WorkoutDriver(app: app).completeWorkout()
        // Matched by accessibility label, which is the comma-separated twin of
        // the "4 · 4 · 1" on screen — the same list, spoken rather than set.
        XCTAssertTrue(app.staticTexts["4, 4, 1"].exists,
                      "the rating screen must show the sets as they ran, not 1 three times")
        XCTAssertFalse(app.staticTexts["actual 1"].exists,
                       "1 was one set of three — it must not stand for the exercise")

        app.staticTexts["On plan"].tap()
        XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5))

        // History says the same thing the rating screen said.
        app.tabBars.buttons["Calendar"].tap()
        let day = Calendar.current.component(.day, from: .now)
        app.buttons["day-\(day)"].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["4, 4, 1"].exists, "the history row lost the sets")
        app.buttons["Got it"].tap()
    }
}
