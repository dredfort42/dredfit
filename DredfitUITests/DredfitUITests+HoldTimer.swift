//
//  The hold-timer walks (plank, per-side holds, and the pull-up bar hang),
//  moved out of DredfitUITests.swift to keep it under the linter's file and
//  type-body ceilings. Kept together because they share the session-2 arrange
//  (`launchIntoSession2AndReachPlank`) and the two hold lengths it can seed.
//  The bar hang joined this file rather than staying with its "Pull-up bar"
//  settings toggle because, once the toggle is flipped, what it walks IS a
//  hold timer — the same shape as the plank and per-side tests above it.
//
//  THE HOLD LENGTH IS SEEDED AT LAUNCH, not typed on the screen. It used to be
//  typed: two helpers opened "Went differently" before the effort and walked
//  the stepper to the corridor's floor or its ceiling. R23 removed that
//  control from the hold screen — nothing is entered before the effort — so
//  the two lengths the suite actually needed became `--uitest-hold-short`
//  (the floor, to walk a whole hold exercise inside a test's budget) and
//  `--uitest-hold-long` (the ceiling, to give a mid-hold Stop a margin no
//  loaded runner can eat).
//

import XCTest

// MARK: - Hold timer
extension DredfitUITests {

    /// Session 2 via --uitest-session2 (session 1 seeded as completed
    /// "yesterday"), skipped to the plank — the first hold exercise.
    ///
    /// WITH the reset, which this arrange used to lose by assigning the whole
    /// argument list. The seed clears the engine state and the journal by
    /// itself, so the tests behind this helper stayed green on their
    /// predecessor's leftovers — silently, and settings survive a seed.
    private func launchIntoSession2AndReachPlank(_ seeds: String...) {
        app.seedLaunchArguments(["--uitest-session2"] + seeds)
        app.launch()
        // Seeded synchronously at launch: a busy runner can outrun a tight wait.
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 8),
                      "--uitest-session2 must open on workout 2")
        startWorkout()
        let startExercise = app.buttons[AX.holdStartExercise]
        skipExercises(until: startExercise, limit: 6)
        XCTAssertTrue(startExercise.waitForExistence(timeout: 3),
                      "the hold exercise did not offer the countdown")
    }

    // MARK: - One tap per exercise

    /// R23: a hold exercise used to cost four touches, three of them taken
    /// between sets by somebody lying on the floor. One tap now buys the whole
    /// exercise — every set after the first counts itself in when its rest
    /// ends, and the phone is not touched again until the movement is over.
    ///
    /// Nothing is tapped between the first tap and the last screen, which is
    /// the whole assertion: if the auto-run were broken the flow would stop on
    /// a start button after the first rest and the settled last set would
    /// never arrive.
    func testOneTapRunsTheWholeHoldExercise() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        XCTAssertFalse(app.staticTexts["set 1 of 1"].exists,
                       "this walk needs a hold with more than one set to say anything")
        XCTAssertTrue(app.element(withIdentifier: AX.holdSetsAndRest).exists,
                      "the screen before the tap must say what the exercise is")
        XCTAssertTrue(app.element(withIdentifier: AX.holdAutorunPromise).exists,
                      "the tap promises the exercise runs itself — say so before it")
        XCTAssertTrue(app.buttons[AX.holdSetTime].exists,
                      "a hold takes one thing before the effort: how long it runs")
        XCTAssertFalse(app.buttons[AX.exerciseAdjust].exists,
                       "“Went differently” asks how a set WENT — before the "
                        + "effort there is no set to ask about")

        coordinateTap(app.buttons[AX.holdStartExercise])

        // The settled LAST set is the goal. Reaching it without a second tap
        // is what the one tap bought: count-in, hold, rest, count-in, hold …
        let done = app.buttons[AX.exerciseDone]
        XCTAssertTrue(done.waitForExistence(timeout: 90),
                      "the exercise did not run itself to its last set")
        XCTAssertTrue(app.element(withIdentifier: AX.summaryHeld).exists,
                      "nothing on screen says the hold is behind")
        XCTAssertFalse(app.buttons[AX.holdStartExercise].exists,
                       "the exercise was started once — it must not ask again")
        // R23 removed the entry from BEFORE the effort, never from after it —
        // and what it left in its place says more: EVERY set of the movement
        // is on this screen and correctable, not only the last one (#220).
        XCTAssertTrue(app.buttons[AX.summarySet(1)].exists,
                      "the first set must be correctable too — that is the "
                        + "whole reason this screen replaced the settled hold")
        coordinateTap(done)
        XCTAssertTrue(app.buttons[AX.summarySet(1)].waitForNonExistence(timeout: 10),
                      "the logged movement did not leave the summary")
    }

    /// The count-in before an AUTO-CONTINUED set is longer than the one a tap
    /// earns, and `GetReady.countInSeconds` already says why: a tap is somebody
    /// saying "I am ready" and needs only the beat between saying it and being
    /// counted in, while a set the run opened was agreed to sets ago by
    /// somebody who has since been lying on the floor.
    ///
    /// Measured as a LOWER BOUND on the second count-in, which a slow runner
    /// cannot break — only an app that spent the short one there can.
    /// Deliberately without --uitest-fast: that flag collapses both lengths to
    /// a second and the difference would be invisible.
    func testAnAutoContinuedSetIsCountedInAsTravelNotAsABeat() {
        launchIntoSession2AndReachPlank("--uitest-hold-short")
        let stop = app.buttons[AX.holdStop]
        coordinateTap(app.buttons[AX.holdStartExercise])
        XCTAssertTrue(stop.waitForExistence(timeout: 12),
                      "the tapped count-in never handed over to the hold")

        // Set one runs itself out into its rest; skipping it puts the auto
        // count-in under the clock immediately.
        let skipRest = app.buttons[AX.skipRest]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 20),
                      "a hold with sets behind it must start its rest by itself")
        coordinateTap(skipRest)

        let openedAt = Date.now
        XCTAssertTrue(app.staticTexts["Get ready"].waitForExistence(timeout: 5),
                      "the set after the rest must count itself in, with no tap")
        XCTAssertTrue(stop.waitForExistence(timeout: 30),
                      "the auto-continued count-in never handed over to the hold")
        XCTAssertGreaterThan(Date.now.timeIntervalSince(openedAt), 8,
                             "the auto-continued set was counted in as a beat "
                                + "(5 s), not as travel to the position")
    }

    // MARK: - Stopping a hold

    /// An early stop past the grace records what was held, and the number
    /// carries onto the sets after it — which is the only place it can be read
    /// now that the exercise runs itself: the caption a stopped set used to
    /// leave on the screen is replaced by the next set's own count-in.
    func testHoldTimerEarlyStopCapturesActual() {
        // 90 s of hold to stop early inside — the countdown must not be able
        // to run out from under the taps below on a slow runner. The seed is
        // the PLAN, so the five seconds this records govern the sets after it
        // and the walk to the movement's last set costs seconds, not minutes.
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-long")
        // Taps inside the workout cover go through coordinateTap, to sidestep
        // the hittability quirk. Stop belongs to the RUNNING hold, so it
        // arrives only past the count-in the tap buys.
        coordinateTap(app.buttons[AX.holdStartExercise])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the countdown")

        // A stop within the first seconds is a mis-tap — the countdown
        // cancels and the set survives instead of recording a 2-second plank.
        // What comes back is the ONE-set control: the exercise is already
        // under way, so it is not offered for sale a second time.
        coordinateTap(stop)
        XCTAssertTrue(app.buttons[AX.holdStart].waitForExistence(timeout: 3),
                      "an immediate stop must cancel the countdown, not consume the set")
        XCTAssertFalse(app.buttons[AX.holdStartExercise].exists,
                       "a cancelled set re-arms the set, not the whole exercise")

        // a real early stop (past the grace) records the held seconds
        coordinateTap(app.buttons[AX.holdStart])
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertTrue(coordinateTap(stop),
                      "the countdown ended before the stop could be delivered")
        // Set one of several: the stop closes it, and the exercise carries on
        // by itself — rest, count-in, the remaining sets, each of them now
        // running the FIVE seconds this one reported rather than the plan.
        let done = app.buttons[AX.exerciseDone]
        XCTAssertTrue(done.waitForExistence(timeout: 60),
                      "an early stop must not stop the exercise it happened in")
        // Read off the movement's own summary, which is where the numbers
        // stand once the exercise is behind. The stopped set is marked as an
        // ESTIMATE as well: it ended under a thumb, and the reach allowance
        // that produced its number is a guess about a walk to the phone.
        let firstCard = app.buttons[AX.summarySet(1)]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10),
                      "the finished movement did not reach its summary")
        XCTAssertTrue(firstCard.label.contains("approximately 5 seconds"),
                      "the early-stopped seconds were not recorded as an "
                        + "estimate of five — got “\(firstCard.label)”")
    }

    /// R29: the control names the figure it will write, so the two to four
    /// seconds spent reaching for the phone are a decision rather than a
    /// surprise. Inside the mis-tap grace it names nothing — that tap cancels
    /// the set and writes no number at all.
    func testStopNamesTheFigureItWillRecord() {
        launchIntoSession2AndReachPlank("--uitest-hold-long")
        coordinateTap(app.buttons[AX.holdStartExercise])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the countdown")
        XCTAssertEqual(stop.label, "Stop",
                       "inside the grace the tap records nothing — a figure would be a lie")

        // Past the grace the label carries the number a stop would actually
        // store: the seconds held, less the reach allowance, never below the
        // corridor's five-second floor. Slept rather than raced — the hang is
        // 90 s here, so six seconds cannot run it out.
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(stop.label.hasPrefix("Stop, records "),
                      "past the grace the control must name what it will write, "
                        + "got “\(stop.label)”")
    }

    // MARK: - Per-side holds

    /// The side-switch pause (issue #35): a per-side hold runs side one, pauses
    /// on an announced "Switch sides", then auto-starts side two with no tap.
    func testPerSideHoldPausesBetweenSidesAndAutoStartsTheSecond() {
        launchIntoSession2AndReachPlank("--uitest-hold-short")
        // The goal is the "seconds per side" caption, not the exercise name —
        // Today's plan list under the cover also holds the name, so the name
        // "exists" long before the bird dog's work screen is up.
        let perSideCaption = app.staticTexts["seconds per side"]
        skipExercises(until: perSideCaption, limit: 2)
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 3),
                      "the per-side hold must follow the plank in session 2")

        coordinateTap(app.buttons[AX.holdStartExercise])
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
    /// is how long the second side actually runs. At the corridor's 90 s
    /// ceiling the two answers are ninety seconds apart, so the deadline below
    /// separates them with room to spare — before the fix the second side ran
    /// the planned 90 and this timed out.
    func testTheSecondSideRunsWhatTheFirstSideRan() {
        launchIntoSession2AndReachPlank("--uitest-hold-long")
        let perSideCaption = app.staticTexts["seconds per side"]
        skipExercises(until: perSideCaption, limit: 2)
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 3),
                      "the per-side hold must follow the plank in session 2")

        coordinateTap(app.buttons[AX.holdStartExercise])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the count-in")
        // Past the three-second mis-tap grace, so this is a real early stop.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(coordinateTap(stop), "the first side ended before the stop landed")

        XCTAssertTrue(app.staticTexts["Switch sides"].waitForExistence(timeout: 10),
                      "an early stop on the first side must still open the switch pause")

        // NOTHING is tapped from here on, deliberately. An earlier version of
        // this test went on to brush Stop inside the mis-tap grace and press
        // the start button again, to cover the retake path — and that HEALED
        // the defect it exists for: `startHold` recomputes the length
        // correctly, so a broken switch-pause no longer showed. A test that
        // repairs its own subject on the way to the assertion is worse than no
        // test. The retake's decision is pinned at unit level instead
        // (`SetFacts.holdSideSeconds`).
        XCTAssertTrue(app.buttons[AX.skipRest].waitForExistence(timeout: 30),
                      "the second side must run the first side's seconds, not the plan's")
    }

    // MARK: - Pull-up bar hang

    func testBarWorkoutFlowsToRating() {
        // 90 s of hang so the stop below is not raced by the app's own
        // countdown — this test is the one that lost that race on the nightly
        // of 2026-08-04. WITH --uitest-fast, which it did without while it
        // still tapped "Skip rest" by hand: a hold exercise runs itself now,
        // so the rests it opens are the auto-run's business and the walk that
        // used to tap through them would be waiting on a screen that closes
        // itself. WITH the reset, which this line used to drop by assigning
        // the whole argument list — it then stood on whatever the previous
        // test had left behind.
        app.seedLaunchArguments("--uitest-session2", "--uitest-fast",
                                "--uitest-hold-long")
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
        XCTAssertTrue(app.buttons[AX.holdStartExercise].waitForExistence(timeout: 3),
                      "the bar hang must run as a hold exercise")
        app.buttons[AX.technique].tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3),
                      "the technique sheet must open for a bar exercise")
        app.buttons[AX.techniqueDone].tap()
        coordinateTap(app.buttons[AX.holdStartExercise])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the hang countdown")
        Thread.sleep(forTimeInterval: 3.5)   // past the mis-tap grace
        XCTAssertTrue(coordinateTap(stop),
                      "the hang ended before the stop could be delivered")
        // The stopped hang closes its own set and the exercise carries on;
        // the remaining sets run the seconds it reported, so the movement is
        // behind in a handful of them.
        let done = app.buttons[AX.exerciseDone]
        XCTAssertTrue(done.waitForExistence(timeout: 60),
                      "the stopped hang must run the exercise out by itself")
        // Logged, not skipped past: the movement is behind and its escapes
        // have stood down, so a skip-through started here would spin against
        // controls that cannot act.
        coordinateTap(done)

        // the rest of the workout is not the point of this smoke — skip through
        let rating = app.staticTexts["How did it go?"]
        skipExercises(until: rating, limit: 6)
        driver.declineCooldownIfAsked()   // the block asks first
        XCTAssertTrue(rating.waitForExistence(timeout: 3))
        rate(landsOn: "Workout 2 completed")
    }
}

// MARK: - The declared time and the exercise summary
extension DredfitUITests {

    /// Opens the pre-effort entry and walks the stepper to `seconds`.
    ///
    /// Reads where the panel OPENED rather than assuming it, and steps in
    /// whichever direction is needed. A helper that only walked up worked on
    /// the plank and could never reach a target below the plan — and the
    /// panel opens on the plan, which moves whenever the engine says so.
    private func declareHoldTime(_ seconds: Int) {
        coordinateTap(app.buttons[AX.holdSetTime])
        let plus = app.buttons[AX.adjustPlus]
        XCTAssertTrue(plus.waitForExistence(timeout: 5),
                      "the entry did not open its stepper")
        let target = app.staticTexts["\(seconds) s"]
        // The panel's own value, which is the only static text on the screen
        // that is a bare number of seconds.
        let value = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+ s$")).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5),
                      "the stepper is not showing a value to walk from")
        let opened = Int(value.label.replacingOccurrences(of: " s", with: "")) ?? 0
        let step = opened < seconds ? plus : app.buttons[AX.adjustMinus]
        var taps = 0
        while !target.exists && taps < abs(seconds - opened) + 5 {
            step.tap()
            taps += 1
        }
        XCTAssertTrue(target.exists,
                      "the stepper never reached \(seconds) s from \(opened)")
        app.buttons[AX.adjustConfirm].tap()
    }

    /// THE channel for "more than the plan" on a hold: say so before the
    /// effort, while you are standing up and can reach the phone. The clock
    /// then runs from that number on every set, and what the engine reads is
    /// still what the clock measured.
    func testADeclaredTimeGovernsEverySetAndReachesTheSummary() {
        // 20 is above the plank's own plan, which is what the summary
        // compares each card against — so this walk is the "more than the
        // plan" case, the one the declaration exists for.
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        XCTAssertTrue(app.buttons[AX.holdSetTime].exists,
                      "a hold must let you say how long it will run")

        declareHoldTime(20)
        coordinateTap(app.buttons[AX.holdStartExercise])

        let lastCard = app.buttons[AX.summarySet(3)]
        XCTAssertTrue(lastCard.waitForExistence(timeout: 150),
                      "the exercise did not run itself out at the declared time")
        for set in 1...3 {
            let label = app.buttons[AX.summarySet(set)].label
            XCTAssertTrue(label.contains("20 seconds"),
                          "set \(set) did not run the declared time — got “\(label)”")
        }
        XCTAssertTrue(lastCard.label.contains("planned 15"),
                      "the summary must still compare against the PLAN, not "
                        + "against what was declared")
    }

    /// The case nothing after the plan could ever serve: a per-side hold records the
    /// SMALLER of its two sides, so nothing that happens after the plan is met
    /// can raise its number. A declared time can, because both sides run from
    /// it — the same code, with no exception for this shape.
    func testAPerSideHoldTakesADeclaredTimeOnBothSides() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        let perSideCaption = app.staticTexts["seconds per side"]
        skipExercises(until: perSideCaption, limit: 2)
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 3),
                      "the per-side hold must follow the plank in session 2")

        // Below this movement's plan, deliberately: two sides of three sets
        // at a raised time outlast the test's budget, and what this walk is
        // about is that BOTH SIDES run the declared number at all. The "more
        // than the plan" direction is the plank walk above.
        declareHoldTime(10)
        coordinateTap(app.buttons[AX.holdStartExercise])

        let lastCard = app.buttons[AX.summarySet(3)]
        XCTAssertTrue(lastCard.waitForExistence(timeout: 180),
                      "a per-side hold must reach the summary like any other")
        XCTAssertTrue(lastCard.label.contains("10 seconds"),
                      "both sides must run the declared time — got “\(lastCard.label)”")
    }

    /// A declared time outlives the process dying. Coming back to the plan's
    /// number would undo the decision without saying so.
    func testADeclaredTimeSurvivesTheAppBeingKilled() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        declareHoldTime(20)
        coordinateTap(app.buttons[AX.holdStartExercise])
        XCTAssertTrue(app.buttons[AX.holdStop].waitForExistence(timeout: 15),
                      "the declared hold never started")
        app.terminate()

        let relaunch = XCUIApplication.launchedOnStoredState("--uitest-fast",
                                                            "--uitest-hold-short")
        XCTAssertTrue(relaunch.buttons[AX.resumeContinue].waitForExistence(timeout: 10),
                      "an interrupted workout must offer to be continued")
        relaunch.buttons[AX.resumeContinue].tap()
        // The set is offered again — a hold never restores mid-count — but at
        // the DECLARED length, which is what the summary then records.
        let lastCard = relaunch.buttons[AX.summarySet(3)]
        let start = relaunch.buttons[AX.holdStartExercise]
        if start.waitForExistence(timeout: 10) { driver.coordinateTap(start) }
        XCTAssertTrue(lastCard.waitForExistence(timeout: 180),
                      "the resumed exercise never finished")
        XCTAssertTrue(lastCard.label.contains("20 seconds"),
                      "the declared time did not survive the kill — got "
                        + "“\(lastCard.label)”")
    }

    /// R26: the summary is the first screen on which sets 1…n−1 can be
    /// corrected at all. The work screen's writer records the set UNDER WAY
    /// and truncates what follows — correct as it stands, since those sets
    /// have not happened — so before this there was no writer that could
    /// touch set one without deleting sets two and three.
    func testCorrectingOneSetOnTheSummaryLeavesTheOthersStanding() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        coordinateTap(app.buttons[AX.holdStartExercise])

        let first = app.buttons[AX.summarySet(1)]
        XCTAssertTrue(first.waitForExistence(timeout: 90),
                      "the movement did not reach its summary")
        let secondBefore = app.buttons[AX.summarySet(2)].label
        let thirdBefore = app.buttons[AX.summarySet(3)].label
        let firstBefore = first.label

        coordinateTap(first)
        let plus = app.buttons[AX.adjustPlus]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "the card did not open the stepper")
        for _ in 0..<3 { plus.tap() }
        app.buttons[AX.adjustConfirm].tap()

        XCTAssertTrue(app.buttons[AX.summarySet(1)].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.buttons[AX.summarySet(1)].label, firstBefore,
                          "the tapped card must take the new number")
        XCTAssertEqual(app.buttons[AX.summarySet(2)].label, secondBefore,
                       "correcting set one must not touch set two")
        XCTAssertEqual(app.buttons[AX.summarySet(3)].label, thirdBefore,
                       "…nor set three, which is the defect this screen exists for")
    }
}
