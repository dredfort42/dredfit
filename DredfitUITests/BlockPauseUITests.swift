//
//  The pause of the guided blocks (issue #61). The warm-up cases run at the
//  real 30 s of a move on purpose — a countdown collapsed to a second cannot
//  be shown to stand still. Only the cool-down case takes --uitest-fast,
//  because reaching it any other way costs six minutes of holds.
//

import XCTest

@MainActor
final class BlockPauseUITests: XCTestCase {

    private var app: XCUIApplication!
    private var driver: WorkoutDriver { WorkoutDriver(app: app) }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func testAPausedMoveStandsStillAndComesBackWhereItStopped() {
        app.launch()
        app.buttons["Start"].tap()
        app.buttons["warmup-start"].tap()   // v2.26: the block is offered first
        let move = app.staticTexts["warmup-countdown"]
        XCTAssertTrue(move.waitForExistence(timeout: 15),
                      "the transition must hand over to the first move")

        app.buttons["block-pause"].tap()
        let resume = app.buttons["block-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3),
                      "the control must flip to Resume")
        XCTAssertTrue(app.staticTexts["Paused"].exists,
                      "the screen has to say plainly that it is paused")

        let frozen = Int(move.label) ?? -1
        XCTAssertGreaterThan(frozen, 0, "the frozen countdown must still be readable")
        Thread.sleep(forTimeInterval: 4)
        XCTAssertEqual(Int(move.label), frozen,
                       "nothing may move while the block is paused")

        resume.tap()
        let reentry = app.staticTexts["reentry-countdown"]
        XCTAssertTrue(reentry.waitForExistence(timeout: 3),
                      "resuming counts the user back into the position first")
        XCTAssertTrue(reentry.waitForNonExistence(timeout: 15),
                      "the way back in must hand over on its own")
        let resumed = Int(move.label) ?? -1
        XCTAssertGreaterThan(resumed, 0, "the move must be running again")
        XCTAssertLessThanOrEqual(resumed, frozen,
                                 "the move continues from where it stopped, never from the top")
    }

    /// The transition is the one screen that resumes straight into itself.
    func testAPausedTransitionHoldsItsPlaceAndItsPrimaryStepsAside() {
        // Taps controls that live only while the transition runs.
        app.launchArguments.append("--uitest-long-transition")
        app.launch()
        app.buttons["Start"].tap()
        app.buttons["warmup-start"].tap()   // v2.26: the block is offered first
        XCTAssertTrue(app.staticTexts["getready-countdown"].waitForExistence(timeout: 5),
                      "the warm-up must open on the transition")

        app.buttons["block-pause"].tap()
        XCTAssertTrue(app.buttons["block-resume"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["get-ready-start"].exists,
                       "“I'm ready” must not start a position the user has stopped")

        app.buttons["block-resume"].tap()
        XCTAssertTrue(app.buttons["get-ready-start"].waitForExistence(timeout: 3),
                      "resuming gives the transition back")
        XCTAssertFalse(app.staticTexts["reentry-countdown"].exists,
                       "a transition needs no way back in — it already is one")
    }

    /// Both blocks, not just the warm-up: the cool-down runs the same
    /// machinery over stretches and the side-switch pause.
    func testACooldownStretchPausesAndResumes() {
        app.launchArguments.append("--uitest-fast")
        app.launch()
        driver.startWorkout()

        let done = app.buttons["Done"]
        let startHold = app.buttons["Start hold"]
        let pause = app.buttons["block-pause"]
        let resume = app.buttons["block-resume"]
        let cooldown = app.staticTexts["COOL-DOWN"]
        var deadline = Date.now.addingTimeInterval(420)
        while !cooldown.exists && Date.now < deadline {
            if done.exists {
                driver.coordinateTap(done)
                _ = done.waitForNonExistence(timeout: 3)
            } else if startHold.exists {
                driver.coordinateTap(startHold)
                _ = startHold.waitForNonExistence(timeout: 3)
            } else {
                _ = cooldown.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(cooldown.waitForExistence(timeout: 5),
                      "the cool-down must follow the last exercise")

        // v2.26 (§37.7a): the header is up as soon as the block is OFFERED —
        // the block itself runs only once the offer is accepted.
        let acceptCooldown = app.buttons["cooldown-start"]
        if acceptCooldown.waitForExistence(timeout: 5) { acceptCooldown.tap() }

        // Every screen of the block carries the control, so a tap that lands
        // one stage late still lands on a pause — retried until one takes,
        // because --uitest-fast gives each stage a single second. The loop
        // hangs on the block's header, not on the control: between two stages
        // an accessibility snapshot can catch the moment the old screen's
        // button is gone and the new one's has not arrived (I-5's class of
        // flake), and a condition reading `pause.exists` would give up there.
        deadline = Date.now.addingTimeInterval(30)
        while !resume.exists && cooldown.exists && Date.now < deadline {
            if pause.exists { driver.coordinateTap(pause) }
            _ = resume.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(resume.exists, "a cool-down stage must be pausable")
        XCTAssertTrue(app.staticTexts["Paused"].exists,
                      "the cool-down says it is paused in the same words")

        driver.coordinateTap(resume)
        XCTAssertTrue(pause.waitForExistence(timeout: 10),
                      "resuming must put the block back on the clock")
        app.buttons["skip-cooldown"].tap()
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 5),
                      "a paused-and-resumed cool-down still reaches the rating")
    }
}
