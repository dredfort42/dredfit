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
    /// launch it with `--uitest-hold-long`.
    /// An INFINITE frame is refused as well, and that is not belt and braces:
    /// a control standing down as `.opacity(0).disabled()` keeps its place in
    /// the tree and can report `CGRect.null`, whose origin is infinite —
    /// `coordinate(withNormalizedOffset:)` then raises
    /// NSInternalInconsistencyException and takes the whole test down with a
    /// message about a point, which says nothing about the screen.
    ///
    /// FINITENESS ONLY: an empty frame is still tapped. Inside the workout's
    /// fullScreenCover this simulator reports zero-sized frames for controls
    /// that are plainly on screen — the same quirk that forces coordinates
    /// here in the first place — so refusing those would refuse half the
    /// flow's own buttons.
    @discardableResult
    func coordinateTap(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return false }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// All four in-workout skips ask before they act (SkipConfirmation.swift),
    /// and all four answer to the same short button — deliberately, because
    /// the alert's layout follows its label widths and per-kind labels made
    /// two neighbouring controls stack differently. Which question is up is
    /// read off the TITLE, never off this; a test that needs to know asserts
    /// the title.
    ///
    /// ENGLISH ONLY, unlike everything else this driver taps. An alert button
    /// carries no identifier that survives into the accessibility tree, so a
    /// label is what there is — which means a localized walk (S7) must not
    /// route a skip through here. It does not today: `completeWorkout` never
    /// skips, it finishes every set.
    ///
    /// The onboarding cards carry a "Skip" of their own. It is a different
    /// screen and never up at the same time, and no control inside the workout
    /// reads exactly this word.
    static let skipConfirmLabel = "Skip"

    /// Answers a skip's question. One place for it, because a confirmation
    /// added to a control is exactly the change that leaves half a dozen call
    /// sites tapping into a flow that no longer moves.
    ///
    /// A plain `.tap()`, not `coordinateTap`: the alert is its own
    /// presentation, outside the workout's fullScreenCover, so the hittability
    /// quirk that forces coordinates inside the cover does not apply here.
    @discardableResult
    func confirmSkip(timeout: TimeInterval = 5) -> Bool {
        let confirm = app.buttons[Self.skipConfirmLabel]
        guard confirm.waitForExistence(timeout: timeout) else { return false }
        confirm.tap()
        return true
    }

    /// The escape and its answer as one act — what every caller that just
    /// wants the skip to happen should reach for.
    @discardableResult
    func skip(control identifier: String, timeout: TimeInterval = 5) -> Bool {
        let control = app.buttons[identifier]
        guard control.waitForExistence(timeout: timeout) else { return false }
        coordinateTap(control)
        return confirmSkip(timeout: timeout)
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
        // ONE tap per hold exercise since R23: the sets after the first count
        // themselves in and this control does not come back. `holdStart` is
        // still tapped when it does — the probe set, which the auto-run leaves
        // to the person — so both stay in the loop.
        let startHold = app.buttons[AX.holdStartExercise]
        let startOneHold = app.buttons[AX.holdStart]
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
            } else if startOneHold.exists {
                coordinateTap(startOneHold)
                _ = startOneHold.waitForNonExistence(timeout: 3)
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

    /// Answers the cool-down's footer escape and proves the rating followed.
    ///
    /// CONFIRMED and retried once, because a single unconfirmed `.tap()` on a
    /// control inside the workout's fullScreenCover GETS LOST, and a lost tap
    /// leaves the button standing. Measured on the local full run of
    /// 02.09.2026 (I-22): the tap was synthesized dead centre of an enabled
    /// `skip-cooldown` ({{24, 764}, {354, 56}}, so (201, 792)) with no
    /// interrupting elements, and the app never acted on it — the block ran on
    /// through all seven positions with the escape still on screen. So the
    /// confirmation is the button's disappearance and the recovery is a second
    /// tap: the rule at the top of this file, and the same retry
    /// `BlockPauseUITests` already carries for its own resumed block.
    ///
    /// THE BUDGET IS THE CHECK — DO NOT RAISE THESE SECONDS. Under
    /// `--uitest-fast` the block also ends by itself, ~17 s after the escape is
    /// first offered on position 1 of 7. 4 s + one retry + 5 s holds the whole
    /// wait under 9 s, so a rating that arrives in time can only be the skip.
    /// Widened to 20 s the test goes green on the block merely running out,
    /// having stopped checking the skip at all: I-22's first fix already moved
    /// this wait 3 s → 15 s and the transition was lost anyway, so the next
    /// reader's instinct — more seconds — turns a red test into a silent one.
    ///
    /// The retry is refused once the rating is up, and `coordinateTap` refuses
    /// a control that has vanished. Both matter: the rating's cards stand in
    /// the same bottom slot, so a blind second tap would answer the question
    /// this walk exists to ask.
    @discardableResult
    func skipCooldownBlock(ratingLabel: String = "How did it go?",
                           file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let skip = app.buttons[AX.skipCooldown]
        let rating = app.staticTexts[ratingLabel]
        guard coordinateTap(skip) else {
            XCTFail("the running cool-down must offer a way out of the block",
                    file: file, line: line)
            return false
        }
        if !skip.waitForNonExistence(timeout: 4), !rating.exists {
            coordinateTap(skip)
        }
        XCTAssertTrue(rating.waitForExistence(timeout: 5),
                      "skipping the cool-down lands on the rating",
                      file: file, line: line)
        return rating.exists
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
        let startHold = app.buttons[AX.holdStartExercise]
        let startOneHold = app.buttons[AX.holdStart]
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
            } else if startOneHold.exists {
                coordinateTap(startOneHold)
                _ = startOneHold.waitForNonExistence(timeout: 3)
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
