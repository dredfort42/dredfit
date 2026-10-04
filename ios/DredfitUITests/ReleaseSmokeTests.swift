//
//  The Release smoke block of TESTPLAN.md (S1–S8), automated. Row names are
//  carried into activity names and failure messages, so a red run says "S3"
//  and the checklist row is found without translation.
//
//  Still manual: S9, the number S8 expects on the history row, everything
//  marked ⌚ in TESTPLAN (device-only), and the "nothing is clipped" half of
//  S7 — a judgement about pixels, not strings.
//

import XCTest

@MainActor
final class ReleaseSmokeTests: XCTestCase {

    nonisolated(unsafe) private var app: XCUIApplication!
    private var driver: WorkoutDriver { WorkoutDriver(app: app) }

    // Synchronous, on purpose: an async setUp kills the CI retries (Apple
    // #108565878). Why, and why `app` is `nonisolated(unsafe)`: DredfitUITests.setUp.
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = MainActor.assumeIsolated {
            let app = XCUIApplication()
            // --uitest-fast collapses rests, cool-down stages and the get-ready
            // transition (#52); a warm-up MOVE is deliberately not collapsed
            // anywhere in the app, so S2 checks that the block opens and then
            // skips it rather than paying three minutes. That asymmetry is what
            // S2 waits on below: the move's countdown is up for 30 real seconds,
            // the transition's for one, so only the former is safe to assert.
            app.seedLaunchArguments("--uitest-fast")
            return app
        }
    }

    // MARK: - S1–S6 in English

    /// One test: S3 has no meaning without S2 having just happened, and S4 is
    /// "the same state, after a relaunch".
    func testReleaseSmokeEnglish() {
        app.launch()
        s1ColdStart()
        s2FullWorkout()
        s3TodayAfterCompletion()
        s4RecordSurvivesRelaunch()
        s5CalendarAndHistory()
        s6Progress()
    }

    private func s1ColdStart() {
        XCTContext.runActivity(named: "S1 — cold start on a fresh install") { _ in
            XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 10),
                          "S1: a fresh install must open Today on Workout 1")
            // The engine's own arithmetic surfaced: if this line drifts, a
            // release-blocking number drifted.
            //
            // A RANGE: the full plan and the shortest the session can be
            // made from inside it. Both read back from the
            // reference engine (`estimatedTotalMin` for session 1, at the
            // levels as shipped and with every movement on the sets floor),
            // not copied off the screen: this line is a pin, and a pin taken
            // from the thing it guards guards nothing.
            // By identifier and then by SPOKEN label: the line carries an
            // accessibility label (a range read as two numbers is not a
            // range), and that label is what a query sees. Both numbers are
            // still pinned, which is the point of the row.
            let planLine = app.staticTexts[AX.planLength]
            XCTAssertTrue(planLine.exists, "S1: the plan line is missing")
            XCTAssertEqual(planLine.label, "about 24 to 32 minutes · 6 exercises",
                           "S1: the plan line must read ≈ 24–32 min · 6 exercises")
            XCTAssertTrue(app.buttons[AX.startWorkout].exists, "S1: Start is missing")
            // One Start, and nothing beside it to agree to first — no short
            // version, no session handle.
            XCTAssertFalse(app.buttons["start-short"].exists,
                           "S1: the short-version offer is back on the plan")
        }
    }

    private func s2FullWorkout() {
        XCTContext.runActivity(named: "S2 — full workout to the rating") { _ in
            app.buttons[AX.startWorkout].tap()
            // The block is offered before it runs. S2 says yes — the countdown
            // it asserts below only exists once somebody has.
            let startWarmup = app.buttons[AX.warmupStart]
            XCTAssertTrue(startWarmup.waitForExistence(timeout: 5),
                          "S2: the warm-up must be offered before it starts")
            startWarmup.tap()
            XCTAssertTrue(app.staticTexts[AX.warmupCountdown].waitForExistence(timeout: 5),
                          "S2: the workout must open on the warm-up and reach "
                            + "its first move through the get-ready transition")
            let skipWarmup = app.buttons[AX.skipWarmup]
            XCTAssertTrue(skipWarmup.exists, "S2: the warm-up must be skippable")
            skipWarmup.tap()

            // skipCooldown: false — S2 names the cool-down, so it runs.
            let walk = driver.completeWorkout(skipCooldown: false)
            XCTAssertTrue(walk.sawCooldown,
                          "S2: the cool-down must run between the last set and the rating")

            app.element(withIdentifier: AX.ratingPlan).tap()
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 10),
                          "S2: rating must return to Today in the done state")
        }
    }

    private func s3TodayAfterCompletion() {
        XCTContext.runActivity(named: "S3 — Today after completion") { _ in
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].exists,
                          "S3: the done state is missing")
            XCTAssertFalse(app.buttons[AX.startWorkout].exists,
                           "S3: Start must not show once the day is done")
            // Kicker uppercases, so the label is "NEXT".
            XCTAssertTrue(app.staticTexts["NEXT"].exists,
                          "S3: the next-workout card is missing")
            // --uitest-reset clears rest days, so the date word is
            // deterministic here.
            XCTAssertTrue(app.staticTexts["Workout 2 · tomorrow"].exists,
                          "S3: the next card must name workout 2 and when it lands")
        }
    }

    private func s4RecordSurvivesRelaunch() {
        XCTContext.runActivity(named: "S4 — the record survives a relaunch") { _ in
            app.terminate()
            // Deliberately WITHOUT the reset, and the call says so by name:
            // what S4 is about is the record on disk surviving a cold start.
            app.storedStateLaunchArguments("--uitest-fast")
            app.launch()
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 10),
                          "S4: a cold start must still open Today in its completed state")
        }
    }

    private func s5CalendarAndHistory() {
        XCTContext.runActivity(named: "S5 — Calendar and history") { _ in
            app.tabBars.buttons["Calendar"].tap()
            XCTAssertTrue(app.staticTexts["Completed today ✓"].waitForExistence(timeout: 5),
                          "S5: the calendar must mark today as completed")

            let dayNumber = Calendar.current.component(.day, from: .now)
            let today = app.buttons[AX.day(dayNumber)]
            XCTAssertTrue(today.waitForExistence(timeout: 3),
                          "S5: today's cell must be in the grid")
            today.tap()
            XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 5),
                          "S5: the history sheet must open on the workout")
            // The LINE, not a number. The value is the engine's, pinned
            // bit-for-bit by the golden fixture; asserting it again here only
            // means a UI test goes red whenever early progression changes.
            let level = app.staticTexts.element(
                matching: NSPredicate(format: "label BEGINSWITH %@", "Total steps after:"))
            XCTAssertTrue(level.waitForExistence(timeout: 5),
                          "S5: the history sheet must list the steps the workout ended on")
        }
    }

    private func s6Progress() {
        XCTContext.runActivity(named: "S6 — Progress") { _ in
            // By its own button, not a swipe.
            app.buttons[AX.historyDone].tap()
            app.tabBars.buttons["Progress"].tap()
            XCTAssertTrue(app.staticTexts["steps"].waitForExistence(timeout: 5),
                          "S6: the Progress header is missing")
            let total = app.staticTexts[AX.totalSteps]
            XCTAssertTrue(total.exists, "S6: the total level is missing")
            // A NUMBER, not a particular one — the same reason as S5: what the
            // number should be is the engine's business and the golden
            // fixture's.
            XCTAssertNotNil(Int(total.label),
                            "S6: the header must carry the total level as a number")
            XCTAssertTrue(app.staticTexts["1 workout"].exists,
                          "S6: the workout count must read \"1 workout\"")
        }
    }

    // MARK: - S8: the honest number

    /// Its own launch: S1–S6 owns a clean journal, and this row needs one too.
    ///
    /// It walks the honest number, on the argument that the part of the
    /// engine that reads it is dead code if the entry stops reaching the
    /// journal.
    func testReleaseSmokeHonestNumber() {
        app.launch()
        XCTContext.runActivity(named: "S8 — an honest number reaches the rating") { _ in
            app.buttons[AX.startWorkout].tap()
            let skipWarmup = app.buttons[AX.warmupIntroSkip]
            XCTAssertTrue(skipWarmup.waitForExistence(timeout: 5), "S8: no warm-up to skip")
            skipWarmup.tap()

            // The fourth movement is the pull slot, which every session
            // carries. What this row walks on it is the honest number, and it
            // has to reach the rating.
            for _ in 0..<3 {
                // The escape asks before it acts (SkipConfirmation.swift).
                XCTAssertTrue(driver.skip(control: AX.exerciseSkip, timeout: 10),
                              "S8: no work screen to skip")
            }
            let adjust = app.buttons[AX.exerciseAdjust]
            XCTAssertTrue(adjust.waitForExistence(timeout: 5),
                          "S8: the adjust action is missing from the exercise screen")
            adjust.tap()

            // A number BELOW the plan, entered by hand: the channel for saying
            // the work went differently.
            let minus = app.buttons[AX.adjustMinus]
            XCTAssertTrue(minus.waitForExistence(timeout: 5), "S8: the stepper did not open")
            minus.tap()
            app.buttons[AX.adjustConfirm].tap()

            // …and it has to reach the rating from there — through the rest of
            // the work and the cool-down's question, which the driver answers.
            driver.completeWorkout()

            XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 10),
                          "S8: the workout must reach the rating")

            // THE CLAIM OF THIS ROW, and it is made HERE: three movements were
            // skipped and the fourth was ANSWERED, and the answer has to travel
            // as work done rather than be lost as a fourth skip. The rating's
            // summary card carries both halves on one screen — the answered
            // movement with its number, and the skips under their own header —
            // with nothing to scroll to and nothing under a fold.
            //
            // Not in the history sheet, by counting the rows that read
            // "skipped": its movements are a scrolling `List`, so what a query
            // finds there is what FITS, not what was skipped. A line added to
            // the sheet's header or a button to its footer is enough to push a
            // row under the fold and turn S8 red with the journal unchanged.
            XCTAssertTrue(app.staticTexts["SKIPPED"].waitForExistence(timeout: 5),
                          "S8: the rating must list what was set aside under its own header")
            // By LABEL, because the row carries the state itself: the header is
            // a separate element to VoiceOver, so each name is spoken with its
            // own word (FeedbackView). The comma is what keeps this off the
            // "Sets skipped" rows, which end "N of M sets skipped".
            let skips = app.staticTexts.matching(
                NSPredicate(format: "label ENDSWITH %@", ", skipped"))
            XCTAssertEqual(skips.count, 3,
                           "S8: exactly the three skipped movements may reach the rating as skipped")
            // ONE movement carries a number, and it is the one the number was
            // entered for. A run of equal sets prints as "actual N"
            // (`SetFactsLabel`), and an entry carries forward over the sets
            // after it, so that is the shape this walk produces.
            let answered = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "actual "))
            XCTAssertEqual(answered.count, 1,
                           "S8: the hand-entered number must reach the rating as work done, "
                             + "on the one movement it was entered for")
            // One below the plan: a fresh install starts every movement on the
            // bottom of the rep grid (`Dose.swift`, 4…15 by 1) and one tap on
            // the stepper is one rep. A number that came back as the plan's own
            // would mean the entry never landed — which is the whole row.
            XCTAssertEqual(answered.firstMatch.label, "actual 3",
                           "S8: the number that reached the rating must be the one entered")

            app.element(withIdentifier: AX.ratingPlan).tap()
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 10),
                          "S8: the rating must return to Today")

            s8TheRecordReadBack()
        }
    }

    /// The second half of S8: the same workout opened from the calendar, which
    /// is the journal read back rather than the screen that wrote it. Its own
    /// function like every other row here — and the row's body is the shorter
    /// for it.
    private func s8TheRecordReadBack() {
        app.tabBars.buttons["Calendar"].tap()
        let dayNumber = Calendar.current.component(.day, from: .now)
        app.buttons[AX.day(dayNumber)].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 5),
                      "S8: the history sheet must open on the workout")
        // What history has to add is that the record survived the rating and
        // still calls a skip a skip. NOT how many rows say it: the list
        // scrolls, so the number on screen is a fact about layout, and pinning
        // it would only park this row on the next reader's padding change. The
        // bound is the half of that count that is about the journal: no
        // movement may read "skipped" that was not one, and the three that
        // were are counted on the rating screen above.
        let skippedRows = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "skipped"))
        XCTAssertGreaterThanOrEqual(skippedRows.count, 1,
                                    "S8: the sheet opens on the movements that were skipped — "
                                      + "the first of them must still read skipped")
        XCTAssertLessThanOrEqual(skippedRows.count, 3,
                                 "S8: no movement may read skipped but the three that were")
        // Nothing writes the pain mark, so no record this walk writes can
        // carry the word "hurt" — `HistoryRow` prints it only for an older
        // record that holds one.
        XCTAssertFalse(app.staticTexts["hurt"].exists,
                       "S8: the pain mark cannot appear on a record written after the pain channel was removed")
    }

    // MARK: - S7: the same first three rows in Russian

    func testReleaseSmokeRussian() {
        app.seedLaunchArguments("--uitest-fast", locale: .russian)
        app.launch()

        XCTContext.runActivity(named: "S7/S1 — холодный старт на чистой установке") { _ in
            XCTAssertTrue(app.staticTexts["Тренировка 1"].waitForExistence(timeout: 10),
                          "S7/S1: русская сборка должна открыться на «Тренировка 1»")
            XCTAssertTrue(app.buttons["Начать"].exists, "S7/S1: кнопка «Начать» не найдена")
            // The English leak this row exists to catch.
            // By the English LABEL, deliberately: `start-workout` is an
            // identifier and matches in any language, which is the opposite
            // of what this row checks.
            XCTAssertFalse(app.buttons["Start"].exists,
                           "S7: English «Start» leaked into the Russian build")
            XCTAssertFalse(app.staticTexts["Workout 1"].exists,
                           "S7: English «Workout 1» leaked into the Russian build")
        }

        XCTContext.runActivity(named: "S7/S2 — тренировка целиком до оценки") { _ in
            app.buttons["Начать"].tap()
            let skipWarmup = app.buttons["Пропустить разминку"]   // the offer's own
            XCTAssertTrue(skipWarmup.waitForExistence(timeout: 5),
                          "S7/S2: разминка не открылась или её нельзя пропустить")
            skipWarmup.tap()

            // By identifier, not the English word: the sheet has to open on
            // a Russian build too.
            let technique = app.buttons[AX.technique]
            XCTAssertTrue(technique.waitForExistence(timeout: 5),
                          "S7/S2: кнопка техники не найдена по идентификатору")
            technique.tap()
            let gotIt = app.buttons["Понятно"]
            XCTAssertTrue(gotIt.waitForExistence(timeout: 5),
                          "S7/S2: шит техники не открылся на русской сборке")
            gotIt.tap()
            XCTAssertTrue(gotIt.waitForNonExistence(timeout: 5),
                          "S7/S2: «Понятно» не закрыло шит техники")

            // No Russian twins for Done and Start hold: the driver taps both
            // by identifier, which is what an identifier is for.
            let walk = driver.completeWorkout(skipCooldown: false,
                                              ratingLabel: "Как прошло?")
            XCTAssertTrue(walk.sawCooldown, "S7/S2: заминка не отработала")

            app.staticTexts["По плану"].tap()
            XCTAssertTrue(app.staticTexts["Тренировка 1 выполнена"].waitForExistence(timeout: 10),
                          "S7/S2: после оценки «Сегодня» должно быть в состоянии «выполнено»")
        }

        XCTContext.runActivity(named: "S7/S3 — «Сегодня» после завершения") { _ in
            XCTAssertFalse(app.buttons["Начать"].exists,
                           "S7/S3: «Начать» не должно показываться после завершения")
            XCTAssertTrue(app.staticTexts["СЛЕДУЮЩАЯ"].exists,
                          "S7/S3: карточка следующей тренировки не найдена (Kicker поднимает регистр)")
            XCTAssertTrue(app.staticTexts["Тренировка 2 · завтра"].exists,
                          "S7/S3: карточка должна называть тренировку 2 и когда она будет")
            XCTAssertFalse(app.staticTexts["Workout 1 completed"].exists,
                           "S7: английское «Workout 1 completed» просочилось в русскую сборку")
        }
    }
}
