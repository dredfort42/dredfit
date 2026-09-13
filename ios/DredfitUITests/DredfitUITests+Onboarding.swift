//
//  The onboarding walk, moved out of DredfitUITests.swift to keep it under
//  the linter's file and type-body ceilings. Kept apart because both tests
//  care about first-run behaviour specifically: what a fresh install opens
//  on, and that a skip still routes through the one screen it cannot skip
//  past. The code moved unchanged.
//

import XCTest

// MARK: - Onboarding
extension DredfitUITests {

    func testOnboardingAppearsOnFirstRunAndFinishes() {
        seed("--uitest-onboarding")
        app.launch()
        XCTAssertTrue(app.staticTexts["Training at home. No questionnaires."]
                        .waitForExistence(timeout: 5),
                      "a first run must open on the onboarding")

        let primary = app.buttons[AX.onboardingPrimary]
        primary.tap()
        XCTAssertTrue(app.staticTexts["It adjusts like a thermostat."]
                        .waitForExistence(timeout: 3), "card 2 is missing")
        primary.tap()
        XCTAssertTrue(app.staticTexts["One tap after the workout."]
                        .waitForExistence(timeout: 3), "card 3 is missing")

        primary.tap()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 3),
                      "finishing the onboarding must reveal Today")
        XCTAssertFalse(app.staticTexts["Training at home. No questionnaires."].exists,
                       "the onboarding must be gone")
    }

    /// Skip jumps TO the care card, never past it (#101): the checklist is
    /// the one screen that cannot be skipped, and only its explicit button
    /// completes the onboarding.
    func testOnboardingSkipLandsOnTheCareCardAndIsRemembered() {
        seed("--uitest-onboarding")
        app.launch()
        XCTAssertTrue(app.buttons[AX.onboardingSkip].waitForExistence(timeout: 5))
        app.buttons[AX.onboardingSkip].tap()
        XCTAssertTrue(app.staticTexts["One tap after the workout."]
                        .waitForExistence(timeout: 3),
                      "skipping must land on the care card, not on Today")
        // Today's elements stay .exists behind the cover: the card text going
        // away is what proves completion.
        app.buttons[AX.onboardingPrimary].tap()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["One tap after the workout."].exists,
                       "the explicit acknowledgement completes the onboarding")

        let relaunch = XCUIApplication.launchedOnStoredState()
        XCTAssertTrue(relaunch.buttons[AX.startWorkout].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunch.staticTexts["Training at home. No questionnaires."].exists,
                       "an acknowledged onboarding must not come back")
    }
}
