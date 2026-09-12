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

    // `async throws`: a synchronous `setUp()` override inherits XCTestCase's
    // non-isolated declaration whatever the class is annotated with, so
    // touching main-actor `XCUIApplication` from it warned four times per
    // file. Only the async form may add the class's isolation.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.seedLaunchArguments()
    }

    func testAPausedMoveStandsStillAndComesBackWhereItStopped() {
        app.launch()
        app.buttons[AX.startWorkout].tap()
        app.buttons[AX.warmupStart].tap()
        let move = app.staticTexts[AX.warmupCountdown]
        XCTAssertTrue(move.waitForExistence(timeout: 15),
                      "the transition must hand over to the first move")

        app.buttons[AX.blockPause].tap()
        let resume = app.buttons[AX.blockResume]
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
        let reentry = app.staticTexts[AX.reentryCountdown]
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
        app.seedLaunchArguments("--uitest-long-transition")
        app.launch()
        app.buttons[AX.startWorkout].tap()
        app.buttons[AX.warmupStart].tap()
        XCTAssertTrue(app.staticTexts[AX.getReadyCountdown].waitForExistence(timeout: 5),
                      "the warm-up must open on the transition")
        // …but that one is the offer's count-in, five seconds whatever the
        // flag says. Onto the next position's, which the flag does hold open.
        XCTAssertTrue(app.staticTexts[AX.warmupCountdown].waitForExistence(timeout: 10),
                      "the count-in must hand the first move over on its own")
        app.buttons["Skip this position"].tap()
        XCTAssertTrue(app.buttons[AX.getReadyStart].waitForExistence(timeout: 5),
                      "skipping a move lands on the next position's transition")

        app.buttons[AX.blockPause].tap()
        XCTAssertTrue(app.buttons[AX.blockResume].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons[AX.getReadyStart].exists,
                       "“I'm ready” must not start a position the user has stopped")

        app.buttons[AX.blockResume].tap()
        XCTAssertTrue(app.buttons[AX.getReadyStart].waitForExistence(timeout: 3),
                      "resuming gives the transition back")
        XCTAssertFalse(app.staticTexts[AX.reentryCountdown].exists,
                       "a transition needs no way back in — it already is one")
    }

    /// Both blocks, not just the warm-up: the cool-down runs the same
    /// machinery over stretches and the side-switch pause.
    func testACooldownStretchPausesAndResumes() {
        app.seedLaunchArguments("--uitest-fast")
        app.launch()
        driver.startWorkout()

        let pause = app.buttons[AX.blockPause]
        let resume = app.buttons[AX.blockResume]
        let cooldown = app.staticTexts["COOL-DOWN"]
        // The driver owns this walk. A private copy of it stood here, in
        // HandlesUITests and in DredfitUITests+Cooldown at once — three places
        // to keep in step with one screen, which is the drift the driver's own
        // header warns about and the nightly has already paid for once.
        XCTAssertTrue(driver.walkToCooldownOffer(deadline: 420),
                      "the cool-down must follow the last exercise")
        XCTAssertTrue(cooldown.exists,
                      "the header is up as soon as the block is offered")

        // Offered, not running: the block itself starts only once the offer
        // is accepted.
        app.buttons[AX.cooldownStart].tap()

        // Every screen of the block carries the control, so a tap that lands
        // one stage late still lands on a pause — retried until one takes,
        // because --uitest-fast gives each stage a single second. The loop
        // hangs on the block's header, not on the control: between two stages
        // an accessibility snapshot can catch the moment the old screen's
        // button is gone and the new one's has not arrived (I-5's class of
        // flake), and a condition reading `pause.exists` would give up there.
        let deadline = Date.now.addingTimeInterval(30)
        while !resume.exists && cooldown.exists && Date.now < deadline {
            if pause.exists { driver.coordinateTap(pause) }
            _ = resume.waitForExistence(timeout: 1)
        }
        // Which way the loop ended, said out loud. Under --uitest-fast every
        // stage lasts one second and the whole block ~15, while this project
        // has measured a single XCUITest answer at 9.5 s (nightly 2026-08-04):
        // a runner slow enough to outlive the block fails on the pause and
        // reads as a broken pause. It is not one, and the sentence says so.
        XCTAssertTrue(resume.exists,
                      cooldown.exists
                        ? "a cool-down stage must be pausable"
                        : "the cool-down block ended before a pause could be delivered "
                            + "— the runner ran out of stages, not the app out of pauses")
        XCTAssertTrue(app.staticTexts["Paused"].exists,
                      "the cool-down says it is paused in the same words")

        driver.coordinateTap(resume)
        XCTAssertTrue(pause.waitForExistence(timeout: 10),
                      "resuming must put the block back on the clock")
        // 5 s here was below this project's own measured worst case for a
        // single XCUITest answer (9.5 s, nightly 2026-08-04), and it flaked:
        // iteration 2 of 5 on 26.08.2026 reached this line with the pause and
        // the resume both proven and still read no rating. The tap is also
        // retried once — right after a resume the block can be mid-transition,
        // and a tap spent on the outgoing screen leaves the button standing.
        let rating = app.staticTexts["How did it go?"]
        let skip = app.buttons[AX.skipCooldown]
        XCTAssertTrue(skip.waitForExistence(timeout: 10),
                      "the resumed cool-down must still offer a way out of the block")
        skip.tap()
        if !rating.waitForExistence(timeout: 10), skip.exists {
            skip.tap()
        }
        XCTAssertTrue(rating.waitForExistence(timeout: 10),
                      "a paused-and-resumed cool-down still reaches the rating")
    }
}
