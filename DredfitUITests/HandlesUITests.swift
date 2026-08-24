//
//  The athlete's handles, end to end.
//
//  This file replaces DiscomfortUITests, which walked "Something hurt" through
//  the workout, the rating screen and the resting line on Today. None of that
//  exists: the channel is gone, and what took its place is on the plan rather
//  than inside the workout — pulling a handle regenerates the session and the
//  announced duration together, which is exactly what these walk through.
//

import XCTest

@MainActor
final class HandlesUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// 's headline: the recalculated duration is on screen BEFORE the tap, and
    /// the workout the person gets is the one the button promised.
    func testTheSessionHandleShowsBothNumbersAndDeliversTheSecond() {
        app.launch()
        let shorter = app.buttons["session-shorter"]
        XCTAssertTrue(shorter.waitForExistence(timeout: 5),
                      "the session handle is missing from the plan")
        // "Fewer sets in every movement · 37 → 26 min" — both numbers,
        // and the axis it moves, before agreeing.
        let promise = shorter.label
        XCTAssertTrue(promise.contains("→"),
                      "the handle must show what the session becomes, not just that it shrinks")

        shorter.tap()

        XCTAssertTrue(app.buttons["session-full"].waitForExistence(timeout: 3),
                      "a shortened session must offer the way back")
    }

    /// The way back: "All sets back" restores every set on every movement.
    func testTheFullWorkoutIsReachableAgain() {
        app.launch()
        let shorter = app.buttons["session-shorter"]
        XCTAssertTrue(shorter.waitForExistence(timeout: 5))
        shorter.tap()

        let full = app.buttons["session-full"]
        XCTAssertTrue(full.waitForExistence(timeout: 3))
        full.tap()

        XCTAssertFalse(full.waitForExistence(timeout: 2),
                       "with every set back there is nothing to restore")
    }

    /// The per-movement handles sit on the movement they act on, and the
    /// easier one carries its RESULT rather than a promise.
    func testTheExerciseHandlesActOnTheirOwnMovement() {
        app.launch()
        let fewer = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fewer-sets-")).firstMatch
        XCTAssertTrue(fewer.waitForExistence(timeout: 5),
                      "the per-movement sets handle is missing from the plan")
        fewer.tap()

        let more = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "more-sets-")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 3),
                      "a movement with a set off must offer to put it back")
    }

    /// The trap this asserts is not hypothetical: before `.plain` and
    /// `.borderless` were set, one tap on the empty strip of a plan row took a
    /// set off the plan — the announced duration went 35 min to 33 and the
    /// handle vanished from under the finger. A List row treats several
    /// default-styled buttons as one control, and the row itself is a button
    /// into the technique sheet.
    ///
    /// Two claims, in this order: an aimless tap on the row changes nothing,
    /// and the row's own affordance still opens the sheet. By coordinate,
    /// because what is being tested is a place on the screen rather than a
    /// control — a query would find the control wherever it went.
    func testATapOnAPlanRowDoesNotPullItsHandles() {
        app.launch()
        let minutes = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "exercises")).firstMatch
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        let announced = minutes.label

        let handles = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fewer-sets-"))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5))
        let count = handles.count

        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 40, dy: handles.firstMatch.frame.midY))
            .tap()

        XCTAssertEqual(minutes.label, announced,
                       "a tap on the row's empty strip rewrote the plan")
        XCTAssertEqual(handles.count, count,
                       "a tap on the row's empty strip took a set off a movement")

        // A row above the handle is the card itself — that one does open.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 60, dy: handles.firstMatch.frame.minY - 34))
            .tap()
        XCTAssertTrue(app.staticTexts["technique-life"].waitForExistence(timeout: 5),
                      "the plan row no longer opens the technique sheet")
        XCTAssertEqual(minutes.label, announced,
                       "opening the technique sheet rewrote the plan")
    }

    // MARK: - Offered, not required (both blocks)

    /// The warm-up's own version of the cool-down screen below. The claim is
    /// the ABSENCE of a running block, not the presence of a button: a screen
    /// that merely appeared over a countdown already ticking would pass a
    /// presence check and fail the person.
    func testTheWarmUpAsksBeforeItStarts() {
        app.launch()
        app.buttons["Start"].tap()
        let offer = app.buttons["warmup-start"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5),
                      "the workout must open on the warm-up offer")
        XCTAssertFalse(app.staticTexts["getready-countdown"].exists,
                       "nothing may be counting down before the block is agreed to")
        XCTAssertFalse(app.staticTexts["warmup-countdown"].exists,
                       "the warm-up must not have started itself")
        offer.tap()
        XCTAssertTrue(app.staticTexts["getready-countdown"].waitForExistence(timeout: 5),
                      "saying yes must open the block on its first transition")
    }

    /// …and the other answer is a real one: straight to the work, with nothing
    /// recorded against the person for arriving already warm.
    func testTheWarmUpCanBeDeclined() {
        app.launch()
        app.buttons["Start"].tap()
        let skip = app.buttons["warmup-intro-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5),
                      "the offer must carry a way past it")
        skip.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5),
                      "declining the warm-up must lead straight to the first exercise")
    }

    /// The cool-down is offered, not started — and the same screen lets it be
    /// declined.
    func testTheCoolDownAsksBeforeItStarts() {
        // Five movements skipped and the sixth actually performed: the block
        // is drawn from what was DONE, so a workout of pure skips has nothing
        // to stretch and is never asked the question at all.
        app.launchArguments.append("--uitest-fast")
        app.launch()
        app.buttons["Start"].tap()
        let skipWarmup = app.buttons["warmup-intro-skip"]
        if skipWarmup.waitForExistence(timeout: 5) { skipWarmup.tap() }
        for _ in 0..<5 {
            let skip = app.buttons["Skip exercise"]
            XCTAssertTrue(skip.waitForExistence(timeout: 10), "the work screen never came up")
            skip.tap()
        }

        // The last movement is walked to its end; the question comes after it.
        let driver = WorkoutDriver(app: app)
        let start = app.buttons["cooldown-start"]
        let rating = app.staticTexts["How did it go?"]
        let done = app.buttons["Done"]
        let startHold = app.buttons["Start hold"]
        let deadline = Date.now.addingTimeInterval(180)
        while !start.exists && !rating.exists && Date.now < deadline {
            if done.exists {
                driver.coordinateTap(done)
                _ = done.waitForNonExistence(timeout: 3)
            } else if startHold.exists {
                driver.coordinateTap(startHold)
                _ = startHold.waitForNonExistence(timeout: 3)
            } else {
                _ = start.waitForExistence(timeout: 2)
            }
        }

        XCTAssertTrue(start.exists, "the work must end on the cool-down question")
        XCTAssertTrue(app.buttons["cooldown-intro-skip"].exists,
                      "the question must be answerable both ways")
        XCTAssertFalse(app.staticTexts["cooldown-countdown"].exists,
                       "nothing may be counting down before the block is agreed to")
        app.buttons["cooldown-intro-skip"].tap()
        XCTAssertTrue(rating.waitForExistence(timeout: 5),
                      "declining the cool-down goes to the rating")
    }
}
