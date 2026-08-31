//
//  Resuming a workout after the app was killed mid-flight, moved out of
//  DredfitUITests.swift to keep it under the linter's file and type-body
//  ceilings. Grouped here because each pins where a relaunch must land — back
//  inside the workout, on the rating, on plain Start when there is nothing to
//  resume — using the shared `relaunchOnAnInterruptedWorkout()` arrange that
//  stays in the base file. The two persistence-after-a-completed-workout
//  tests at the bottom joined them for the same reason: both ask what a cold
//  relaunch shows, just without an interruption to resume from. The code
//  moved unchanged.
//

import XCTest

// MARK: - Resuming an interrupted workout
extension DredfitUITests {

    func testInterruptedWorkoutCanBeResumedAfterRelaunch() {
        let relaunch = relaunchOnAnInterruptedWorkout()
        relaunch.buttons[AX.resumeContinue].tap()
        // The snapshot was taken entering rest — the flow resumes inside it.
        XCTAssertTrue(relaunch.buttons[AX.skipRest].waitForExistence(timeout: 5),
                      "continuing must land back inside the workout")
    }

    func testResumeLandsOnRatingWhenKilledThere() {
        app.launch()
        startWorkout()
        // Each escape asks before it acts (SkipConfirmation.swift).
        for _ in 0..<6 { driver.skip(control: AX.exerciseSkip) }
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3))
        app.terminate()

        let relaunch = XCUIApplication.launchedOnStoredState()
        XCTAssertTrue(relaunch.staticTexts["Continue the workout?"]
                        .waitForExistence(timeout: 5))
        XCTAssertTrue(relaunch.staticTexts["The workout is done — only the rating is left."]
                        .exists, "the card must say the truth: only the rating is left")

        relaunch.buttons[AX.resumeContinue].tap()
        XCTAssertTrue(relaunch.staticTexts["How did it go?"].waitForExistence(timeout: 5),
                      "continuing must reopen the rating, not a set already done")
        relaunch.element(withIdentifier: AX.ratingPlan).tap()
        XCTAssertTrue(relaunch.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5),
                      "the resumed rating must record the workout")
    }

    func testNoResumeCardWithoutProgress() {
        app.launch()
        startWorkout()
        XCTAssertTrue(app.buttons[AX.exerciseDone].waitForExistence(timeout: 3))
        app.terminate()

        let relaunch = XCUIApplication.launchedOnStoredState()
        XCTAssertTrue(relaunch.buttons[AX.startWorkout].waitForExistence(timeout: 5),
                      "an empty interruption must fall back to the plain Start")
        XCTAssertFalse(relaunch.staticTexts["Continue the workout?"].exists,
                       "there is nothing to continue — the card must not show")
    }

    func testResumeCardCanStartOver() {
        let relaunch = relaunchOnAnInterruptedWorkout()
        relaunch.buttons[AX.resumeRestart].tap()
        XCTAssertTrue(relaunch.buttons[AX.warmupStart].waitForExistence(timeout: 5),
                      "starting over must open a fresh session at the warm-up offer")
    }

    func testSkipAllExercisesStillReachesRating() {
        app.launch()
        startWorkout()
        // Each escape asks before it acts (SkipConfirmation.swift).
        for _ in 0..<6 { driver.skip(control: AX.exerciseSkip) }
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3),
                      "skipping all exercises should lead to the rating")
        // The state lives once in the section header; each row's dimmed name
        // still announces it through its accessibility label.
        XCTAssertTrue(app.staticTexts["SKIPPED"].exists,
                      "skipped exercises are not listed on the rating screen")
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", ", skipped")).count, 6,
            "all six skipped exercises must be listed")

        // Nothing was trained, so "easy" is not on offer at all — the purest
        // case of the gate. The claim this walk used to make by tapping it is
        // pinned in AppStoreTests now, where the card cannot get in the way.
        XCTAssertTrue(app.staticTexts["“Easy, could do more” is for a workout done in full."].exists,
                      "a session where nothing was done still offers “easy”")

        // A rating must not level up untrained patterns — on the identified
        // element, because a bare "0" can match a chart axis label.
        rate()
        app.tabBars.buttons["Progress"].tap()
        let totalLevel = app.staticTexts[AX.totalSteps]
        XCTAssertTrue(totalLevel.waitForExistence(timeout: 3))
        XCTAssertEqual(totalLevel.label, "0",
                       "skipped exercises must not raise the level (honest skips)")
    }

    // MARK: - Persistence across a relaunch
    //
    // Not an interruption to resume from — these two ask what a plain cold
    // start shows once a workout is already behind it, using the same
    // `launchedOnStoredState()` relaunch the tests above use.

    func testColdStartOpensTodayEvenWhenDone() {
        walkAWholeWorkout()
        let relaunch = XCUIApplication.launchedOnStoredState()
        XCTAssertTrue(relaunch.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5),
                      "a cold start must open Today in its completed state")

        relaunch.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(relaunch.staticTexts["Completed today ✓"].waitForExistence(timeout: 3),
                      "the calendar keeps its completed-today card")
    }

    func testStateSurvivesRelaunch() {
        walkAWholeWorkout()
        let relaunch = XCUIApplication.launchedOnStoredState()
        relaunch.tabBars.buttons["Today"].tap()
        XCTAssertTrue(relaunch.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5),
                      "state did not survive the relaunch")
    }
}
