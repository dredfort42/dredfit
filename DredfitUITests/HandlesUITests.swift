//
//  The athlete's handle, end to end, and the two blocks that ask before they
//  run.
//
//  This file replaced DiscomfortUITests, which walked "Something hurt" through
//  the workout, the rating screen and the resting line on Today. That change
//  then took the two handles that moved VOLUME off the plan — the decision
//  they asked for in advance is taken mid-session now (SetSkipUITests) — and
//  what is left here is the one that changes the movement itself.
//

import XCTest

@MainActor
final class HandlesUITests: XCTestCase {

    private var app: XCUIApplication!

    // `async throws`, and that is the whole fix: a synchronous `setUp()`
    // override inherits XCTestCase's non-isolated declaration whatever the
    // class is annotated with, so touching main-actor `XCUIApplication` from
    // it warned four times per file. Only the async form may add the class's
    // isolation (the precedent is DredfitTests/AppStoreTestCase.swift).
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.seedLaunchArguments()
    }

    /// The one handle left on the plan carries its RESULT rather than a
    /// promise: the name and dose the movement would have after the tap.
    ///
    /// Seeded above the first tier, because that is the whole of when the
    /// handle exists: on a fresh install every movement is in its gentlest
    /// variation and there is nothing below it to offer.
    func testTheEasierHandleNamesTheVariationItWouldGive() {
        app.seedLaunchArguments("--uitest-long-session")
        app.launch()
        let easier = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.easierHandlePrefix)).firstMatch
        XCTAssertTrue(easier.waitForExistence(timeout: 5),
                      "the per-movement variation handle is missing from the plan")
        // "Easier · Knee push-ups · 3×8" — the movement, not the promise.
        XCTAssertTrue(easier.label.contains("·"),
                      "the handle must name what the tap would deliver")
    }

    /// And the two that used to stand beside it are gone. Not a style
    /// preference: they asked the person to predict, before the first set, how
    /// much of the session they had in them — a question that moved to the
    /// work screen, where it is known.
    func testThePlanNoLongerAsksHowLongTodayWillBe() {
        app.launch()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 5))
        for gone in ["session-shorter", "session-full", "start-short", "start-full"] {
            XCTAssertFalse(app.buttons[gone].exists,
                           "\(gone) is still on the plan — it was removed when the decision moved to the work screen")
        }
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fewer-sets-")).count, 0,
            "the per-movement sets handle is still on the plan")
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "more-sets-")).count, 0,
            "the way back from the sets handle is still on the plan")
    }

    /// The trap this asserts is not hypothetical: before `.plain` and
    /// `.borderless` were set, one tap on the empty strip of a plan row pulled
    /// a handle — the announced duration went 35 min to 33 and the control
    /// vanished from under the finger. A List row treats several
    /// default-styled buttons as one control, and the row itself is a button
    /// into the technique sheet.
    ///
    /// Two claims, in this order: an aimless tap on the row changes nothing,
    /// and the row's own affordance still opens the sheet. By coordinate,
    /// because what is being tested is a place on the screen rather than a
    /// control — a query would find the control wherever it went.
    func testATapOnAPlanRowDoesNotPullItsHandle() {
        app.seedLaunchArguments("--uitest-long-session")
        app.launch()
        let minutes = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "exercises")).firstMatch
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        let announced = minutes.label

        let handles = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.easierHandlePrefix))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5))
        let handle = handles.firstMatch.frame
        let promise = handles.firstMatch.label
        // The row's own right edge, taken from a plan card: the list has
        // insets of its own, and the screen's edge is not the row's. ANY card
        // will do — they share a width — but it has to be a card, which is why
        // this asks by identifier rather than for `element(boundBy: 0)`: the
        // settings button is an overlay above the tab content, and nothing
        // orders it against the rows underneath.
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.planRowPrefix)).firstMatch.frame

        // The strip to the RIGHT of the handle, derived from the two frames
        // rather than from a fixed inset: the handle sits on the left of its
        // row and its label is a whole sentence, so where the empty part of
        // the row begins depends on the name of the movement. A button answers
        // a few points outside the frame it reports, so the tap goes to the
        // middle of the strip and never to its edge.
        let empty = (handle.maxX + row.maxX) / 2
        XCTAssertGreaterThan(row.maxX - handle.maxX, 60,
                             "no empty strip to tap — the check would prove nothing")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: empty, dy: handle.midY))
            .tap()

        XCTAssertEqual(minutes.label, announced,
                       "a tap on the row's empty strip rewrote the plan")
        XCTAssertEqual(handles.firstMatch.label, promise,
                       "a tap at x=\(empty) on the row's empty strip (handle ends at "
                       + "\(handle.maxX), row at \(row.maxX)) pulled the handle beside it")

        // A row above the handle is the card itself — that one does open.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 60, dy: handle.minY - 34))
            .tap()
        XCTAssertTrue(app.staticTexts[AX.techniqueLife].waitForExistence(timeout: 5),
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
        app.buttons[AX.startWorkout].tap()
        let offer = app.buttons[AX.warmupStart]
        XCTAssertTrue(offer.waitForExistence(timeout: 5),
                      "the workout must open on the warm-up offer")
        XCTAssertFalse(app.staticTexts[AX.getReadyCountdown].exists,
                       "nothing may be counting down before the block is agreed to")
        XCTAssertFalse(app.staticTexts[AX.warmupCountdown].exists,
                       "the warm-up must not have started itself")
        offer.tap()
        XCTAssertTrue(app.staticTexts[AX.getReadyCountdown].waitForExistence(timeout: 5),
                      "saying yes must open the block on its first transition")
    }

    /// …and the other answer is a real one: straight to the work, with nothing
    /// recorded against the person for arriving already warm.
    func testTheWarmUpCanBeDeclined() {
        app.launch()
        app.buttons[AX.startWorkout].tap()
        let skip = app.buttons[AX.warmupIntroSkip]
        XCTAssertTrue(skip.waitForExistence(timeout: 5),
                      "the offer must carry a way past it")
        skip.tap()
        XCTAssertTrue(app.buttons[AX.exerciseDone].waitForExistence(timeout: 5),
                      "declining the warm-up must lead straight to the first exercise")
    }

    /// The cool-down is offered, not started — and the same screen lets it be
    /// declined.
    func testTheCoolDownAsksBeforeItStarts() {
        // Five movements skipped and the sixth actually performed: the block
        // is drawn from what was DONE, so a workout of pure skips has nothing
        // to stretch and is never asked the question at all.
        app.seedLaunchArguments("--uitest-fast")
        app.launch()
        app.buttons[AX.startWorkout].tap()
        let skipWarmup = app.buttons[AX.warmupIntroSkip]
        if skipWarmup.waitForExistence(timeout: 5) { skipWarmup.tap() }
        for _ in 0..<5 {
            // The escape asks before it acts (SkipConfirmation.swift), so the
            // helper is what walks it: control tap, then the answer.
            XCTAssertTrue(WorkoutDriver(app: app).skip(control: AX.exerciseSkip, timeout: 10),
                          "the work screen never came up")
        }

        // The last movement is walked to its end by the driver; the question
        // comes after it. A private copy of that loop is what this file used
        // to carry, and the drift it invites had already cost six red nightly
        // runs once.
        let rating = app.staticTexts["How did it go?"]
        XCTAssertTrue(WorkoutDriver(app: app).walkToCooldownOffer(deadline: 180),
                      "the work must end on the cool-down question"
                        + (rating.exists ? " — it reached the rating instead" : ""))
        XCTAssertTrue(app.buttons[AX.cooldownIntroSkip].exists,
                      "the question must be answerable both ways")
        XCTAssertFalse(app.staticTexts[AX.cooldownCountdown].exists,
                       "nothing may be counting down before the block is agreed to")
        app.buttons[AX.cooldownIntroSkip].tap()
        XCTAssertTrue(rating.waitForExistence(timeout: 5),
                      "declining the cool-down goes to the rating")
    }
}
