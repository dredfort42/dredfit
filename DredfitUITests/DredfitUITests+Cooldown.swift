//
//  The cool-down tests (#28), moved out of DredfitUITests.swift, which had
//  grown to nearly nine hundred lines. It is still over the linter's file
//  ceiling after this, and its CLASS BODY sits at 599 against an error at 600
//  — an extension weighs nothing against that bound, so the room has to come
//  from the class itself. The code moved unchanged.
//

import XCTest

// MARK: - Cool-down (#28)
//
// An extension keeps these out of the test class's own body, which the linter
// bounds separately from file length and wherever the extension sits; XCTest
// discovers test methods in extensions just fine.
//
// The two short-workout rows that stood in DredfitUITests.swift went with the
// feature: the app no longer picks three movements of six for anybody. What
// replaced them is SetSkipUITests, where the person decides mid-session
// instead.
extension DredfitUITests {

    func testCooldownRunsBetweenLastExerciseAndRating() {
        seed("--uitest-fast")
        app.launch()
        startWorkout()

        // The walk to the question is the driver's. It was copied out into
        // this file, HandlesUITests and BlockPauseUITests at the same time —
        // three copies of the loop the driver's own header warns about, and
        // the last drift of it cost the nightly six red runs.
        XCTAssertTrue(driver.walkToCooldownOffer(),
                      "the cool-down must follow the last exercise")
        XCTAssertTrue(app.staticTexts["COOL-DOWN"].exists,
                      "the header is up as soon as the block is offered")

        // Offered, not running: the block itself starts only once the offer
        // is accepted.
        app.buttons[AX.cooldownStart].tap()

        // The position mini-sheet (issue #34) opens over the running block
        // and closes back into it — opening freezes the countdown, so the
        // sequence is stable even on --uitest-fast's 1 s stages. By its OWN
        // identifier: four sheets in this app close on a button reading
        // "Got it", and this one is up over a block that keeps running.
        coordinateTap(app.buttons[AX.technique])
        let gotIt = app.buttons[AX.positionTechniqueDone]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 3), "the cool-down mini-sheet did not open")
        gotIt.tap()
        XCTAssertTrue(gotIt.waitForNonExistence(timeout: 3), "the mini-sheet did not close")

        app.buttons[AX.skipCooldown].tap()
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3),
                      "skipping the cool-down lands on the rating")
        rate()
    }
}
