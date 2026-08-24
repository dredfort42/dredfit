//
//  The one way the UI tests drive a workout to the rating screen. Two copies
//  of this walk would drift, and the last time it drifted it cost the nightly
//  six red runs (I-5).
//
//  Load-independent BY DESIGN — keep it that way: only stable controls are
//  tapped (Done and Start hold leave the screen only once acted on), each tap
//  is confirmed by waiting for its control to disappear, and a dropped tap is
//  retried on the next pass. Auto-vanishing controls are never tapped.
//

import XCTest

@MainActor
struct WorkoutDriver {

    let app: XCUIApplication

    /// Bypasses hittability resolution: inside the workout's fullScreenCover
    /// the CI simulator reports degenerate ancestor frames, so `.tap()`,
    /// `.isHittable` and predicate waits fail with "activation point invalid"
    /// even though the control is on screen. The leaf frame is valid.
    ///
    /// Returns false rather than tapping an element that is already gone. The
    /// flow stacks its one primary control in the same bottom slot on every
    /// screen, so a tap aimed at a vanished control hits the NEXT screen's
    /// control and quietly consumes it. Callers loop on a goal, so a skipped
    /// tap is retried; a consumed one would not be recoverable.
    ///
    /// This narrows the window rather than closing it: XCUITest delivers the
    /// tap some time after the check, and on a degraded runner that gap has
    /// been ten seconds (nightly 2026-08-04, run 30875292377). A test whose
    /// target can expire on the app's own timer must widen its margin too —
    /// see `maximiseHold()`.
    @discardableResult
    func coordinateTap(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// The warm-up opens on its offer screen, so getting past the
    /// block is one tap on the offer's own skip rather than the footer's.
    func startWorkout() {
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["warmup-intro-skip"]
        if skipWarmup.waitForExistence(timeout: 3) { skipWarmup.tap() }
    }

    /// The cool-down asks before it runs, and the question
    /// stands between the last exercise and the rating. Any walk that ends on
    /// the rating has to answer it — otherwise it waits for a screen that
    /// cannot arrive. Answers only if asked, so it is safe to call on a path
    /// that never reaches the block (a workout of pure skips has nothing to
    /// stretch and is never asked).
    @discardableResult
    func declineCooldownIfAsked(timeout: TimeInterval = 5) -> Bool {
        let skip = app.buttons["cooldown-intro-skip"]
        guard skip.waitForExistence(timeout: timeout) else { return false }
        coordinateTap(skip)
        return true
    }

    /// Returned rather than asserted: whether the cool-down had to run is
    /// the caller's rule, not the driver's.
    struct Walk {
        let sawCooldown: Bool
    }

    /// Requires --uitest-fast on the launch. Labels default to English
    /// because every suite but the release smoke's S7 row runs pinned to
    /// en/US; the cool-down's skip goes by identifier and needs no twin.
    @discardableResult
    func completeWorkout(skipCooldown skipsCooldown: Bool = true,
                         doneLabel: String = "Done",
                         startHoldLabel: String = "Start hold",
                         ratingLabel: String = "How did it go?",
                         file: StaticString = #filePath, line: UInt = #line) -> Walk {
        let done = app.buttons[doneLabel]
        let startHold = app.buttons[startHoldLabel]
        let skipCooldownButton = app.buttons["skip-cooldown"]
        let cooldownQuestion = app.buttons["cooldown-start"]
        let cooldownDeclineButton = app.buttons["cooldown-intro-skip"]
        let cooldownCountdown = app.staticTexts["cooldown-countdown"]
        let rating = app.staticTexts[ratingLabel]
        var sawCooldown = false
        // Wall-clock bound, not an iteration count. The seeded milestone
        // session spends ~330 s in holds alone, so this carries headroom.
        let deadline = Date.now.addingTimeInterval(420)
        while !rating.exists && Date.now < deadline {
            if done.exists {
                coordinateTap(done)
                _ = done.waitForNonExistence(timeout: 3)      // set logged → rest/next
            } else if startHold.exists {
                coordinateTap(startHold)
                _ = startHold.waitForNonExistence(timeout: 3)  // countdown started
            } else if cooldownQuestion.exists {
                // The block asks first. Skipping answers the
                // question rather than the footer — the block never runs, so
                // this is deliberately NOT counted as having seen it.
                coordinateTap(skipsCooldown ? cooldownDeclineButton : cooldownQuestion)
                _ = cooldownQuestion.waitForNonExistence(timeout: 3)
            } else if skipsCooldown, skipCooldownButton.exists {
                sawCooldown = true
                coordinateTap(skipCooldownButton)
                _ = skipCooldownButton.waitForNonExistence(timeout: 3)
            } else {
                // resting, stretching or mid-transition — under
                // --uitest-fast every one of those advances on its own
                if cooldownCountdown.exists { sawCooldown = true }
                _ = rating.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(rating.waitForExistence(timeout: 5),
                      "did not reach the rating screen", file: file, line: line)
        return Walk(sawCooldown: sawCooldown)
    }
}
