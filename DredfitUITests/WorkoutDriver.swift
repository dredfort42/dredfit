//
//  WorkoutDriver.swift
//  DredfitUITests
//
//  The one way the UI tests drive a workout to the rating screen. Extracted
//  when the release smoke became a suite of its own (1.8.1): two copies of
//  this walk would drift, and the last time it drifted it cost the nightly
//  six red runs (I-5) — the fix that made it load-independent has to live in
//  exactly one place.
//
//  Load-independent by design: only stable controls are tapped (Done and
//  Start hold leave the screen only once acted on), each tap is confirmed by
//  waiting for its control to disappear, and a tap a busy runner drops is
//  simply retried on the next pass. Rests are never tapped — under
//  --uitest-fast they collapse to ~1 s and advance on their own.
//

import XCTest

@MainActor
struct WorkoutDriver {

    let app: XCUIApplication

    /// Taps an element at the centre of its own frame, bypassing hittability
    /// resolution. Inside the workout's fullScreenCover the CI simulator can
    /// report degenerate ancestor frames, so anything that resolves
    /// hittability (`.tap()`, `.isHittable`, predicate waits) fails with
    /// "activation point invalid" even though the control is on screen.
    /// The element's own leaf frame is valid, so a coordinate tap lands.
    func coordinateTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Taps Start and skips the warm-up block.
    func startWorkout() {
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["Skip warm-up"]
        if skipWarmup.waitForExistence(timeout: 3) { skipWarmup.tap() }
    }

    /// What the walk observed on its way to the rating. Returned rather than
    /// asserted here: whether the cool-down had to run is the caller's rule,
    /// not the driver's.
    struct Walk {
        let sawCooldown: Bool
    }

    /// Runs the whole workout to the rating screen: Done on every set, Start
    /// hold on every hold. Requires --uitest-fast on the launch.
    ///
    /// - Parameters:
    ///   - skipCooldown: tap "Skip cool-down" when it appears. The default
    ///     gets to the rating fastest; the release smoke passes `false` so the
    ///     cool-down actually runs, because S2 names it.
    ///   - doneLabel, startHoldLabel, ratingLabel: the localized labels to
    ///     drive. Defaulted to English because every suite but the release
    ///     smoke's S7 row runs pinned to en/US; S7 passes the Russian ones.
    ///     The cool-down's skip is addressed by accessibility identifier, so
    ///     it needs no localized twin.
    @discardableResult
    func completeWorkout(skipCooldown skipsCooldown: Bool = true,
                         doneLabel: String = "Done",
                         startHoldLabel: String = "Start hold",
                         ratingLabel: String = "How did it go?",
                         file: StaticString = #filePath, line: UInt = #line) -> Walk {
        let done = app.buttons[doneLabel]
        let startHold = app.buttons[startHoldLabel]
        let skipCooldownButton = app.buttons["skip-cooldown"]
        let cooldownCountdown = app.staticTexts["cooldown-countdown"]
        let rating = app.staticTexts[ratingLabel]
        var sawCooldown = false
        // Wall-clock bound, not an iteration count: the only real time sink
        // is the hold countdowns (~3 minutes in a deep session), which are
        // load-independent, so this bound holds even on a saturated runner.
        // The seeded milestone session spends ~330 s in holds alone, so the
        // bound carries a little headroom for taps and transitions.
        let deadline = Date.now.addingTimeInterval(420)
        while !rating.exists && Date.now < deadline {
            if done.exists {
                coordinateTap(done)
                _ = done.waitForNonExistence(timeout: 3)      // set logged → rest/next
            } else if startHold.exists {
                coordinateTap(startHold)
                _ = startHold.waitForNonExistence(timeout: 3)  // countdown started
                // the countdown runs itself down and auto-advances into rest
            } else if skipsCooldown, skipCooldownButton.exists {
                sawCooldown = true
                coordinateTap(skipCooldownButton)
                _ = skipCooldownButton.waitForNonExistence(timeout: 3)
            } else {
                // resting, stretching or mid-transition: under --uitest-fast
                // every one of those advances on its own
                if cooldownCountdown.exists { sawCooldown = true }
                _ = rating.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(rating.waitForExistence(timeout: 5),
                      "did not reach the rating screen", file: file, line: line)
        return Walk(sawCooldown: sawCooldown)
    }
}
