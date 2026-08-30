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

    /// The three in-workout skips ask before they act (SkipConfirmation.swift).
    /// The raw value IS the alert button's label, and that label is
    /// deliberately not the label on the control that raised the question — a
    /// query for one must never resolve to the other.
    ///
    /// ENGLISH ONLY, unlike everything else this driver taps. An alert button
    /// carries no identifier that survives into the accessibility tree, so a
    /// label is what there is — which means a localized walk (S7) must not
    /// route a skip through here. It does not today: `completeWorkout` never
    /// skips, it finishes every set.
    enum Skip: String {
        case set = "Skip the set"
        case remainingSets = "Skip the remaining sets"
        case exercise = "Skip the exercise"
    }

    /// Answers a skip's question. One place for it, because a confirmation
    /// added to a control is exactly the change that leaves half a dozen call
    /// sites tapping into a flow that no longer moves.
    ///
    /// A plain `.tap()`, not `coordinateTap`: the alert is its own
    /// presentation, outside the workout's fullScreenCover, so the hittability
    /// quirk that forces coordinates inside the cover does not apply here.
    @discardableResult
    func confirmSkip(_ kind: Skip, timeout: TimeInterval = 5) -> Bool {
        let confirm = app.buttons[kind.rawValue]
        guard confirm.waitForExistence(timeout: timeout) else { return false }
        confirm.tap()
        return true
    }

    /// The escape and its answer as one act — what every caller that just
    /// wants the skip to happen should reach for.
    @discardableResult
    func skip(_ kind: Skip, control identifier: String,
              timeout: TimeInterval = 5) -> Bool {
        let control = app.buttons[identifier]
        guard control.waitForExistence(timeout: timeout) else { return false }
        coordinateTap(control)
        return confirmSkip(kind, timeout: timeout)
    }

    /// The warm-up opens on its offer screen, so getting past the block is one
    /// tap on the offer's own skip rather than the footer's.
    func startWorkout() {
        app.buttons[AX.startWorkout].tap()
        let skipWarmup = app.buttons[AX.warmupIntroSkip]
        if skipWarmup.waitForExistence(timeout: 3) { skipWarmup.tap() }
    }

    /// The work, walked until the cool-down is OFFERED — the question that
    /// stands between the last exercise and the rating — without answering it.
    ///
    /// Three copies of this loop stood outside the driver (HandlesUITests,
    /// BlockPauseUITests, DredfitUITests+Cooldown) at the same time as the
    /// warning at the top of this file, which the last drift had already cost
    /// six red nightly runs to earn. It is one loop now; what each caller
    /// wants from the offer is still the caller's own business.
    ///
    /// Returns whether the offer arrived, so a caller can fail with its own
    /// sentence instead of inheriting the driver's.
    @discardableResult
    func walkToCooldownOffer(deadline seconds: TimeInterval = 360,
                             ratingLabel: String = "How did it go?") -> Bool {
        let done = app.buttons[AX.exerciseDone]
        let startHold = app.buttons[AX.holdStart]
        let offer = app.buttons[AX.cooldownStart]
        // The rating is the other way this walk can end, and it is a failure
        // for every caller: a workout that reaches it was never asked. Stopping
        // on it turns a whole deadline of spinning into an immediate answer.
        let rating = app.staticTexts[ratingLabel]
        let deadline = Date.now.addingTimeInterval(seconds)
        while !offer.exists && !rating.exists && Date.now < deadline {
            if done.exists {
                coordinateTap(done)
                _ = done.waitForNonExistence(timeout: 3)
            } else if startHold.exists {
                coordinateTap(startHold)
                _ = startHold.waitForNonExistence(timeout: 3)
            } else {
                // resting or mid-transition — every one of those advances on
                // its own, so waiting on the goal is also the settle.
                _ = offer.waitForExistence(timeout: 2)
            }
        }
        return offer.exists
    }

    /// The cool-down asks before it runs, and the question stands between the
    /// last exercise and the rating. Any walk that ends on the rating has to
    /// answer it — otherwise it waits for a screen that cannot arrive. Answers
    /// only if asked, so it is safe to call on a path that never reaches the
    /// block (a workout of pure skips has nothing to stretch and is never
    /// asked).
    @discardableResult
    func declineCooldownIfAsked(timeout: TimeInterval = 5) -> Bool {
        let skip = app.buttons[AX.cooldownIntroSkip]
        guard skip.waitForExistence(timeout: timeout) else { return false }
        coordinateTap(skip)
        return true
    }

    /// Returned rather than asserted: whether the cool-down had to run is
    /// the caller's rule, not the driver's.
    struct Walk {
        let sawCooldown: Bool
    }

    /// Requires --uitest-fast on the launch. Every control it taps now goes by
    /// identifier, so the walk is the same in any language and the release
    /// smoke's S7 row needs no English twins to pass in — only the rating
    /// HEADLINE is still a label, because that screen carries no identifier of
    /// its own.
    ///
    /// `deadline` is wall-clock and therefore sensitive to how loaded the
    /// runner is, which is why it is a parameter rather than a constant: the
    /// longest consumer (`testMilestoneScreenListsEverythingEarned`) spent
    /// 205 s of the old fixed 420 on a healthy machine, a margin of ×2.05, and
    /// the next seed that adds a hold would eat the rest of it silently. The
    /// failure now reports the time actually spent, so a runner that ran out
    /// of budget cannot be read as a flow that never reached the rating.
    @discardableResult
    func completeWorkout(skipCooldown skipsCooldown: Bool = true,
                         deadline seconds: TimeInterval = 420,
                         ratingLabel: String = "How did it go?",
                         file: StaticString = #filePath, line: UInt = #line) -> Walk {
        let done = app.buttons[AX.exerciseDone]
        let startHold = app.buttons[AX.holdStart]
        let skipCooldownButton = app.buttons[AX.skipCooldown]
        let cooldownQuestion = app.buttons[AX.cooldownStart]
        let cooldownDeclineButton = app.buttons[AX.cooldownIntroSkip]
        let cooldownCountdown = app.staticTexts[AX.cooldownCountdown]
        let rating = app.staticTexts[ratingLabel]
        var sawCooldown = false
        let startedAt = Date.now
        let deadline = startedAt.addingTimeInterval(seconds)
        while !rating.exists && Date.now < deadline {
            if done.exists {
                coordinateTap(done)
                _ = done.waitForNonExistence(timeout: 3)      // set logged → rest/next
            } else if startHold.exists {
                coordinateTap(startHold)
                _ = startHold.waitForNonExistence(timeout: 3)  // countdown started
            } else if cooldownQuestion.exists {
                // The block asks first. Skipping answers the question rather
                // than the footer — the block never runs, so this is
                // deliberately NOT counted as having seen it.
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
        let spent = Int(Date.now.timeIntervalSince(startedAt))
        XCTAssertTrue(rating.waitForExistence(timeout: 5),
                      "did not reach the rating screen after \(spent) s of a "
                        + "\(Int(seconds)) s budget — a walk that spent the whole "
                        + "budget ran out of runner, not out of flow",
                      file: file, line: line)
        return Walk(sawCooldown: sawCooldown)
    }
}
