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
//  R30 moved that last one off the plan as well, into the technique sheet the
//  plan row already opened. So the tests below no longer look for a control
//  under a row: they check that there is none, that the sheet carries it
//  instead — from Today AND from the work screen, which is the door the plan
//  never had — and that the one grey line paying for its discoverability is
//  spent by the first visit and stays spent across a relaunch.
//

import XCTest

@MainActor
final class HandlesUITests: XCTestCase {

    private var app: XCUIApplication!

    /// The two answers to the step-down question, BY LABEL and therefore in
    /// English — an alert's buttons carry no identifier into the accessibility
    /// tree, which is the same constraint `WorkoutDriver.skipConfirmLabel`
    /// lives under. Both queries are scoped to `app.alerts`: the confirm
    /// repeats the verb of the capsule that raised it, so an unscoped query
    /// would match two controls and resolve by tree order.
    private static let confirmSwitch = "Switch"
    private static let keepGoing = "Keep going"

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

    // MARK: - The plan carries no handles at all

    /// The whole claim of R30 in one screen: six rows, six movements, and
    /// nothing under any of them. Asked by PREFIX rather than for one movement,
    /// so a handle that comes back on a single pattern is caught too — and the
    /// row's own affordance is asserted in the same test, because "no control"
    /// is only the right answer while the row is still a door.
    ///
    /// Seeded above the first variation. On a fresh install every movement is
    /// in its gentlest one and there is nothing below it to offer, so the
    /// absence would prove nothing.
    func testThePlanCarriesNoPerMovementHandles() {
        app.seedLaunchArguments("--uitest-long-session")
        app.launch()
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.planRowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.easierHandlePrefix)).count, 0,
            "the per-movement variation handle is back on the plan — it lives in the "
              + "technique sheet now (R30)")

        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons[AX.techniqueStepDown].waitForExistence(timeout: 5),
                      "the row must open the sheet the handle moved into")
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

    // MARK: - The handle, where it lives now

    /// What the block promises is that this sheet becomes the movement it
    /// names, and that the plan follows. Both halves are asserted without
    /// reading a catalog string: the title before, the title after, and the
    /// row's own label — a name the test never has to know.
    func testTheStepBelowSwitchesTheSheetAndThePlanWithIt() {
        app.seedLaunchArguments("--uitest-long-session")
        app.launch()
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.planRowPrefix)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let rowBefore = row.label
        row.tap()

        let title = app.element(withIdentifier: AX.techniqueTitle)
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the sheet did not open")
        let before = title.label
        let switchDown = app.buttons[AX.techniqueStepDown]
        XCTAssertTrue(switchDown.exists,
                      "no step below on a movement seeded at the top of its ladder")
        // "Switch to Bar hang" — the control names the movement, so a
        // VoiceOver user meeting it out of context knows what it does.
        let promise = switchDown.label
        switchDown.tap()

        // It asks first (owner, 01.09.2026): the plan has no undo, and the way
        // back up a ladder is a probe several appearances away.
        let confirm = app.alerts.firstMatch.buttons[Self.confirmSwitch]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "the step down acted without asking")
        confirm.tap()

        let after = title.label
        XCTAssertNotEqual(after, before, "the sheet did not move to the movement below")
        XCTAssertTrue(promise.contains(after),
                      "the button promised \"\(promise)\" and delivered \"\(after)\"")

        app.buttons[AX.techniqueDone].tap()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 5))
        XCTAssertNotEqual(row.label, rowBefore, "the plan kept the movement that was switched away")
        XCTAssertTrue(row.label.contains(after),
                      "the plan row does not carry the movement the sheet delivered")
    }

    /// And the question is a real one: answered with "keep going", the sheet
    /// stays on the movement it was describing and the plan is untouched.
    ///
    /// This is the half that can rot silently. A confirmation whose cancel
    /// still performs the action looks exactly like one that works, because
    /// nobody taps the cancel twice to check.
    func testTheStepBelowCanBeDeclinedAndChangesNothing() {
        app.seedLaunchArguments("--uitest-long-session")
        app.launch()
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.planRowPrefix)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let rowBefore = row.label
        row.tap()

        let title = app.element(withIdentifier: AX.techniqueTitle)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let before = title.label
        app.buttons[AX.techniqueStepDown].tap()

        let keep = app.alerts.firstMatch.buttons[Self.keepGoing]
        XCTAssertTrue(keep.waitForExistence(timeout: 5), "the step down did not ask")
        keep.tap()

        XCTAssertEqual(title.label, before, "declining moved the sheet")
        app.buttons[AX.techniqueDone].tap()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, rowBefore, "declining rewrote the plan anyway")
    }

    /// On the first variation there is nothing below, and the block is ABSENT
    /// rather than present and disabled: a control that cannot act is a control
    /// that has to be read and dismissed every time the sheet is opened.
    func testTheFirstVariationCarriesNoStepBelow() {
        app.launch()
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.planRowPrefix)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts[AX.techniqueLife].waitForExistence(timeout: 5),
                      "the sheet did not open")
        XCTAssertFalse(app.buttons[AX.techniqueStepDown].exists,
                       "a fresh install is on the bottom rung of every ladder — "
                         + "there is nothing below it to offer")
    }

    /// And it is offered on the screen that shows the UPCOMING workout, never
    /// inside a running one (owner, 01.09.2026).
    ///
    /// Not a matter of taste: the session is snapshotted at Start, so a switch
    /// taken mid-workout moves the state under a plan already in flight, and
    /// the rating is applied to the pair. Measured on the engine — squat v6
    /// 3×15 switched to v5 and rated "on plan" writes 15 into the journal of
    /// v5, where the person had shown 4, and a probe passed later in the same
    /// session promotes straight past the rung they had just chosen. Neither is
    /// an engine defect; the two states simply must not move at once.
    func testTheStepBelowIsNotOfferedInsideAWorkout() {
        app.seedLaunchArguments("--uitest-long-session")
        app.launch()
        WorkoutDriver(app: app).startWorkout()
        XCTAssertTrue(app.buttons[AX.exerciseDone].waitForExistence(timeout: 10),
                      "the work screen never came up")
        app.buttons[AX.technique].tap()
        XCTAssertTrue(app.element(withIdentifier: AX.techniqueTitle).waitForExistence(timeout: 5),
                      "the sheet did not open mid-exercise")
        XCTAssertFalse(app.buttons[AX.techniqueStepDown].exists,
                       "the sheet offers a switch while a session generated from the "
                         + "state it would move is in flight")
    }

    // MARK: - The line that pays for it

    /// One grey line is the whole price the plan pays for a handle that is no
    /// longer visible on it, and it is spent by going through the door once —
    /// from any screen. Gated on that rather than on an empty journal, because
    /// the person carried over from v2 has a full one and is exactly who the
    /// sentence is for.
    ///
    /// The relaunch is half the test: a flag kept in memory would read as
    /// "spent" for the rest of the session and come back on the next launch,
    /// which is the same sentence shown twice.
    func testTheTechniqueHintIsSpentByTheFirstSheetAndStaysSpent() {
        app.launch()
        XCTAssertTrue(app.staticTexts[AX.techniqueHint].waitForExistence(timeout: 5),
                      "the plan says nothing about what a row opens")

        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.planRowPrefix)).firstMatch.tap()
        XCTAssertTrue(app.buttons[AX.techniqueDone].waitForExistence(timeout: 5))
        app.buttons[AX.techniqueDone].tap()

        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[AX.techniqueHint].exists,
                       "the hint is still up after the door it describes was used")

        let relaunched = XCUIApplication.launchedOnStoredState()
        XCTAssertTrue(relaunched.buttons[AX.startWorkout].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunched.staticTexts[AX.techniqueHint].exists,
                       "the hint came back on the next launch — the flag never reached the file")
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
