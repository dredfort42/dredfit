//
//  The skip that happens DURING the workout (spec §38.2), end to end.
//
//  The two handles that used to stand on Today are gone: nobody is asked to
//  decide how long the session will be before standing on the mat. What is
//  walked here is the decision in its new place — the work screen — and the
//  two shapes it takes: one set, or the rest of a movement.
//

import XCTest

@MainActor
final class SetSkipUITests: XCTestCase {

    private var app: XCUIApplication!
    private var driver: WorkoutDriver { WorkoutDriver(app: app) }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitest-fast collapses the rests, so walking two sets costs
        // seconds rather than minutes.
        app.launchArguments = ["--uitest-reset", "--uitest-fast",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// The set is not performed and the next one is up — with no rest in
    /// between, because nothing was done to recover from and the minutes are
    /// the whole point of the tap.
    func testSkippingASetGoesStraightToTheNextOne() {
        app.launch()
        driver.startWorkout()

        XCTAssertTrue(app.staticTexts["set 1 of 3"].waitForExistence(timeout: 10),
                      "the work screen did not come up on the first set")
        let skip = app.buttons["exercise-skip-set"]
        XCTAssertTrue(skip.exists, "the set-level skip is missing from the work screen")
        driver.coordinateTap(skip)

        XCTAssertTrue(app.staticTexts["set 2 of 3"].waitForExistence(timeout: 5),
                      "the skip did not move on to the next set")
        XCTAssertFalse(app.buttons["Skip rest"].exists,
                       "a skipped set went through a rest nobody earned")
    }

    /// The exercise-level escape names its own landing. With nothing behind
    /// it, leaving is a skipped MOVEMENT — level frozen, appearance unspent.
    /// With the floor's worth of sets behind it, the rest of them are a cut:
    /// the movement was trained, just less of it (§38.2 rule 3).
    func testTheExerciseEscapeNamesWhatItTakes() {
        app.launchArguments.append("--uitest-long-session")
        app.launch()
        driver.startWorkout()

        XCTAssertTrue(app.staticTexts["set 1 of 4"].waitForExistence(timeout: 10),
                      "--uitest-long-session must open on a four-set movement")
        XCTAssertTrue(app.buttons["exercise-skip"].exists,
                      "with nothing performed the escape must be the movement itself")
        XCTAssertFalse(app.buttons["exercise-skip-rest"].exists,
                       "a movement with nothing behind it has no “rest of the sets”")

        // Two sets behind — the floor. The escape changes what it takes.
        for set in 1...2 {
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10), "set \(set) never offered Done")
            driver.coordinateTap(done)
            _ = app.staticTexts["set \(set + 1) of 4"].waitForExistence(timeout: 10)
        }

        XCTAssertTrue(app.buttons["exercise-skip-rest"].waitForExistence(timeout: 5),
                      "two sets in, the escape must offer to take the rest of them")
        XCTAssertFalse(app.buttons["exercise-skip"].exists,
                       "the two escapes must never both stand for the same tap")

        driver.coordinateTap(app.buttons["exercise-skip-rest"])
        XCTAssertTrue(app.staticTexts["2 / 6"].waitForExistence(timeout: 5),
                      "the tap must move on to the next movement")
    }

    /// Rule 2 from the person's side: once the plan is down to the floor the
    /// set-level skip is not offered at all. It cannot be recorded as a
    /// skipped set — and doing it quietly as something else, under a word that
    /// promises less, is what the rule exists to prevent.
    func testAtTheFloorTheOnlyWayOutIsTheMovement() {
        app.launchArguments.append("--uitest-long-session")
        app.launch()
        driver.startWorkout()

        let skip = app.buttons["exercise-skip-set"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "no work screen to skip on")
        // Four sets: two can go, and the third would leave a single one.
        driver.coordinateTap(skip)
        _ = app.staticTexts["set 2 of 4"].waitForExistence(timeout: 5)
        driver.coordinateTap(skip)
        XCTAssertTrue(app.staticTexts["set 3 of 4"].waitForExistence(timeout: 5),
                      "the second skip did not land")

        XCTAssertFalse(skip.exists,
                       "a third skipped set would leave one — it must not be offered")
        XCTAssertTrue(app.buttons["exercise-skip"].exists,
                      "with the sets spent, the way out is the movement, and it says so")
    }
}
