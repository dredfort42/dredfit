//
//  The hold-timer walks (plank, per-side holds, and the pull-up bar hang),
//  moved out of DredfitUITests.swift to keep it under the linter's file and
//  type-body ceilings. Kept together because they share the session-2 arrange
//  (`launchIntoSession2AndReachPlank`), the floor-seeking adjuster walk
//  (`shortenHoldToTheFloor`) and the ceiling-seeking one (`maximiseHold`),
//  all three used only by the tests below and moved with them. The bar hang
//  joined this file rather than staying with its "Pull-up bar" settings
//  toggle because, once the toggle is flipped, what it walks IS a hold timer
//  (maximiseHold, holdStart/holdStop) — the same shape as the plank and
//  per-side tests above it. The code moved unchanged.
//

import XCTest

// MARK: - Hold timer
extension DredfitUITests {

    /// Session 2 via --uitest-session2 (session 1 seeded as completed
    /// "yesterday"), skipped to the plank — the first hold exercise (20 s).
    private func launchIntoSession2AndReachPlank() {
        // WITH the reset, which this line used to lose by assigning the whole
        // argument list. The seed clears the engine state and the journal by
        // itself, so the four tests behind this helper stayed green on their
        // predecessor's leftovers — silently, and settings survive a seed.
        app.seedLaunchArguments("--uitest-session2")
        app.launch()
        // Seeded synchronously at launch: a busy runner can outrun a tight wait.
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 8),
                      "--uitest-session2 must open on workout 2")
        startWorkout()
        let startHold = app.buttons[AX.holdStart]
        skipExercises(until: startHold, limit: 6)
        XCTAssertTrue(startHold.waitForExistence(timeout: 3),
                      "the hold exercise did not offer the countdown")
    }

    /// Raises a hold to the adjuster's 90 s ceiling before it starts, so a
    /// test that stops it early has a margin no runner can eat.
    ///
    /// The nightly of 2026-08-04 (run 30875292377) failed here: XCUITest took
    /// 9.5 s to answer `waitForExistence` and 10.7 s to synthesize the tap, so
    /// the planned 20 s hang ran out on its own and the Stop tap landed on the
    /// rest screen that had replaced it. At 90 s the budget is 86 s, five
    /// times the worst yet observed — and the seconds actually held, which is
    /// what these tests assert on, do not change.
    private func maximiseHold() {
        let plus = openAdjuster(AX.adjustPlus)
        // Holds step by 5 within 5...90 (AdjustPanel), and the panel clamps —
        // saturating from the floor takes 17 taps, so 18 is enough from any
        // plan and the extra one costs nothing.
        for _ in 0..<18 { plus.tap() }
        app.buttons[AX.adjustConfirm].tap()
    }

    func testHoldTimerEarlyStopCapturesActual() {
        launchIntoSession2AndReachPlank()
        // 90 s of hold to stop early inside — the countdown must not be able
        // to run out from under the taps below on a slow runner.
        maximiseHold()
        // Taps inside the workout cover go through coordinateTap, to sidestep
        // the hittability quirk. Stop belongs to the RUNNING hold, so it
        // arrives only past the count-in the tap buys.
        coordinateTap(app.buttons[AX.holdStart])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the countdown")

        // A stop within the first seconds is a mis-tap — the countdown
        // cancels and the set survives instead of recording a 2-second plank.
        coordinateTap(stop)
        XCTAssertTrue(app.buttons[AX.holdStart].waitForExistence(timeout: 3),
                      "an immediate stop must cancel the countdown, not consume the set")

        // a real early stop (past the grace) records the held seconds
        coordinateTap(app.buttons[AX.holdStart])
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertTrue(coordinateTap(stop),
                      "the countdown ended before the stop could be delivered")
        // Set one of several: the stop closes it and the rest starts itself,
        // with no tap in between. Only the movement's LAST hold waits to be
        // logged — see `testOnlyTheLastHoldOfAMovementHandsTheSetBack`.
        let skipRest = app.buttons[AX.skipRest]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 5),
                      "an early stop with sets behind it should flow into rest")
        coordinateTap(skipRest)
        XCTAssertTrue(app.staticTexts["actual 5"].waitForExistence(timeout: 5),
                      "the held seconds were not recorded as the actual")
    }

    /// Down to the corridor's 5 s floor, whatever the plan asks for — the two
    /// tests below wait out a whole hold. Counted taps used to do it
    /// ("20 → 15 → 10 → 5") and stopped working without saying so: the hold
    /// grid is one second wide now, not five (`SetFacts.snap`). Walking to the
    /// floor cannot go stale that way — the panel clamps, so an extra tap
    /// costs nothing.
    private func shortenHoldToTheFloor() {
        let minus = openAdjuster(AX.adjustMinus)
        let floor = app.staticTexts["5 s"]
        var taps = 0
        while !floor.exists && taps < 90 {
            minus.tap()
            taps += 1
        }
        XCTAssertTrue(floor.exists, "the stepper never reached the 5 s floor")
        app.buttons[AX.adjustConfirm].tap()
    }

    /// The count-in "Start hold" earns (`GetReady.countInSeconds`): the clock
    /// used to start under the thumb, and the seconds spent getting into
    /// position came off the number the engine measures.
    func testStartHoldCountsInBeforeTheClockRuns() {
        launchIntoSession2AndReachPlank()
        let stop = app.buttons[AX.holdStop]
        let tappedAt = Date.now
        coordinateTap(app.buttons[AX.holdStart])
        // Cheapest check FIRST, deliberately: everything asserted inside the
        // count-in races a five-second window (GetReady.countInSeconds), one
        // XCUITest answer has cost this project 9.5 s (nightly 2026-08-04),
        // and the margin here was 4.10 s.
        XCTAssertFalse(stop.exists, "nothing may be held while the count-in runs")
        let getReady = app.staticTexts["Get ready"]
        XCTAssertTrue(getReady.waitForExistence(timeout: 3),
                      "the tap must open a count-in, not the hold itself")
        XCTAssertTrue(stop.waitForExistence(timeout: 15),
                      "the count-in must hand over to the hold")
        // The claim, measured rather than raced: the hold began LATER than
        // the tap. A lower bound cannot be broken by a slow runner — only by
        // an app that skipped the count-in.
        XCTAssertGreaterThan(Date.now.timeIntervalSince(tappedAt), 3,
                             "the hold started under the thumb — no count-in ran")
        XCTAssertFalse(getReady.exists, "the count-in is over once the hold runs")
    }

    /// Walks a hold exercise from wherever it stands to its LAST set, skipping
    /// the rests each finished set opens by itself. The goal is the settled
    /// screen, not a set count: what "last" means belongs to the plan, and a
    /// walk that counted sets would go stale the first time the plan changed.
    private func reachTheLastHoldSet(deadline seconds: TimeInterval = 150) {
        let done = app.buttons[AX.exerciseDone]
        let start = app.buttons[AX.holdStart]
        let skipRest = app.buttons[AX.skipRest]
        let deadline = Date.now.addingTimeInterval(seconds)
        while !done.exists && Date.now < deadline {
            if skipRest.exists {
                coordinateTap(skipRest)
                _ = start.waitForExistence(timeout: 10)
            } else if start.exists {
                coordinateTap(start)
                // Either the set settles (the last one) or a rest opens (any
                // earlier one). No wait covers both, so poll for whichever
                // arrives rather than burn a full timeout on the wrong one.
                let inner = Date.now.addingTimeInterval(30)
                while !done.exists && !skipRest.exists && Date.now < inner {
                    _ = done.waitForExistence(timeout: 1)
                }
            } else {
                _ = done.waitForExistence(timeout: 2)   // counting in, or held
            }
        }
    }

    /// A hold ends itself — and until 30.08.2026 the flow left the work screen
    /// in the same frame, so the seconds it had just recorded could never be
    /// corrected: after the last set of a movement no screen about that
    /// movement ever came back.
    ///
    /// Both halves of the rule are here, because the fix went too wide first:
    /// an EARLIER set still runs itself into its rest, and a tap between the
    /// effort and the recovery on every hold was friction the movement does
    /// not need — it comes back. It is the LAST set that is terminal, and
    /// there the clock owns only the end of the effort; the set is logged by
    /// the same tap that logs a set of reps (owner, 31.08.2026).
    func testOnlyTheLastHoldOfAMovementHandsTheSetBack() {
        launchIntoSession2AndReachPlank()
        shortenHoldToTheFloor()
        XCTAssertFalse(app.staticTexts["set 1 of 1"].exists,
                       "this walk needs a hold with more than one set to say anything")

        // Set one: five seconds of count-in ahead of the five the hold was
        // cut to, and then the rest — no tap anywhere in between.
        coordinateTap(app.buttons[AX.holdStart])
        let skipRest = app.buttons[AX.skipRest]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 20),
                      "a hold with sets behind it must start its rest by itself")
        XCTAssertFalse(app.buttons[AX.exerciseDone].exists,
                       "an earlier set must not stop to be logged")
        coordinateTap(skipRest)

        // …and the last one hands the set back instead.
        reachTheLastHoldSet()
        let done = app.buttons[AX.exerciseDone]
        XCTAssertTrue(done.waitForExistence(timeout: 30),
                      "the last hold did not hand the set back at zero")
        XCTAssertTrue(app.staticTexts["Held"].exists,
                      "nothing on screen says the hold is behind")
        XCTAssertTrue(app.buttons[AX.exerciseAdjust].exists,
                      "“Went differently” must be reachable once the hold is over")
        // `exists` is the wrong question: the row is `.opacity(0).disabled()`
        // so its reserved height keeps the layout still, and whether a fully
        // transparent view stays in the accessibility tree is SwiftUI's
        // business, not the rule's. What the rule says is that the control
        // cannot act.
        let skipSet = app.buttons[AX.exerciseSkipSet]
        XCTAssertFalse(skipSet.exists && skipSet.isEnabled,
                       "a performed set must not still offer to be skipped")
        coordinateTap(done)
        XCTAssertTrue(app.staticTexts["Held"].waitForNonExistence(timeout: 10),
                      "the logged hold did not leave the work screen")
    }

    /// The side-switch pause (issue #35): a per-side hold runs side one, pauses
    /// on an announced "Switch sides", then auto-starts side two with no tap.
    func testPerSideHoldPausesBetweenSidesAndAutoStartsTheSecond() {
        launchIntoSession2AndReachPlank()
        // The goal is the "seconds per side" caption, not the exercise name —
        // Today's plan list under the cover also holds the name, so the name
        // "exists" long before the bird dog's work screen is up.
        let perSideCaption = app.staticTexts["seconds per side"]
        skipExercises(until: perSideCaption, limit: 2)
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 3),
                      "the per-side hold must follow the plank in session 2")

        shortenHoldToTheFloor()

        coordinateTap(app.buttons[AX.holdStart])
        // side one (5 s, behind its count-in) runs out into the pause it
        // announces; the second side needs none, because the pause is one.
        XCTAssertTrue(app.staticTexts["Switch sides"].waitForExistence(timeout: 15),
                      "the pause must open when the first side ends")
        // the second side starts itself: Stop reappears with no tap anywhere
        XCTAssertTrue(app.buttons[AX.holdStop].waitForExistence(timeout: 9),
                      "the second side must start without a tap")
        XCTAssertTrue(app.staticTexts["second side"].exists,
                      "the second side must be labelled")
        // and runs out on its own into rest, like any completed set that is
        // not the movement's last
        XCTAssertTrue(app.buttons[AX.skipRest].waitForExistence(timeout: 9),
                      "the second side did not auto-advance to rest at zero")
    }

    /// Both sides of one set carry the same load: a first side cut short
    /// hands the second side ITS seconds, not the plan's.
    ///
    /// Observed through the clock rather than through the number on screen:
    /// the big digit has no identifier of its own, and what the rule is about
    /// is how long the second side actually runs. At the adjuster's 90 s
    /// ceiling the two answers are ninety seconds apart, so the deadline below
    /// separates them with room to spare — before the fix the second side ran
    /// the planned 90 and this timed out.
    func testTheSecondSideRunsWhatTheFirstSideRan() {
        launchIntoSession2AndReachPlank()
        let perSideCaption = app.staticTexts["seconds per side"]
        skipExercises(until: perSideCaption, limit: 2)
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 3),
                      "the per-side hold must follow the plank in session 2")

        maximiseHold()
        coordinateTap(app.buttons[AX.holdStart])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the count-in")
        // Past the three-second mis-tap grace, so this is a real early stop.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(coordinateTap(stop), "the first side ended before the stop landed")

        XCTAssertTrue(app.staticTexts["Switch sides"].waitForExistence(timeout: 10),
                      "an early stop on the first side must still open the switch pause")

        // NOTHING is tapped from here on, deliberately. An earlier version of
        // this test went on to brush Stop inside the mis-tap grace and press
        // "Start hold" again, to cover the retake path — and that HEALED the
        // defect it exists for: `startHold` recomputes the length correctly,
        // so a broken switch-pause no longer showed. A test that repairs its
        // own subject on the way to the assertion is worse than no test.
        // The retake's decision is pinned at unit level instead
        // (`SetFacts.holdSideSeconds`).
        XCTAssertTrue(app.buttons[AX.skipRest].waitForExistence(timeout: 30),
                      "the second side must run the first side's seconds, not the plan's")
    }

    // MARK: - Pull-up bar hang

    func testBarWorkoutFlowsToRating() {
        // No --uitest-fast: this test waits for and taps "Skip rest" itself, so
        // the rest must stay on screen long enough to see; its skip-through
        // hits only one rest, so the full 60 s is never waited out. WITH the
        // reset, which this line used to drop by assigning the whole argument
        // list — it then stood on whatever the previous test had left behind.
        app.seedLaunchArguments("--uitest-session2")
        app.launch()
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 5))

        app.buttons[AX.settings].tap()
        let toggle = app.switches[AX.hasBarToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "no pull-up bar toggle in settings")
        toggle.tap()
        app.buttons[AX.settingsDone].tap()
        XCTAssertTrue(app.staticTexts["Bar hang"].waitForExistence(timeout: 3),
                      "with the bar on, session 2 must swap in the bar hang")

        startWorkout()
        XCTAssertTrue(app.buttons[AX.holdStart].waitForExistence(timeout: 3),
                      "the bar hang must run as a hold exercise")
        app.buttons[AX.technique].tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3),
                      "the technique sheet must open for a bar exercise")
        app.buttons[AX.techniqueDone].tap()
        // 90 s of hang, for the same reason as the plank above: the stop below
        // is timed against the app's own countdown, and this test is the one
        // that lost that race on the nightly of 2026-08-04.
        maximiseHold()
        coordinateTap(app.buttons[AX.holdStart])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the hang countdown")
        Thread.sleep(forTimeInterval: 3.5)   // past the mis-tap grace
        XCTAssertTrue(coordinateTap(stop),
                      "the hang ended before the stop could be delivered")
        XCTAssertTrue(app.buttons[AX.skipRest].waitForExistence(timeout: 5),
                      "the stopped hang must flow into rest")
        coordinateTap(app.buttons[AX.skipRest])

        // the rest of the workout is not the point of this smoke — skip through
        let rating = app.staticTexts["How did it go?"]
        skipExercises(until: rating, limit: 6)
        driver.declineCooldownIfAsked()   // the block asks first
        XCTAssertTrue(rating.waitForExistence(timeout: 3))
        rate(landsOn: "Workout 2 completed")
    }
}
