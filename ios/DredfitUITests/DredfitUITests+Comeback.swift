//
//  The comeback-card walks after a break, moved out of DredfitUITests.swift
//  to keep it under the linter's file and type-body ceilings. Kept together
//  because all four share the `launchOnTheComebackCard` arrange and pin the
//  same offer from different angles: accepted, declined, and — past the
//  long-break threshold — replaced by "start from scratch". The code moved
//  unchanged.
//

import XCTest

// MARK: - Comeback after a break
extension DredfitUITests {

    /// The seeded break and the card it earns — the opening of four tests.
    private func launchOnTheComebackCard(_ seed: String = "--uitest-comeback",
                                         days: Int = 20) {
        app.seedLaunchArguments(seed)
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5),
                      "a \(days)-day break should offer the comeback card")
    }

    func testComebackCardStartsEasier() {
        launchOnTheComebackCard()
        // The seed stands on variation 3 at the top of its grid, so the plan
        // is 2 × 15 with the third set a probe (§40.4); 20 days lands on 3×13.
        XCTAssertTrue(app.staticTexts["2 × 15"].exists, "plan before the comeback")

        app.buttons[AX.comebackAccept].tap()
        XCTAssertTrue(app.staticTexts["3 × 13"].waitForExistence(timeout: 3),
                      "accepting must lower the plan two steps")
        XCTAssertFalse(app.staticTexts["Welcome back"].exists,
                       "the card is answered and gone")
    }

    func testComebackCardCanBeDeclinedForGood() {
        launchOnTheComebackCard()
        app.buttons[AX.comebackDecline].tap()
        XCTAssertFalse(app.staticTexts["Welcome back"].exists)
        XCTAssertTrue(app.staticTexts["2 × 15"].exists, "the plan is unchanged")

        let relaunch = XCUIApplication.launchedOnStoredState()
        XCTAssertTrue(relaunch.buttons[AX.startWorkout].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunch.staticTexts["Welcome back"].exists,
                       "an answered break does not ask again")
    }

    /// The only walk that reaches "Start from scratch": after a break long
    /// enough that the steps describe nobody, the card offers a way out of
    /// them, spells out what it costs, and keeps the history either way.
    func testFreshStartIsOfferedAfterAVeryLongBreak() {
        launchOnTheComebackCard("--uitest-comeback-long", days: 95)
        // By the labels inside it, not by the container's identifier: that
        // sits on a VStack, which XCUITest does not surface as a static text.
        XCTAssertTrue(app.staticTexts["Easier:"].waitForExistence(timeout: 3),
                      "the card answers in numbers, not adjectives")
        XCTAssertTrue(app.staticTexts["As it was:"].exists,
                      "both offers are named, so the choice is a comparison")

        let fresh = app.buttons[AX.comebackFresh]
        XCTAssertTrue(fresh.waitForExistence(timeout: 3),
                      "a break this long is exactly when starting over is on offer")
        fresh.tap()

        // A confirmation, because it is the one irreversible thing here.
        // Taken rather than cancelled: the reset is what the offer is FOR.
        XCTAssertTrue(app.staticTexts["Start from scratch?"].waitForExistence(timeout: 3),
                      "the offer must confirm before it resets anything")
        let reset = app.buttons["Reset progress"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3),
                      "the confirmation must carry the destructive choice")
        reset.tap()

        XCTAssertTrue(app.staticTexts["3 × 4"].waitForExistence(timeout: 5),
                      "the plan goes back to the beginning — the floor is three fours")
        XCTAssertFalse(app.staticTexts["Welcome back"].exists,
                       "the card is answered and gone")

        // "…Your history stays" — the half a careless reset would break.
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["1 workout"].waitForExistence(timeout: 5),
                      "the workout that was done before the break is still there")
    }

    func testFreshStartIsNotOfferedForAShortBreak() {
        launchOnTheComebackCard()
        XCTAssertFalse(app.buttons[AX.comebackFresh].exists,
                       "starting from scratch is for half-year breaks, not three weeks")
    }
}
