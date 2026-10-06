//
//  The hold-timer walks (plank, per-side holds, and the pull-up bar hang), in
//  a file of their own to keep DredfitUITests.swift under the linter's file
//  and type-body ceilings. Kept together because they share the session-2
//  arrange (`launchIntoSession2AndReachPlank`) and the two hold lengths it can
//  seed. The bar hang lives here rather than with its "Pull-up bar" settings
//  toggle because, once the toggle is flipped, what it walks IS a hold timer
//  — the same shape as the plank and per-side tests above it.
//
//  THE HOLD LENGTH IS SEEDED AT LAUNCH, not typed on the screen. The two
//  lengths the suite needs are the ends of the corridor: `--uitest-hold-short`
//  (the floor, to walk a whole hold exercise inside a test's budget) and
//  `--uitest-hold-long` (the ceiling, to give a mid-hold Stop a margin no
//  loaded runner can eat). The pre-effort entry is typed only by the tests
//  whose subject is a declared time.
//

import XCTest

// MARK: - Hold timer
extension DredfitUITests {

    /// Session 2 via --uitest-session2 (session 1 seeded as completed
    /// "yesterday"), skipped to the plank — the first hold exercise.
    ///
    /// WITH the reset, through `seedLaunchArguments` rather than an assigned
    /// argument list. The seed clears the engine state and the journal by
    /// itself, so a test behind this helper that lost the reset would stay
    /// green on its predecessor's leftovers — silently, and settings survive a
    /// seed.
    func launchIntoSession2AndReachPlank(_ seeds: String...) {
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

    /// One tap buys the whole hold exercise — every set after the first
    /// starts on its rest's own go, and the phone is not touched again until
    /// the movement is over: nobody lying on the floor between sets has to
    /// reach for it.
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
        // is what the one tap bought: count-in, hold, rest, hold, rest …
        let done = app.buttons[AX.exerciseDone]
        XCTAssertTrue(done.waitForExistence(timeout: 90),
                      "the exercise did not run itself to its last set")
        XCTAssertTrue(app.element(withIdentifier: AX.summaryHeld).exists,
                      "nothing on screen says the hold is behind")
        XCTAssertFalse(app.buttons[AX.holdStartExercise].exists,
                       "the exercise was started once — it must not ask again")
        // The correction comes AFTER the effort, never before it — and the
        // screen it comes on carries every set of the movement that was done,
        // not only the last one (#220); the last card is the one that takes it.
        XCTAssertTrue(app.buttons[AX.summarySet(1)].exists,
                      "the first set must be on the summary too — the screen "
                        + "carries every set that was done, not only the last")
        coordinateTap(done)
        XCTAssertTrue(app.buttons[AX.summarySet(1)].waitForNonExistence(timeout: 10),
                      "the logged movement did not leave the summary")
    }

    /// A SET THE RUN OPENS HAS NO COUNT-IN OF ITS OWN. The rest before it
    /// counts its own last seconds down and ends on the go, and that go is the
    /// hold's start signal — one signal, not two.
    ///
    /// A second 3-2-1 and a second go on top of the rest would stretch a
    /// minute between sets past the minute and announce one set twice. The
    /// minute IS the travel time.
    ///
    /// Without --uitest-fast, which collapses the rest to a second, and the
    /// rest is let RUN OUT rather than skipped: a skip is a tap, and a tap
    /// still earns its beat — the other half of the rule, below.
    func testASetTheRunOpensStartsOnTheRestsOwnGo() {
        launchIntoSession2AndReachPlank("--uitest-hold-short")
        let stop = app.buttons[AX.holdStop]
        coordinateTap(app.buttons[AX.holdStartExercise])
        XCTAssertTrue(stop.waitForExistence(timeout: 12),
                      "the tapped count-in never handed over to the hold")

        let skipRest = app.buttons[AX.skipRest]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 25),
                      "a hold with sets behind it must start its rest by itself")
        XCTAssertTrue(skipRest.waitForNonExistence(timeout: 120), "the rest never ended")
        // A second count-in would hold "Get ready" on the screen, which is
        // what this catches the moment the rest is over.
        XCTAssertFalse(app.staticTexts["Get ready"].exists,
                       "the set the run opened was counted in a second time")
        XCTAssertTrue(stop.waitForExistence(timeout: 5),
                      "the hold did not start on the rest's own go")
    }

    /// The other half of the same rule: a rest CUT SHORT by Skip is somebody
    /// saying they are ready, and that tap earns the beat every start tap
    /// earns (`GetReady.countInSeconds`) — the hold must not land under the
    /// thumb that skipped the rest.
    func testARestCutShortByATapStillCountsThePersonIn() {
        launchIntoSession2AndReachPlank("--uitest-hold-short")
        let stop = app.buttons[AX.holdStop]
        coordinateTap(app.buttons[AX.holdStartExercise])
        XCTAssertTrue(stop.waitForExistence(timeout: 12),
                      "the tapped count-in never handed over to the hold")

        let skipRest = app.buttons[AX.skipRest]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 25),
                      "a hold with sets behind it must start its rest by itself")
        coordinateTap(skipRest)
        XCTAssertTrue(app.staticTexts["Get ready"].waitForExistence(timeout: 5),
                      "a tap earns the beat between saying it and being counted in")
        XCTAssertTrue(stop.waitForExistence(timeout: 15),
                      "the count-in never handed over to the hold")
    }

    /// The rest of a hands-free run is the one screen of the work phase whose
    /// clock acts on its own, so it is the one that can be frozen. Without the
    /// pause there is no way to stop it: answer the door during a hold
    /// exercise and the next set runs without you.
    ///
    /// The window is longer than the whole rest on purpose. A shorter one
    /// would pass whether the pause worked or not — the set was never due
    /// inside it.
    func testTheRestOfAHandsFreeRunCanBeFrozen() {
        launchIntoSession2AndReachPlank("--uitest-hold-short")
        let stop = app.buttons[AX.holdStop]
        coordinateTap(app.buttons[AX.holdStartExercise])
        XCTAssertTrue(stop.waitForExistence(timeout: 12),
                      "the tapped count-in never handed over to the hold")

        let pause = app.buttons[AX.blockPause]
        XCTAssertTrue(pause.waitForExistence(timeout: 25),
                      "a rest that starts the next set must offer a way to stop it")
        coordinateTap(pause)
        let resume = app.buttons[AX.blockResume]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "the pause did not take")

        XCTAssertFalse(stop.waitForExistence(timeout: 75),
                       "a frozen rest started the next set anyway")
        XCTAssertTrue(app.buttons[AX.skipRest].exists, "the rest left the screen while frozen")

        coordinateTap(resume)
        XCTAssertTrue(pause.waitForExistence(timeout: 5),
                      "Resume did not hand the clock back")
    }

    // MARK: - Stopping a hold

    /// An early stop past the grace records what was held, and the number
    /// carries onto the sets after it. The exercise runs itself on past the
    /// stop, so the number is read where it stands once the movement is
    /// behind: on its summary.
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

        // a real early stop (past the grace) records the held seconds. The grace
        // lasts while the button names no figure: until the tick at four seconds.
        coordinateTap(app.buttons[AX.holdStart])
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 4.5)
        XCTAssertTrue(coordinateTap(stop),
                      "the countdown ended before the stop could be delivered")
        // Set one of several: the stop closes it, and the exercise carries on
        // by itself — rest, then the remaining sets, each of them running the
        // FIVE seconds this one reported rather than the plan.
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

    /// The control names the figure it will write, so the two to four
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
        // corridor's five-second floor. Slept rather than raced — the hold is
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
        // "exists" long before the side plank's work screen is up.
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
    /// separates them with room to spare — a second side that ran the planned
    /// 90 would time this out.
    func testTheSecondSideRunsWhatTheFirstSideRan() {
        launchIntoSession2AndReachPlank("--uitest-hold-long")
        let perSideCaption = app.staticTexts["seconds per side"]
        skipExercises(until: perSideCaption, limit: 2)
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 3),
                      "the per-side hold must follow the plank in session 2")

        coordinateTap(app.buttons[AX.holdStartExercise])
        let stop = app.buttons[AX.holdStop]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no Stop during the count-in")
        // Past the mis-tap grace, which ends on the tick at four seconds, so this is a real early stop.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(coordinateTap(stop), "the first side ended before the stop landed")

        XCTAssertTrue(app.staticTexts["Switch sides"].waitForExistence(timeout: 10),
                      "an early stop on the first side must still open the switch pause")

        // NOTHING is tapped from here on, deliberately. Brushing Stop inside
        // the mis-tap grace and pressing the start button again, to cover the
        // retake path, HEALS the defect this test exists for: `startHold`
        // recomputes the length correctly, so a broken switch-pause would not
        // show. A test that repairs its own subject on the way to the
        // assertion is worse than no test. The retake's decision is pinned at
        // unit level instead (`SetFacts.holdSideSeconds`).
        XCTAssertTrue(app.buttons[AX.skipRest].waitForExistence(timeout: 30),
                      "the second side must run the first side's seconds, not the plan's")
    }

    // MARK: - Pull-up bar hang

    func testBarWorkoutFlowsToRating() {
        // 90 s of hang so the stop below is not raced by the app's own
        // countdown — this test has lost that race on the nightly. WITH
        // --uitest-fast: a hold exercise runs itself, so the rests it opens
        // are the auto-run's business rather than screens for this walk to
        // tap through, and the flag keeps them short. WITH the reset, through
        // `seedLaunchArguments`: an assigned argument list drops it, and the
        // test then stands on whatever the previous test left behind.
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
        Thread.sleep(forTimeInterval: 4.5)   // past the grace, which ends on the tick at 4 s
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
        // 15 s and a sentence, not a bare 3 with neither. It is the last
        // screen transition of a walk through six exercises, so it is the
        // assertion a loaded runner reaches with the least margin left — and
        // when it failed on the nightly without a sentence, the whole report
        // was "XCTAssertTrue failed", which says nothing about what was being
        // waited for (I-22).
        XCTAssertTrue(rating.waitForExistence(timeout: 15),
                      "the rating did not arrive after the skip-through and the "
                        + "cool-down question")
        rate(landsOn: "Workout 2 completed")
    }
}
