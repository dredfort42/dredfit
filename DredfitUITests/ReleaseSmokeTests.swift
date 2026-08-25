//
//  The Release smoke block of TESTPLAN.md (S1–S7), automated. Row names are
//  carried into activity names and failure messages, so a red run says "S3"
//  and the checklist row is found without translation.
//
//  Still manual: everything marked ⌚ in TESTPLAN (device-only), and the
//  "nothing is clipped" half of S7 — a judgement about pixels, not strings.
//

import XCTest

@MainActor
final class ReleaseSmokeTests: XCTestCase {

    private var app: XCUIApplication!
    private var driver: WorkoutDriver { WorkoutDriver(app: app) }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitest-fast collapses rests, cool-down stages and the get-ready
        // transition (#52); a warm-up MOVE is deliberately not collapsed
        // anywhere in the app, so S2 checks that the block opens and then
        // skips it rather than paying three minutes. That asymmetry is what
        // S2 waits on below: the move's countdown is up for 30 real seconds,
        // the transition's for one, so only the former is safe to assert.
        app.launchArguments = ["--uitest-reset", "--uitest-fast",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
            // A RANGE since v2.27 (§38.3): the full plan and the shortest the
            // session can be made from inside it. Both read back from the
            // reference engine (`estimatedTotalMin` for session 1, at the
            // levels as shipped and with every movement on the sets floor),
            // not copied off the screen: this line is a pin, and a pin taken
            // from the thing it guards guards nothing.
            XCTAssertTrue(app.staticTexts["≈ 26–34 min · 6 exercises"].exists,
                          "S1: the plan line must read ≈ 26–34 min · 6 exercises")
            XCTAssertTrue(app.buttons["Start"].exists, "S1: Start is missing")
            // One Start, and nothing beside it to agree to first: §38 took the
            // short version and the session handle off this screen.
            XCTAssertFalse(app.buttons["start-short"].exists,
                           "S1: the short-version offer is back on the plan")
        }
    }

    private func s2FullWorkout() {
        XCTContext.runActivity(named: "S2 — full workout to the rating") { _ in
            app.buttons["Start"].tap()
            // The block is offered before it runs. S2 says yes — the countdown
            // it asserts below only exists once somebody has.
            let startWarmup = app.buttons["warmup-start"]
            XCTAssertTrue(startWarmup.waitForExistence(timeout: 5),
                          "S2: the warm-up must be offered before it starts")
            startWarmup.tap()
            XCTAssertTrue(app.staticTexts["warmup-countdown"].waitForExistence(timeout: 5),
                          "S2: the workout must open on the warm-up and reach "
                            + "its first move through the get-ready transition")
            let skipWarmup = app.buttons["Skip warm-up"]
            XCTAssertTrue(skipWarmup.exists, "S2: the warm-up must be skippable")
            skipWarmup.tap()

            // skipCooldown: false — S2 names the cool-down, so it runs.
            let walk = driver.completeWorkout(skipCooldown: false)
            XCTAssertTrue(walk.sawCooldown,
                          "S2: the cool-down must run between the last set and the rating")

            app.staticTexts["On plan"].tap()
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 10),
                          "S2: rating must return to Today in the done state")
        }
    }

    private func s3TodayAfterCompletion() {
        XCTContext.runActivity(named: "S3 — Today after completion") { _ in
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].exists,
                          "S3: the done state is missing")
            XCTAssertFalse(app.buttons["Start"].exists,
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
            app.launchArguments = ["--uitest-fast",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
            let today = app.buttons["day-\(dayNumber)"]
            XCTAssertTrue(today.waitForExistence(timeout: 3),
                          "S5: today's cell must be in the grid")
            today.tap()
            XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 5),
                          "S5: the history sheet must open on the workout")
            XCTAssertTrue(app.staticTexts["Total level after: 6"].exists,
                          "S5: the history sheet must list the level the workout ended on")
        }
    }

    private func s6Progress() {
        XCTContext.runActivity(named: "S6 — Progress") { _ in
            // By its own button, not a swipe.
            app.buttons["Got it"].tap()
            app.tabBars.buttons["Progress"].tap()
            XCTAssertTrue(app.staticTexts["level"].waitForExistence(timeout: 5),
                          "S6: the Progress header is missing")
            let total = app.staticTexts["total-level"]
            XCTAssertTrue(total.exists, "S6: the total level is missing")
            XCTAssertEqual(total.label, "6",
                           "S6: six patterns rated \"on plan\" must total 6")
            XCTAssertTrue(app.staticTexts["1 workout"].exists,
                          "S6: the workout count must read \"1 workout\"")
        }
    }

    // MARK: - S8: the honest number

    /// Its own launch: S1–S6 owns a clean journal, and this row needs one too.
    ///
    /// This row used to walk the pain report, on the argument that the safety
    /// half of the engine is dead code if the button stops reaching the
    /// journal. The button is gone and so is that half; the channel that
    /// remains — the honest number — carries the same weight and the same
    /// argument, so the row now walks it.
    func testReleaseSmokeHonestNumber() {
        app.launch()
        XCTContext.runActivity(named: "S8 — an honest number reaches the rating") { _ in
            app.buttons["Start"].tap()
            let skipWarmup = app.buttons["warmup-intro-skip"]
            XCTAssertTrue(skipWarmup.waitForExistence(timeout: 5), "S8: no warm-up to skip")
            skipWarmup.tap()

            // The pull slot: in every session, so the rest it earns is real
            // rather than three workouts away. The pain report is gone from
            // this screen. What the smoke test walks now is the answer that
            // replaced it — the honest number — and it has to reach the rating
            // the same way.
            for _ in 0..<3 {
                let skip = app.buttons["Skip exercise"]
                XCTAssertTrue(skip.waitForExistence(timeout: 10), "S8: no work screen to skip")
                skip.tap()
            }
            let adjust = app.buttons["exercise-adjust"]
            XCTAssertTrue(adjust.waitForExistence(timeout: 5),
                          "S8: the adjust action is missing from the exercise screen")
            adjust.tap()

            // A number BELOW the plan, entered by hand: the one channel leaves
            // for saying the work went differently.
            let minus = app.buttons["minus"]
            XCTAssertTrue(minus.waitForExistence(timeout: 5), "S8: the stepper did not open")
            minus.tap()
            app.buttons["OK"].tap()

            // …and it has to reach the rating from there — through the rest of
            // the work and the cool-down's question, which the driver answers.
            driver.completeWorkout()

            XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 10),
                          "S8: the workout must reach the rating")

            app.staticTexts["On plan"].tap()
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 10),
                          "S8: the rating must return to Today")

            app.tabBars.buttons["Calendar"].tap()
            let dayNumber = Calendar.current.component(.day, from: .now)
            app.buttons["day-\(dayNumber)"].tap()
            XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 5),
                          "S8: the history sheet must open on the workout")
            // This row used to end on the word "hurt". No record written after
            // the wave can carry it — the mark only survives on journal
            // entries older than the wave — so the claim moves to what
            // replaced it: three movements were skipped and the fourth was
            // ANSWERED, and the answer has to reach the journal as work done
            // rather than be lost as a fourth skip.
            let skippedRows = app.staticTexts.matching(
                NSPredicate(format: "label == %@", "skipped"))
            XCTAssertEqual(skippedRows.count, 3,
                           "S8: only the three skipped movements may read skipped")
            XCTAssertFalse(app.staticTexts["hurt"].exists,
                           "S8: the pain mark cannot appear on a record written after v2.26")
        }
    }

    // S9 — the hold-this-level request — is gone with the input it
    // smoke-tested. What it guarded (a per-movement mark reaches the journal,
    // and the smoke would not otherwise notice if it stopped) is covered by
    // S8, the pain report, on the same path.

    // MARK: - S7: the same first three rows in Russian

    func testReleaseSmokeRussian() {
        app.launchArguments = ["--uitest-reset", "--uitest-fast",
                               "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        XCTContext.runActivity(named: "S7/S1 — холодный старт на чистой установке") { _ in
            XCTAssertTrue(app.staticTexts["Тренировка 1"].waitForExistence(timeout: 10),
                          "S7/S1: русская сборка должна открыться на «Тренировка 1»")
            XCTAssertTrue(app.buttons["Начать"].exists, "S7/S1: кнопка «Начать» не найдена")
            // The English leak this row exists to catch.
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
            let technique = app.buttons["technique"]
            XCTAssertTrue(technique.waitForExistence(timeout: 5),
                          "S7/S2: кнопка техники не найдена по идентификатору")
            technique.tap()
            let gotIt = app.buttons["Понятно"]
            XCTAssertTrue(gotIt.waitForExistence(timeout: 5),
                          "S7/S2: шит техники не открылся на русской сборке")
            gotIt.tap()
            XCTAssertTrue(gotIt.waitForNonExistence(timeout: 5),
                          "S7/S2: «Понятно» не закрыло шит техники")

            let walk = driver.completeWorkout(skipCooldown: false, doneLabel: "Готово",
                                              startHoldLabel: "Начать удержание",
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
