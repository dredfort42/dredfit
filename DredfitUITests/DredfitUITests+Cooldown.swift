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
        app.launchArguments.append("--uitest-fast")
        app.launch()
        startWorkout()

        let done = app.buttons["Done"]
        let startHold = app.buttons["Start hold"]
        let cooldown = app.staticTexts["COOL-DOWN"]
        let deadline = Date.now.addingTimeInterval(360)
        while !cooldown.exists && Date.now < deadline {
            if done.exists {
                coordinateTap(done)
                _ = done.waitForNonExistence(timeout: 3)
            } else if startHold.exists {
                coordinateTap(startHold)
                _ = startHold.waitForNonExistence(timeout: 3)
            } else {
                _ = cooldown.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(cooldown.waitForExistence(timeout: 5),
                      "the cool-down must follow the last exercise")

        // The header is up as soon as the block is OFFERED — the block itself
        // runs only once the offer is accepted.
        let acceptCooldown = app.buttons["cooldown-start"]
        if acceptCooldown.waitForExistence(timeout: 5) { acceptCooldown.tap() }

        // The position mini-sheet (issue #34) opens over the running block
        // and closes back into it — opening freezes the countdown, so the
        // sequence is stable even on --uitest-fast's 1 s stages.
        coordinateTap(app.buttons["technique"])
        let gotIt = app.buttons["Got it"]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 3), "the cool-down mini-sheet did not open")
        gotIt.tap()
        XCTAssertTrue(gotIt.waitForNonExistence(timeout: 3), "the mini-sheet did not close")

        app.buttons["skip-cooldown"].tap()
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3),
                      "skipping the cool-down lands on the rating")
        app.staticTexts["On plan"].tap()
        XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5),
                      "the workout is recorded exactly as before")
    }
}
