//
//  The exit-dialog and data-integrity walks, split from DredfitUITests.swift
//  to keep that file and its class body under the linter's ceilings. They
//  share one private arrange, `exitDialogOverOneLoggedSet`, so it lives here.
//

import XCTest

extension DredfitUITests {

    /// One set logged and the dialog open over it — the arrange of the four
    /// tests below, which differ only in which answer they take.
    ///
    /// No `.firstMatch` on the exit tap, deliberately: the header carries a
    /// second control reading "Exit" — a hidden twin balancing the title — so
    /// both are named (`workout-exit`, `workout-exit-spacer`) and the tap asks
    /// for the real one by name, not by tree order.
    private func exitDialogOverOneLoggedSet() {
        app.launch()
        startWorkout()
        app.buttons[AX.exerciseDone].tap()
        XCTAssertTrue(app.buttons[AX.skipRest].waitForExistence(timeout: 3),
                      "the set has to be logged first, or there is nothing to confirm")
        app.buttons[AX.workoutExit].tap()
    }

    func testExitDiscardsWorkoutAfterConfirmation() {
        exitDialogOverOneLoggedSet()
        let discard = app.buttons["Discard workout"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3),
                      "Exit with progress must ask for confirmation")
        discard.tap()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 3),
                      "after a discard the workout must not count as completed")
    }

    func testExitWithNoProgressNeedsNoConfirmation() {
        app.launch()
        startWorkout()
        app.buttons[AX.workoutExit].tap()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 3),
                      "an empty workout should exit without a dialog")
    }

    /// The stray tap, and what it must NOT cost. A question that can throw a
    /// workout away has to survive being brushed against.
    ///
    /// The question is an `.alert`, and an alert is modal: the tap outside is
    /// swallowed whole. It does not answer the question, and it does not reach
    /// the rest screen underneath. A `confirmationDialog` would invert this:
    /// iOS 26 presents it as an anchored POPOVER, which the tap outside DOES
    /// dismiss, and a popover suppresses its cancel action, so a declared
    /// `Button(role: .cancel)` is drawn nowhere and stands nowhere in the
    /// accessibility tree. The alert's escape is a button a person can SEE,
    /// pinned by the test below — so what this one pins is the other half:
    /// the tap that misses costs nothing.
    func test_exitDialog_aTapOutsideNeitherAnswersItNorReachesTheScreenUnder() {
        exitDialogOverOneLoggedSet()
        let dialog = app.alerts["Leave the workout?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3),
                      "exiting over a logged set must ask before it throws the set away")
        // dy 0.95 is below the alert and over the rest screen it covers — the
        // one place a stray tap could both miss the alert and land on
        // something. Waiting for a non-existence that must NOT arrive, rather
        // than reading `exists` straight after the tap: a dismissal the tap
        // wrongly started would be animating, not instant.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertFalse(dialog.waitForNonExistence(timeout: 2),
                       "a modal question must not be answered by a tap that missed it")
        app.buttons["Keep training"].tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 3),
                      "the visible way back must close the question")
        // Today's controls stay in the tree under the workout cover, so the
        // proof of "still inside" is the rest screen, not the absence of Start.
        XCTAssertTrue(app.buttons[AX.skipRest].exists,
                      "the rest screen the dialog covered must be exactly as it was")
        app.buttons[AX.workoutExit].tap()
        XCTAssertTrue(app.buttons["Discard workout"].waitForExistence(timeout: 3),
                      "the set logged before the stray tap must still be there — an "
                        + "empty workout is not asked to confirm")
    }

    /// The visible way back out: every other answer leads out of the workout,
    /// one of them destructively. It carries the `.cancel` role as well, so
    /// the escape gesture and the button people can see are the same thing.
    func test_exitDialog_keepTrainingIsDrawnAndLeavesTheWorkoutStanding() {
        exitDialogOverOneLoggedSet()
        let keep = app.buttons["Keep training"]
        XCTAssertTrue(keep.waitForExistence(timeout: 3),
                      "the question must offer a VISIBLE way to stay, not only a tap outside")
        keep.tap()

        XCTAssertTrue(app.alerts["Leave the workout?"].waitForNonExistence(timeout: 3),
                      "the way to stay must close the question")
        XCTAssertTrue(app.buttons[AX.skipRest].exists,
                      "staying must leave the rest screen the dialog covered as it was")
        app.buttons[AX.workoutExit].tap()
        XCTAssertTrue(app.buttons["Discard workout"].waitForExistence(timeout: 3),
                      "the set logged before is still there — an empty workout is not asked")
    }

    func testExitCanFinishNowThroughTheRating() {
        exitDialogOverOneLoggedSet()
        let finishNow = app.buttons["Finish now"]
        XCTAssertTrue(finishNow.waitForExistence(timeout: 3))
        finishNow.tap()

        // 15 s, not 3: the rating is the screen a whole workout ends on, and
        // every wait for it stands at the end of a chain of taps. Three
        // seconds is not a check on a loaded runner, it is a coin toss —
        // I-22, and the nightly has now lost this transition twice.
        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 15),
                      "Finish now must lead to the rating screen")
        // "not finished" is the one per-row word that differs from the section
        // header and therefore stays visible.
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'not finished'")).firstMatch.exists,
            "the interrupted exercise must read 'not finished', not 'skipped'")
        XCTAssertTrue(app.staticTexts["SKIPPED"].exists,
                      "the skips section carries its header")

        rate()
    }
}
