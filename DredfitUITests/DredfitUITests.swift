//
//  DredfitUITests.swift
//  UI tests of the full feature set. Run on the English locale
//  with clean state (--uitest-reset), except the persistence test.
//
//  Hold-timer tests use --uitest-session2: session 1 is pre-completed
//  "yesterday", so today's workout is session 2, which contains the two
//  hold exercises (plank at #4, side plank at #5) at their 20 s level.
//

import XCTest

@MainActor
final class DredfitUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    // MARK: - Helpers

    // MARK: - Onboarding (v1.4)

    /// The explainer must appear on a genuinely fresh install, and finishing it
    /// must land on Today — not leave the cover stuck over the app.
    func testOnboardingAppearsOnFirstRunAndFinishes() {
        app.launchArguments.append("--uitest-onboarding")
        app.launch()
        XCTAssertTrue(app.staticTexts["Training at home. No questionnaires."]
                        .waitForExistence(timeout: 5),
                      "a first run must open on the onboarding")

        let primary = app.buttons["onboarding-primary"]
        primary.tap()
        XCTAssertTrue(app.staticTexts["It adjusts like a thermostat."]
                        .waitForExistence(timeout: 3), "card 2 is missing")
        primary.tap()
        XCTAssertTrue(app.staticTexts["One tap after the workout."]
                        .waitForExistence(timeout: 3), "card 3 is missing")

        primary.tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3),
                      "finishing the onboarding must reveal Today")
        XCTAssertFalse(app.staticTexts["Training at home. No questionnaires."].exists,
                       "the onboarding must be gone")
    }

    /// Skipping counts as seen: the flag is written and survives a relaunch.
    func testOnboardingSkipIsRememberedAcrossRelaunch() {
        app.launchArguments.append("--uitest-onboarding")
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3),
                      "skipping must land on Today")

        // Relaunch WITHOUT the reset flag so the stored flag is what decides.
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        relaunch.launch()
        XCTAssertTrue(relaunch.buttons["Start"].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunch.staticTexts["Training at home. No questionnaires."].exists,
                       "a skipped onboarding must not come back")
    }

    /// Taps Start and skips the v1.1 warm-up block.
    private func startWorkout() {
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["Skip warm-up"]
        if skipWarmup.waitForExistence(timeout: 3) { skipWarmup.tap() }
    }

    /// Taps an element at the centre of its own frame, bypassing hittability
    /// resolution. Inside the workout's fullScreenCover the CI simulator
    /// sometimes reports degenerate ancestor frames ({inf,inf},{0,0}); walking
    /// them to compute an activation point then fails with "activation point
    /// invalid" even though the control is fully on screen (the failure
    /// screenshots show a pristine rest screen with the button in place). The
    /// button's own leaf frame is valid, so a coordinate tap lands reliably.
    /// This is the reason `.tap()`/`.isHittable`/an isHittable predicate wait
    /// all raise here — every one of them resolves hittability first.
    private func coordinateTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Runs the whole workout: Done on every set, Skip rest on every rest.
    /// Returns control on the "How did it go?" screen.
    private func completeWorkout(adjustFirstExercise: Bool = false) {
        startWorkout()

        if adjustFirstExercise {
            app.buttons["Went differently"].tap()
            let minus = app.buttons["minus"]
            XCTAssertTrue(minus.waitForExistence(timeout: 2), "the stepper did not open")
            minus.tap(); minus.tap(); minus.tap()   // plan 8 → 5
            app.buttons["OK"].tap()
            XCTAssertTrue(app.staticTexts["actual 5"].exists, "the actual marker did not appear")
        }

        let done = app.buttons["Done"]
        let skipRest = app.buttons["Skip rest"]
        let rating = app.staticTexts["How did it go?"]
        // 6 exercises × 3 sets = 18 Done, a rest between each. Coordinate-tap
        // whichever control is present: this loop fires ~35 taps through rapid
        // phase transitions, and a normal `.tap()` hits the fullScreenCover
        // hittability quirk often enough to flake. The 1 s rating poll doubles
        // as the settle between phases.
        var guardCounter = 0
        while !rating.waitForExistence(timeout: 1) && guardCounter < 80 {
            if done.exists {
                coordinateTap(done)
            } else if skipRest.exists {
                coordinateTap(skipRest)
            }
            guardCounter += 1
        }
        XCTAssertTrue(rating.waitForExistence(timeout: 5), "did not reach the rating screen")
    }

    // MARK: - Full pass

    func testFullWorkoutFlowWithAdjustment() {
        app.launch()

        // starting screen: the plan and the button
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 5))
        let start = app.buttons["Start"]
        XCTAssertTrue(start.isHittable, "the Start button is unavailable (covered by the tab bar?)")

        completeWorkout(adjustFirstExercise: true)

        // the rating screen shows the summary of adjustments
        XCTAssertTrue(app.staticTexts["ADJUSTED"].exists, "no actuals summary on the rating screen")
        XCTAssertTrue(app.staticTexts["actual 5"].exists)

        app.staticTexts["Easy, could do more"].tap()

        // done state: no Start button, with the next-workout card
        XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start"].exists, "Start must not show after completion")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Workout 2 ·'")).firstMatch.exists,
            "no next-workout card")
    }

    func testNextWorkoutPreviewHasNoStartButton() {
        app.launch()
        completeWorkout()
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        // next-workout preview
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Workout 2 ·'"))
            .firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Start"].exists, "the preview must not have Start")
        app.buttons["Got it"].tap()
    }

    // MARK: - Technique

    func testTechniqueSheetFromTodayList() {
        app.launch()
        _ = app.staticTexts["Workout 1"].waitForExistence(timeout: 5)
        // tap the first row of the exercise list
        app.buttons.matching(NSPredicate(format: "label CONTAINS '3 ×'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["COMMON MISTAKES"].exists)
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3))
    }

    func testTechniqueSheetDuringWorkout() {
        app.launch()
        startWorkout()
        app.buttons["technique"].tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3))
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
    }

    // MARK: - Exit and data integrity

    func testExitDiscardsWorkout() {
        app.launch()
        startWorkout()
        app.buttons["Done"].tap()          // one set
        app.buttons["Exit"].firstMatch.tap()
        // the workout is not recorded — Start is back in place
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3),
                      "after Exit the workout must not count as completed")
    }

    func testSkipAllExercisesStillReachesRating() {
        app.launch()
        startWorkout()
        for _ in 0..<6 { app.buttons["Skip exercise"].tap() }
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3),
                      "skipping all exercises should lead to the rating")
        // v1.1: the rating screen lists the skipped exercises
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label == 'skipped'")).firstMatch.exists,
            "skipped exercises are not listed on the rating screen")

        // honest skips: even an "easy" rating must not level up untrained patterns
        app.staticTexts["Easy, could do more"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["total level"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0"].exists,
                      "skipped exercises must not raise the level (honest skips)")
    }

    // MARK: - Calendar and history

    func testCalendarShowsHistoryAfterWorkout() {
        app.launch()
        completeWorkout(adjustFirstExercise: true)
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["Completed today ✓"].waitForExistence(timeout: 3))

        // tapping today's (filled) day opens the history
        let day = Calendar.current.component(.day, from: .now)
        app.buttons.matching(NSPredicate(format: "label == '\(day)'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3),
                      "history did not open on the day tap")
        XCTAssertTrue(app.staticTexts["actual 5"].exists, "the actual is not shown in the history")
        app.buttons["Got it"].tap()
    }

    func testCalendarColdStartWhenDoneToday() {
        app.launch()
        completeWorkout()
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        // relaunch WITHOUT a reset — the app should open on the calendar
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        relaunch.terminate()
        relaunch.launch()
        XCTAssertTrue(relaunch.staticTexts["Completed today ✓"].waitForExistence(timeout: 5),
                      "a cold start with a completed workout should open the calendar")
    }

    // MARK: - Progress

    func testProgressReflectsCompletedWorkout() {
        app.launch()
        completeWorkout()
        app.staticTexts["Easy, could do more"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["total level"].waitForExistence(timeout: 3))
        // 6 patterns × (+2) = 12
        XCTAssertTrue(app.staticTexts["12"].exists, "the total level after \"easy\" should be 12")
        // singular form — the catalog's plural variations must be intact
        XCTAssertTrue(app.staticTexts["1 workout"].exists,
                      "\"1 workout\" must use the singular (plural variations lost?)")
    }

    // MARK: - Hold timer (v1.1)

    /// Session 2 via --uitest-session2; skips the three rep exercises
    /// (pull, vertical push, lunges) to land on the plank (a hold, 20 s).
    private func launchIntoSession2AndReachPlank() {
        app.launchArguments = ["--uitest-session2", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 5),
                      "--uitest-session2 must open on workout 2")
        startWorkout()
        for _ in 0..<3 { app.buttons["Skip exercise"].tap() }
        XCTAssertTrue(app.buttons["Start hold"].waitForExistence(timeout: 3),
                      "the hold exercise did not offer the countdown")
    }

    func testHoldTimerEarlyStopCapturesActual() {
        launchIntoSession2AndReachPlank()
        app.buttons["Start hold"].tap()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 2), "no Stop during the countdown")
        stop.tap()   // ~1 s held → rounds to the 5 s minimum
        // an early stop flows into rest, the held seconds became the actual
        let skipRest = app.buttons["Skip rest"]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 3),
                      "an early stop should flow into rest")
        skipRest.tap()
        XCTAssertTrue(app.staticTexts["actual 5"].waitForExistence(timeout: 3),
                      "the held seconds were not recorded as the actual")
    }

    func testHoldTimerAutoAdvancesAtZero() {
        launchIntoSession2AndReachPlank()
        // shorten the hold to the 5 s minimum: 20 → 15 → 10 → 5
        app.buttons["Went differently"].tap()
        let minus = app.buttons["minus"]
        XCTAssertTrue(minus.waitForExistence(timeout: 2), "the stepper did not open")
        minus.tap(); minus.tap(); minus.tap()
        app.buttons["OK"].tap()
        app.buttons["Start hold"].tap()
        // at zero the countdown must advance to rest by itself
        XCTAssertTrue(app.buttons["Skip rest"].waitForExistence(timeout: 9),
                      "the hold did not auto-advance to rest at zero")
    }

    // MARK: - Warm-up (v1.1)

    func testWarmupShowsAndSkips() {
        app.launch()
        app.buttons["Start"].tap()
        XCTAssertTrue(app.staticTexts["WARM-UP"].waitForExistence(timeout: 3),
                      "the workout must open with the warm-up")
        XCTAssertTrue(app.staticTexts["Marching in place"].exists,
                      "the first warm-up move is missing")
        app.buttons["Skip warm-up"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3),
                      "skipping the warm-up must lead to the first exercise")
    }

    // MARK: - Settings (v1.1)

    func testSettingsTogglesRestDay() {
        app.launch()
        // The settings icon overlays every tab — reachable straight from
        // Today (the default landing tab), no detour through Progress.
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["REST DAYS"].waitForExistence(timeout: 3),
                      "the settings sheet did not open")
        // Monday becomes a rest day and back — the chip reacts without errors
        app.buttons["weekday-2"].tap()
        app.buttons["weekday-2"].tap()
        XCTAssertTrue(app.staticTexts["Sounds and haptics"].exists)
        XCTAssertTrue(app.staticTexts["BACKUP"].exists)
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3),
                      "closing settings should return to Today")
    }

    func testSettingsReachableFromEveryTab() {
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["REST DAYS"].waitForExistence(timeout: 3),
                      "settings must open from the Calendar tab too")
        app.buttons["Got it"].tap()

        app.tabBars.buttons["Progress"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["REST DAYS"].waitForExistence(timeout: 3),
                      "settings must open from the Progress tab too")
        app.buttons["Got it"].tap()
    }

    // MARK: - Pull-up bar (v2.2)

    /// Smoke of the bar module end-to-end: the settings toggle flips the
    /// derived session 2 (odd counter) to the vertical pull, the hang runs
    /// as a hold with a working technique sheet, and the flow reaches the
    /// rating screen.
    func testBarWorkoutFlowsToRating() {
        app.launchArguments = ["--uitest-session2", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 5))

        app.buttons["settings"].tap()
        let toggle = app.switches["hasbar-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "no pull-up bar toggle in settings")
        toggle.tap()
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.staticTexts["Bar hang"].waitForExistence(timeout: 3),
                      "with the bar on, session 2 must swap in the bar hang")

        startWorkout()
        // slot 1 — the hang: a bilateral hold with the technique sheet
        XCTAssertTrue(app.buttons["Start hold"].waitForExistence(timeout: 3),
                      "the bar hang must run as a hold exercise")
        app.buttons["technique"].tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3),
                      "the technique sheet must open for a bar exercise")
        app.buttons["Got it"].tap()
        app.buttons["Start hold"].tap()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 2), "no Stop during the hang countdown")
        stop.tap()
        XCTAssertTrue(app.buttons["Skip rest"].waitForExistence(timeout: 3),
                      "the stopped hang must flow into rest")
        coordinateTap(app.buttons["Skip rest"])

        // the rest of the workout is not the point of this smoke — skip through
        let rating = app.staticTexts["How did it go?"]
        for _ in 0..<6 where !rating.exists {
            let skip = app.buttons["Skip exercise"]
            if skip.waitForExistence(timeout: 3) { coordinateTap(skip) }
        }
        XCTAssertTrue(rating.waitForExistence(timeout: 3))
        app.staticTexts["On plan"].tap()
        XCTAssertTrue(app.staticTexts["Workout 2 completed"].waitForExistence(timeout: 5),
                      "the bar workout must complete like any other")
    }

    // MARK: - Persistence across relaunch

    func testStateSurvivesRelaunch() {
        app.launch()
        completeWorkout()
        app.staticTexts["On plan"].tap()
        _ = app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5)

        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        relaunch.terminate()
        relaunch.launch()
        relaunch.tabBars.buttons["Today"].tap()
        XCTAssertTrue(relaunch.staticTexts["Workout 1 completed"].waitForExistence(timeout: 5),
                      "state did not survive the relaunch")
    }
}
