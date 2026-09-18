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
    private var driver: WorkoutDriver { WorkoutDriver(app: app) }

    // `async throws`: a synchronous `setUp()` override inherits XCTestCase's
    // non-isolated declaration whatever the class is annotated with, so
    // main-actor `XCUIApplication` was reached from a non-isolated context.
    // Only the async form may add the class's isolation.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitest-fast: this test completes real sets, so the rests between
        // them have to collapse.
        app.seedLaunchArguments("--uitest-fast")
    }

    /// Workout 1 opens at 3×4 reps (§40.8). Two sets on plan, the third at 1:
    /// the rating screen must show the three sets as they were, not one number
    /// standing in for all of them.
    func testAFactOnTheLastSetLeavesTheEarlierSetsOnPlan() {
        app.launch()
        driver.startWorkout()
        let done = app.buttons[AX.exerciseDone]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the first work screen never came up")
        // Two sets exactly as planned. The rest collapses to a second and
        // advances itself, so the caption is the thing to wait on.
        for set in 2...3 {
            done.tap()
            XCTAssertTrue(app.staticTexts["set \(set) of 3"].waitForExistence(timeout: 8),
                          "the flow did not reach set \(set)")
        }

        app.buttons[AX.exerciseAdjust].tap()
        let minus = app.buttons[AX.adjustMinus]
        XCTAssertTrue(minus.waitForExistence(timeout: 3), "the stepper did not open")
        // Down to the bottom of the corridor, and that is not zeal: on a plan
        // of 4 a last set of 3 averages 3.67, which snaps back ONTO the plan,
        // and `SetFacts.override` then says nothing at all rather than
        // over-penalise a near miss. The exercise would drop off the rating
        // screen entirely and this test would prove nothing.
        minus.tap(); minus.tap(); minus.tap()   // plan 4 → 1
        app.buttons[AX.adjustConfirm].tap()
        XCTAssertTrue(app.staticTexts["actual 1"].waitForExistence(timeout: 3),
                      "the caption must confirm the number on this set")

        driver.completeWorkout()
        // Matched by accessibility label, which is the comma-separated twin of
        // the "actual 4 · 4 · 1" on screen — the same list, spoken rather than
        // set, and carrying its word: bare numbers under a plan read as
        // anything (§41.13).
        XCTAssertTrue(app.staticTexts["actual 4, 4, 1"].exists,
                      "the rating screen must show the sets as they ran, not 1 three times")
        XCTAssertFalse(app.staticTexts["actual 1"].exists,
                       "1 was one set of three — it must not stand for the exercise")

        app.element(withIdentifier: AX.ratingPlan).tap()
        XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5))

        // History says the same thing the rating screen said.
        app.tabBars.buttons["Calendar"].tap()
        let day = Calendar.current.component(.day, from: .now)
        app.buttons[AX.day(day)].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3))
        // In the plan's own spelling, and named — the row's three lines are
        // "plan", "Actual:" and "After:", each with its word.
        XCTAssertTrue(app.staticTexts["Actual: 4-4-1"].exists, "the history row lost the sets")
        app.buttons[AX.historyDone].tap()
    }

    /// The stepper's target is its whole frame, corners included. A Button
    /// takes taps only where its label draws, and the label drew a ring: the
    /// four corners of the 44 pt frame and everything past the ring took no
    /// tap, so a thumb that landed at the ring's edge missed, and missed the
    /// same way on every repeat — "the − sticks" (owner, 13.09.2026, build
    /// 22). The frame is now 62 × 68 pt of hit shape over the same ring, and
    /// this taps each of its four corners once (`WorkoutDriver.corners`) —
    /// 40 pt from the centre, twice the ring's radius — where the ring alone
    /// would have taken nothing.
    ///
    /// Plan 4 to 0, one corner per step, and the caption has to read the
    /// number that only four hits produce: the rep corridor starts at 0
    /// (`SetFacts.corridor`), a miss on every corner leaves the plan standing
    /// and so no caption at all, and two hits read "actual 2". "actual 0"
    /// cannot be reached any other way.
    func testTheStepperTakesATapAtTheCornerOfItsFrame() {
        app.launch()
        driver.startWorkout()
        XCTAssertTrue(app.buttons[AX.exerciseDone].waitForExistence(timeout: 5),
                      "the first work screen never came up")
        app.buttons[AX.exerciseAdjust].tap()
        let minus = app.buttons[AX.adjustMinus]
        XCTAssertTrue(minus.waitForExistence(timeout: 3), "the stepper did not open")
        for corner in WorkoutDriver.corners {
            minus.coordinate(withNormalizedOffset: corner).tap()
        }
        app.buttons[AX.adjustConfirm].tap()
        XCTAssertTrue(app.staticTexts["actual 0"].waitForExistence(timeout: 3),
                      "four corner taps must step 4 → 0; a miss leaves the plan and no caption, "
                        + "two misses read “actual 2”")
    }
}
