//
//  ReleaseSmokeTests.swift
//  DredfitUITests
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
            XCTAssertTrue(app.staticTexts["≈ 33 min · 6 exercises"].exists,
                          "S1: the plan line must read ≈ 33 min · 6 exercises")
            XCTAssertTrue(app.buttons["Start"].exists, "S1: Start is missing")
            XCTAssertTrue(app.buttons["start-short"].exists,
                          "S1: the short-version offer must sit under Start")
        }
    }

    private func s2FullWorkout() {
        XCTContext.runActivity(named: "S2 — full workout to the rating") { _ in
            app.buttons["Start"].tap()
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

    // MARK: - S8: the discomfort report

    /// Its own launch: S1–S6 owns a clean journal, and this row needs one too.
    /// The safety half of the engine is dead code if this button ever stops
    /// reaching the journal, and nothing else in the smoke would notice.
    func testReleaseSmokeDiscomfort() {
        app.launch()
        XCTContext.runActivity(named: "S8 — a painful exercise is reported and rests") { _ in
            app.buttons["Start"].tap()
            let skipWarmup = app.buttons["Skip warm-up"]
            XCTAssertTrue(skipWarmup.waitForExistence(timeout: 5), "S8: no warm-up to skip")
            skipWarmup.tap()

            // The pull slot: in every session, so the rest it earns is real
            // rather than three workouts away.
            for _ in 0..<3 { app.buttons["Skip exercise"].tap() }
            let report = app.buttons["report-discomfort"]
            XCTAssertTrue(report.waitForExistence(timeout: 5),
                          "S8: the report action is missing from the exercise screen")
            report.tap()
            for _ in 0..<2 { app.buttons["Skip exercise"].tap() }

            XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 10),
                          "S8: reporting must end the exercise and reach the rating")
            XCTAssertTrue(app.staticTexts["DISCOMFORT"].exists,
                          "S8: the rating screen must call the report out")

            app.staticTexts["On plan"].tap()
            XCTAssertTrue(app.staticTexts["Workout 1 completed"].waitForExistence(timeout: 10),
                          "S8: the rating must return to Today")

            app.tabBars.buttons["Calendar"].tap()
            let dayNumber = Calendar.current.component(.day, from: .now)
            app.buttons["day-\(dayNumber)"].tap()
            XCTAssertTrue(app.staticTexts["hurt"].waitForExistence(timeout: 5),
                          "S8: the history row must say hurt, not skipped")
        }
    }

    // MARK: - S7: the same first three rows in Russian

    func testReleaseSmokeRussian() {
        app.launchArguments = ["--uitest-reset", "--uitest-fast",
                               "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        XCTContext.runActivity(named: "S7/S1 — холодный старт на чистой установке") { _ in
            XCTAssertTrue(app.staticTexts["Тренировка 1"].waitForExistence(timeout: 10),
                          "S7/S1: русская сборка должна открыться на «Тренировка 1»")
            XCTAssertTrue(app.buttons["Начать"].exists, "S7/S1: кнопка «Начать» не найдена")
            XCTAssertTrue(app.buttons["start-short"].exists,
                          "S7/S1: предложение короткой версии не найдено")
            // The English leak this row exists to catch.
            XCTAssertFalse(app.buttons["Start"].exists,
                           "S7: English «Start» leaked into the Russian build")
            XCTAssertFalse(app.staticTexts["Workout 1"].exists,
                           "S7: English «Workout 1» leaked into the Russian build")
        }

        XCTContext.runActivity(named: "S7/S2 — тренировка целиком до оценки") { _ in
            app.buttons["Начать"].tap()
            let skipWarmup = app.buttons["Пропустить разминку"]
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
