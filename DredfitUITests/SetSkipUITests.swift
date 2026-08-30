//
//  The skip that happens DURING the workout, end to end.
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

    // `async throws`: a synchronous `setUp()` override inherits XCTestCase's
    // non-isolated declaration whatever the class is annotated with, so
    // main-actor `XCUIApplication` was reached from a non-isolated context.
    // Only the async form may add the class's isolation.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitest-fast collapses the rests, so walking two sets costs
        // seconds rather than minutes.
        app.seedLaunchArguments("--uitest-fast")
    }

    /// The set is not performed and the next one is up — with no rest in
    /// between, because nothing was done to recover from and the minutes are
    /// the whole point of the tap.
    func testSkippingASetGoesStraightToTheNextOne() {
        app.launch()
        driver.startWorkout()

        XCTAssertTrue(app.staticTexts["set 1 of 3"].waitForExistence(timeout: 10),
                      "the work screen did not come up on the first set")
        let skip = app.buttons[AX.exerciseSkipSet]
        XCTAssertTrue(skip.exists, "the set-level skip is missing from the work screen")
        XCTAssertTrue(driver.skip(.set, control: AX.exerciseSkipSet),
                      "the set-level skip never asked its question")

        XCTAssertTrue(app.staticTexts["set 2 of 3"].waitForExistence(timeout: 5),
                      "the skip did not move on to the next set")
        XCTAssertFalse(app.buttons[AX.skipRest].exists,
                       "a skipped set went through a rest nobody earned")
    }

    /// The exercise-level escape names its own landing. With nothing behind
    /// it, leaving is a skipped MOVEMENT — level frozen, appearance unspent.
    /// With the floor's worth of sets behind it, the rest of them are a cut:
    /// the movement was trained, just less of it.
    func testTheExerciseEscapeNamesWhatItTakes() {
        app.seedLaunchArguments("--uitest-fast", "--uitest-long-session")
        app.launch()
        driver.startWorkout()

        XCTAssertTrue(app.staticTexts["set 1 of 4"].waitForExistence(timeout: 10),
                      "--uitest-long-session must open on a four-set movement")
        XCTAssertTrue(app.buttons[AX.exerciseSkip].exists,
                      "with nothing performed the escape must be the movement itself")
        XCTAssertFalse(app.buttons[AX.exerciseSkipRest].exists,
                       "a movement with nothing behind it has no “rest of the sets”")

        // Two sets behind — the floor. The escape changes what it takes.
        for set in 1...2 {
            let done = app.buttons[AX.exerciseDone]
            XCTAssertTrue(done.waitForExistence(timeout: 10), "set \(set) never offered Done")
            driver.coordinateTap(done)
            _ = app.staticTexts["set \(set + 1) of 4"].waitForExistence(timeout: 10)
        }

        XCTAssertTrue(app.buttons[AX.exerciseSkipRest].waitForExistence(timeout: 5),
                      "two sets in, the escape must offer to take the rest of them")
        XCTAssertFalse(app.buttons[AX.exerciseSkip].exists,
                       "the two escapes must never both stand for the same tap")

        XCTAssertTrue(driver.skip(.remainingSets, control: AX.exerciseSkipRest),
                      "the rest-of-the-sets escape never asked its question")
        XCTAssertTrue(app.staticTexts["2 / 6"].waitForExistence(timeout: 5),
                      "the tap must move on to the next movement")
    }

    /// The number follows the decision. The work screen carries what is
    /// LEFT of the session, and a skipped set takes its minutes off at the
    /// moment of the tap — otherwise the person is skipping sets against a
    /// number that still describes the workout they decided not to do.
    func testTheTimeLeftFallsWithASkippedSet() {
        app.seedLaunchArguments("--uitest-fast", "--uitest-long-session")
        app.launch()
        driver.startWorkout()

        let left = app.staticTexts[AX.timeLeft]
        XCTAssertTrue(left.waitForExistence(timeout: 10),
                      "the work screen must say what is left of the session")
        let before = minutes(in: left.label)
        XCTAssertGreaterThan(before, 40, "a 55-minute session should read as most of one")

        driver.skip(.set, control: AX.exerciseSkipSet)
        XCTAssertTrue(app.staticTexts["set 2 of 4"].waitForExistence(timeout: 5))

        XCTAssertLessThan(minutes(in: app.staticTexts[AX.timeLeft].label), before,
                          "a skipped set bought no minutes on screen")
    }

    /// The label is localized and abbreviated differently per language — the
    /// number is the claim, so the number is what is read out of it.
    private func minutes(in label: String) -> Int {
        Int(label.filter(\.isNumber)) ?? -1
    }

    /// Rule 2 from the person's side: once the plan is down to the floor the
    /// set-level skip is not offered at all. It cannot be recorded as a
    /// skipped set — and doing it quietly as something else, under a word that
    /// promises less, is what the rule exists to prevent.
    func testAtTheFloorTheOnlyWayOutIsTheMovement() {
        app.seedLaunchArguments("--uitest-fast", "--uitest-long-session")
        app.launch()
        driver.startWorkout()

        let skip = app.buttons[AX.exerciseSkipSet]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "no work screen to skip on")
        // Four sets: two can go, and the third would leave a single one.
        driver.skip(.set, control: AX.exerciseSkipSet)
        _ = app.staticTexts["set 2 of 4"].waitForExistence(timeout: 5)
        driver.skip(.set, control: AX.exerciseSkipSet)
        XCTAssertTrue(app.staticTexts["set 3 of 4"].waitForExistence(timeout: 5),
                      "the second skip did not land")

        XCTAssertFalse(skip.exists,
                       "a third skipped set would leave one — it must not be offered")
        XCTAssertTrue(app.buttons[AX.exerciseSkip].exists,
                      "with the sets spent, the way out is the movement, and it says so")
    }

    /// The defect this pair of guards exists for: both escapes are 44 pt
    /// targets 18 pt under the button that LOGS the set, they used to fire on
    /// contact, and a workout has no undo. A brushed thumb took a set — or a
    /// whole movement with every number entered for it — and nothing anywhere
    /// could put it back (owner, 30.08.2026).
    ///
    /// Both halves are asserted, because a confirmation that cannot be
    /// declined is not a confirmation: the question has to stand, and saying
    /// no has to leave the set exactly where it was.
    func testAStraySkipTapAsksBeforeItTakesAnything() {
        app.launch()
        driver.startWorkout()

        let firstSet = app.staticTexts["set 1 of 3"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 10),
                      "the work screen did not come up on the first set")

        driver.coordinateTap(app.buttons[AX.exerciseSkipSet])
        XCTAssertTrue(app.staticTexts["Skip this set?"].waitForExistence(timeout: 5),
                      "the set-level skip took the set without asking")
        app.buttons["Keep going"].tap()
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5),
                      "declining the question still took the set")

        driver.coordinateTap(app.buttons[AX.exerciseSkip])
        XCTAssertTrue(app.staticTexts["Skip this exercise?"].waitForExistence(timeout: 5),
                      "the movement-level escape took the movement without asking")
        app.buttons["Keep going"].tap()
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5),
                      "declining the question still left the movement")

        // …and confirming still works, so the guard did not simply disable
        // the way out.
        XCTAssertTrue(driver.skip(.set, control: AX.exerciseSkipSet))
        XCTAssertTrue(app.staticTexts["set 2 of 3"].waitForExistence(timeout: 5),
                      "a confirmed skip must still move on to the next set")
    }
}
