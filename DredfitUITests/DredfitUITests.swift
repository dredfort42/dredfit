//
//  English locale, clean state — and where a walk must instead read back what
//  it just wrote, it says so by name (`launchedOnStoredState`). Both forms
//  live in AccessibilityID.swift because two tests here used to assign
//  `launchArguments` outright and drop --uitest-reset with it.
//

import XCTest

@MainActor
final class DredfitUITests: XCTestCase {

    var app: XCUIApplication!

    // `async throws`, and that is the whole of the fix for sixteen build
    // warnings: a synchronous `setUp()` override inherits XCTestCase's
    // non-isolated declaration whatever the class is annotated with, so
    // main-actor `XCUIApplication` was reached from a non-isolated context.
    // Only the async form may add the class's isolation.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.seedLaunchArguments()
    }

    // Thin wrappers over WorkoutDriver. Internal, not private:
    // DredfitUITests+Cooldown.swift extends this class from another file.
    var driver: WorkoutDriver { WorkoutDriver(app: app) }

    func startWorkout() {
        driver.startWorkout()
    }

    /// Adds seed flags to the clean-state launch `setUp` prepared instead of
    /// replacing it: the two that replaced it lost `--uitest-reset` and ran on
    /// the leftovers of the test before them, which ends mid-workout.
    func seed(_ flags: String...) {
        app.launchArguments.append(contentsOf: flags)
    }

    /// The rating tap and the state it has to land in — the same two lines at
    /// ten call sites, by identifier because the cards are reworded often.
    func rate(_ card: String = AX.ratingPlan, landsOn done: String = "Workout 1 completed") {
        app.element(withIdentifier: card).tap()
        XCTAssertTrue(app.staticTexts[done].waitForExistence(timeout: 5),
                      "the rating must return to Today reading \"\(done)\"")
    }

    /// A workout interrupted mid-rest, then cold-started: the arrange of the
    /// resume tests, which differ only in what they then answer.
    func relaunchOnAnInterruptedWorkout() -> XCUIApplication {
        app.launch()
        startWorkout()
        app.buttons[AX.exerciseDone].tap()          // set 1 done → rest (snapshot written)
        XCTAssertTrue(app.buttons[AX.skipRest].waitForExistence(timeout: 3),
                      "the set has to be logged before the kill, or there is nothing to resume")
        app.terminate()
        let relaunch = XCUIApplication.launchedOnStoredState()
        XCTAssertTrue(relaunch.staticTexts["Continue the workout?"].waitForExistence(timeout: 5),
                      "a fresh interrupted workout must be offered back")
        return relaunch
    }

    /// Opens "Went differently" and hands back the stepper asked for.
    func openAdjuster(_ step: String) -> XCUIElement {
        app.buttons[AX.exerciseAdjust].tap()
        let button = app.buttons[step]
        XCTAssertTrue(button.waitForExistence(timeout: 3), "the stepper did not open")
        return button
    }

    /// Taps the exercise-level skip until `goal` shows, at most `limit` times.
    /// On the GOAL rather than counting taps: the skip keeps its identifier
    /// across exercises, so there is no disappearance edge to confirm one by —
    /// a dropped tap is retried, and over-skipping cannot happen. The wall
    /// clock bounds it as well as the tap count, because an iteration that
    /// finds no skip to tap does not advance the count.
    func skipExercises(until goal: XCUIElement, limit: Int) {
        let skip = app.buttons[AX.exerciseSkip]
        let deadline = Date.now.addingTimeInterval(TimeInterval(limit) * 15)
        var skips = 0
        while !goal.exists && skips < limit && Date.now < deadline {
            if skip.exists { coordinateTap(skip); skips += 1 }
            _ = goal.waitForExistence(timeout: 1)   // settle + goal check
        }
    }

    /// Taps an element at the centre of its own frame, bypassing hittability
    /// resolution — see WorkoutDriver for why this is not `.tap()`, and why
    /// it declines to tap an element that has already left.
    @discardableResult
    func coordinateTap(_ element: XCUIElement) -> Bool {
        driver.coordinateTap(element)
    }

    /// Launch, walk the whole workout, answer the rating: the arrange of
    /// several tests about what Today, the calendar, Progress or a relaunch
    /// look like AFTERWARDS. Not private: DredfitUITests+Resume.swift needs
    /// it too, for the relaunch-after-a-completed-workout tests.
    func walkAWholeWorkout(adjustFirstExercise: Bool = false,
                           rating card: String = AX.ratingPlan) {
        seed("--uitest-fast")
        app.launch()
        completeWorkout(adjustFirstExercise: adjustFirstExercise)
        rate(card)
    }

    /// This wrapper only adds the adjustment step; the walk is the driver's.
    private func completeWorkout(adjustFirstExercise: Bool = false,
                                 deadline: TimeInterval = 420) {
        startWorkout()

        if adjustFirstExercise {
            // Plan 4 → 3. A clean start IS the bottom of the grid (§40.8),
            // so a first-session actual can only be BELOW it — there is no
            // "lower but still on the ladder" number to type here any more.
            openAdjuster(AX.adjustMinus).tap()
            app.buttons[AX.adjustConfirm].tap()
            XCTAssertTrue(app.staticTexts["actual 3"].exists, "the actual marker did not appear")
        }

        // The cool-down has its own test and the release smoke walks it.
        driver.completeWorkout(skipCooldown: true, deadline: deadline)
    }

    // MARK: - Full pass

    func testFullWorkoutFlowWithAdjustment() {
        seed("--uitest-fast")
        app.launch()

        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 5))
        let start = app.buttons[AX.startWorkout]
        XCTAssertTrue(start.isHittable, "the Start button is unavailable (covered by the tab bar?)")

        completeWorkout(adjustFirstExercise: true)

        // The card header states the scope once — the adjusted exercise sits
        // outside it, carrying its own number.
        XCTAssertTrue(app.staticTexts["Your rating applies to 5 of 6"].exists,
                      "no actuals summary on the rating screen")
        XCTAssertTrue(app.staticTexts["actual 3"].exists)

        // The adjusted exercise finished under its planned volume, so the one
        // rating that claims MORE is spent — and says so. The LINE is the
        // assertion, not the card's state: a dimmed card is still in the tree.
        XCTAssertTrue(app.staticTexts["“Easy, could do more” is for a workout done in full."].exists,
                      "no reason given for the rating that is not on offer")

        rate()
        XCTAssertFalse(app.buttons[AX.startWorkout].exists, "Start must not show after completion")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Workout 2 ·'")).firstMatch.exists,
            "no next-workout card")
    }

    func testNextWorkoutPreviewHasNoStartButton() {
        walkAWholeWorkout()

        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Workout 2 ·'"))
            .firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Workout 2"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons[AX.startWorkout].exists, "the preview must not have Start")
        app.buttons[AX.nextWorkoutDone].tap()
    }

    // MARK: - Technique

    func testTechniqueSheetFromTodayList() {
        app.launch()
        _ = app.staticTexts["Workout 1"].waitForExistence(timeout: 5)
        // The first plan row by identifier: "3 ×" is a rendered load — a
        // number format and a locale, not an identity.
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AX.planRowPrefix)).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["COMMON MISTAKES"].exists)
        // The "why" section is always present, below the mistakes.
        XCTAssertTrue(app.staticTexts["IN LIFE"].exists)
        XCTAssertTrue(app.staticTexts[AX.techniqueLife].exists)
        app.buttons[AX.techniqueDone].tap()
        XCTAssertTrue(app.buttons[AX.startWorkout].waitForExistence(timeout: 3))
    }

    func testTechniqueSheetDuringWorkout() {
        app.launch()
        startWorkout()
        app.buttons[AX.technique].tap()
        XCTAssertTrue(app.staticTexts["TECHNIQUE"].waitForExistence(timeout: 3))
        app.buttons[AX.techniqueDone].tap()
        XCTAssertTrue(app.buttons[AX.exerciseDone].waitForExistence(timeout: 3))
    }

    // MARK: - Exit and data integrity

    /// One set logged and the dialog open over it — the arrange of the three
    /// tests below, which differ only in which answer they take.
    ///
    /// No `.firstMatch` on the exit tap any more, and that is a fix rather
    /// than tidying: the header carries TWO controls reading "Exit" — the real
    /// one and a hidden twin balancing the title — so the query was ambiguous
    /// and `.firstMatch` resolved it by tree order. Named now
    /// (`workout-exit`, `workout-exit-spacer`).
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

    /// The dialog's third answer, and the one a person reaches for most: they
    /// changed their mind. Nothing tested it, so a way out that had begun
    /// discarding progress would have gone unnoticed. The claim is that
    /// NOTHING happened — same screen, same progress, the latter proved by
    /// asking again and being asked to confirm again, which only a workout
    /// with something in it is.
    ///
    /// The tap OUTSIDE the dialog, which is the affordance nothing on screen
    /// announces — it stays walked because it stays there.
    ///
    /// Its history is worth keeping straight. As a `confirmationDialog` this
    /// question was presented as an anchored POPOVER, and a popover suppresses
    /// its cancel action, because tapping outside IS the cancel: the declared
    /// `Button("Cancel", role: .cancel)` was drawn nowhere and stood nowhere in
    /// the accessibility tree, so the outside tap was the ONLY way back. That
    /// is what the role-less "Keep training" was added for on 27.08.2026.
    ///
    /// It is an `.alert` now, and an alert does not eat the role — measured the
    /// same day: the node is `Alert`, there is no `Popover` beside it, and every
    /// declared button stood in the tree. So "Keep training" carries the role
    /// itself and there is one escape, not two saying the same thing.
    func test_exitDialog_whenDismissedWithoutAnswering_leavesTheWorkoutExactlyWhereItWas() {
        exitDialogOverOneLoggedSet()
        let dialog = app.alerts["Leave the workout?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3),
                      "exiting over a logged set must ask before it throws the set away")
        // Below the sheet, not above it: measured on iPhone 17 Pro, a tap at
        // dy 0.06 leaves the dialog standing (the dimming layer does not take
        // taps in the safe-area strip) while dy 0.95 dismisses it. Nothing can
        // leak through to the rest screen while the dimming layer is up, and
        // the `skip-rest` assertion below would catch it if it did.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 3),
                      "the question must carry a way back out of itself")
        // Today's controls stay in the tree under the workout cover, so the
        // proof of "still inside" is the rest screen, not the absence of Start.
        XCTAssertTrue(app.buttons[AX.skipRest].exists,
                      "cancelling must leave the rest screen the dialog covered as it was")
        app.buttons[AX.workoutExit].tap()
        XCTAssertTrue(app.buttons["Discard workout"].waitForExistence(timeout: 3),
                      "the set logged before the cancel must still be there — an empty "
                        + "workout is not asked to confirm")
    }

    /// The visible way back out. Before 27.08.2026 the only one was the tap
    /// outside, which nothing on screen mentions — and both buttons that WERE
    /// drawn led out of the workout, one of them destructively. It carries the
    /// `.cancel` role as well now, so the escape gesture and the button people
    /// can see are the same thing.
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

        XCTAssertTrue(app.staticTexts["How did it go?"].waitForExistence(timeout: 3),
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

    // MARK: - Calendar and history

    func testCalendarShowsHistoryAfterWorkout() {
        walkAWholeWorkout(adjustFirstExercise: true)
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["Completed today ✓"].waitForExistence(timeout: 3))

        // By identifier: the label carries the full spoken date and state.
        let day = Calendar.current.component(.day, from: .now)
        app.buttons[AX.day(day)].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3),
                      "history did not open on the day tap")
        XCTAssertTrue(app.staticTexts["actual 3"].exists, "the actual is not shown in the history")
        app.buttons[AX.historyDone].tap()
    }

    // MARK: - Progress

    func testProgressReflectsCompletedWorkout() {
        walkAWholeWorkout(rating: AX.ratingMore)
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["steps"].waitForExistence(timeout: 3))
        // 6 patterns × (+2) = 12, on the identified element. The scale is
        // an ordinal along each ladder now (§40.2); the identifier kept
        // its old name, the CAPTION did not.
        let totalLevel = app.staticTexts[AX.totalSteps]
        XCTAssertEqual(totalLevel.label, "12", "the total level after \"easy\" should be 12")
        XCTAssertTrue(app.staticTexts["1 workout"].exists,
                      "\"1 workout\" must use the singular (plural variations lost?)")
    }

    // MARK: - Warm-up

    func testWarmupShowsAndSkips() {
        // Both transition labels below are asserted while it is on screen — a
        // five-second window at its real length, so it is held open instead.
        seed("--uitest-long-transition")
        app.launch()
        app.buttons[AX.startWorkout].tap()
        XCTAssertTrue(app.staticTexts["WARM-UP"].waitForExistence(timeout: 3),
                      "the workout must open with the warm-up")
        // The block is offered, not started — say yes before walking it.
        app.buttons[AX.warmupStart].tap()
        // Since #52 the block opens on the transition announcing the first
        // move; this label is the one VoiceOver reads.
        XCTAssertTrue(app.staticTexts["Get ready: Marching in place"].exists,
                      "the first warm-up move is missing")
        // one impossible move must not cost the other five
        app.buttons["Skip this move"].tap()
        XCTAssertTrue(app.staticTexts["Get ready: Arm circles"].waitForExistence(timeout: 3),
                      "skipping one move must advance to the next, not exit")
        app.buttons[AX.skipWarmup].tap()
        XCTAssertTrue(app.buttons[AX.exerciseDone].waitForExistence(timeout: 3),
                      "skipping the warm-up must lead to the first exercise")
    }

    // The transition itself has its own suite: GetReadyUITests (issue #52).

    /// The position mini-sheet (issue #34): opens from the warm-up move,
    /// freezes its countdown while it's up, and lets the countdown resume
    /// once the sheet closes.
    func testPositionTechniqueSheetFreezesTheCountdown() {
        // Past the transition and into the move it announced. Nothing here is
        // raced: the block opens on the offer's count-in and hands the move
        // over by itself, with no tap to deliver in a closing window.
        app.launch()
        app.buttons[AX.startWorkout].tap()
        app.buttons[AX.warmupStart].tap()
        XCTAssertTrue(app.staticTexts[AX.getReadyCountdown].waitForExistence(timeout: 5),
                      "the warm-up must open on the transition")
        let countdown = app.staticTexts[AX.warmupCountdown]
        XCTAssertTrue(countdown.waitForExistence(timeout: 10),
                      "the warm-up countdown is missing")

        app.buttons[AX.technique].tap()
        let gotIt = app.buttons[AX.positionTechniqueDone]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 3), "the mini-sheet did not open")
        XCTAssertTrue(app.staticTexts["warm-up · 30 s"].exists, "no block capsule on the sheet")

        // Frozen: the number must not move while the sheet is up.
        let frozen = Int(countdown.label) ?? -1
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(Int(countdown.label), frozen,
                       "the countdown must freeze under the sheet")

        gotIt.tap()
        XCTAssertTrue(gotIt.waitForNonExistence(timeout: 3), "Got it did not close the sheet")
        // Resumed: the number moves again within a few seconds.
        let deadline = Date.now.addingTimeInterval(6)
        var moved = false
        while Date.now < deadline && !moved {
            moved = (Int(countdown.label) ?? frozen) < frozen
            if !moved { Thread.sleep(forTimeInterval: 0.5) }
        }
        XCTAssertTrue(moved, "the countdown must resume after the sheet closes")
    }

    // MARK: - Settings

    /// The chip has to CHANGE STATE, not merely absorb the tap: it used to be
    /// tapped twice with nothing asserted in between, so the test stayed green
    /// through a chip that had stopped doing anything. `isSelected` is the
    /// claim rather than a colour — the chip carries that trait because colour
    /// alone does not reach VoiceOver — and it is asserted on the chip, not on
    /// Today, because whether Monday is today is the calendar's business.
    func testSettingsTogglesRestDay() {
        app.launch()
        // the settings icon overlays every tab — reachable straight from Today
        app.buttons[AX.settings].tap()
        XCTAssertTrue(app.staticTexts["REST DAYS"].waitForExistence(timeout: 3),
                      "the settings sheet did not open")

        let monday = app.buttons[AX.weekday(2)]
        XCTAssertFalse(monday.isSelected, "--uitest-reset clears the rest days")
        monday.tap()
        XCTAssertTrue(monday.isSelected, "the tap must mark Monday as a rest day")

        // Closed and reopened: a chip that only repaints itself is not a
        // setting, and the file is what the plan reads.
        app.buttons[AX.settingsDone].tap()
        app.buttons[AX.settings].tap()
        XCTAssertTrue(monday.waitForExistence(timeout: 3))
        XCTAssertTrue(monday.isSelected, "the rest day must survive closing the sheet")
        monday.tap()
        XCTAssertFalse(monday.isSelected, "tapping again must take the rest day back off")
        app.buttons[AX.settingsDone].tap()
        XCTAssertTrue(app.staticTexts["Workout 1"].waitForExistence(timeout: 3),
                      "closing settings should return to Today")
    }

    func testSettingsReachableFromEveryTab() {
        app.launch()
        for tab in ["Calendar", "Progress"] {
            app.tabBars.buttons[tab].tap()
            app.buttons[AX.settings].tap()
            XCTAssertTrue(app.staticTexts["REST DAYS"].waitForExistence(timeout: 3),
                          "settings must open from the \(tab) tab too")
            app.buttons[AX.settingsDone].tap()
        }
    }

    func testHowItWorksOpensFromSettings() {
        app.launch()
        app.buttons[AX.settings].tap()
        XCTAssertTrue(app.buttons[AX.howItWorks].waitForExistence(timeout: 3),
                      "the explainer row should be the first thing in settings")
        app.buttons[AX.howItWorks].tap()
        XCTAssertTrue(app.staticTexts["Variation and dose"].waitForExistence(timeout: 3),
                      "the explainer did not open")
        for section in ["What your answer does", "Deload", "Rotation",
                        "Weekly rhythm",   // issue #36
                        "Trying the next movement",   // §40.4
                        "Skips", "Why there are no questionnaires"] {
            XCTAssertTrue(app.staticTexts[section].exists,
                          "section \"\(section)\" is missing")
        }

        app.buttons[AX.howItWorksDone].tap()
        XCTAssertTrue(app.staticTexts["REST DAYS"].waitForExistence(timeout: 3),
                      "closing the explainer should return to settings")
    }

}

// An extension rather than more class body, and the reason is a hard gate
// rather than taste: SwiftLint bounds a type's OWN body at 600 lines as an
// error and that body had reached 599. An extension weighs nothing against it
// — splitting the FILE would not have moved the number at all. Same file, so
// every private helper above stays reachable.
extension DredfitUITests {

    // MARK: - About section
    //
    // Was "Pull-up bar" until testBarWorkoutFlowsToRating moved to
    // DredfitUITests+HoldTimer.swift — it is a hold-timer walk in substance
    // (maximiseHold, holdStart/holdStop), and this test is what was left.

    /// Both deliberate ways to leave a review live in settings, so a user
    /// never has to wait for the automatic ask.
    func testAboutSectionOffersBothWaysToRecommend() {
        app.launch()
        app.buttons[AX.settings].tap()
        XCTAssertTrue(app.staticTexts["REST DAYS"].waitForExistence(timeout: 3))
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["ABOUT"].waitForExistence(timeout: 3),
                      "no About section in settings")
        XCTAssertTrue(app.staticTexts["Rate on the App Store"].exists)
        XCTAssertTrue(app.staticTexts["Recommend Dredfit"].exists)
    }

    // MARK: - Rest days

    func testRestDayShowsRestStateInsteadOfALivePlan() {
        app.seedLaunchArguments("--uitest-restday")
        app.launch()
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5),
                      "a rest day must say so on Today")
        XCTAssertFalse(app.buttons[AX.startWorkout].exists,
                       "a rest day must not offer a live workout as the main action")
        XCTAssertTrue(app.buttons[AX.trainAnyway].exists,
                      "rest is a plan, not a lockout — training anyway stays available")
    }

    func testTrainAnywayStartsTheWorkoutOnARestDay() {
        app.seedLaunchArguments("--uitest-restday")
        app.launch()
        XCTAssertTrue(app.buttons[AX.trainAnyway].waitForExistence(timeout: 5))
        app.buttons[AX.trainAnyway].tap()
        XCTAssertTrue(app.buttons[AX.warmupStart].waitForExistence(timeout: 5),
                      "Train anyway must open the workout flow")
    }

    // MARK: - Milestones

    func testMilestoneScreenListsEverythingEarned() {
        app.seedLaunchArguments("--uitest-milestone", "--uitest-fast")
        app.launch()
        XCTAssertTrue(app.staticTexts["Workout 10"].waitForExistence(timeout: 5),
                      "the seeded state should offer the tenth workout")

        // 900 s, not the driver's default 420: this walk is the longest in the
        // suite and spent 205 s of that default on a healthy runner — ×2.05,
        // the thinnest margin anywhere, and the next seed that adds a hold
        // would eat the rest of it in silence.
        completeWorkout(deadline: 900)
        app.element(withIdentifier: AX.ratingPlan).tap()

        XCTAssertTrue(app.staticTexts["WORKOUT #10"].waitForExistence(timeout: 5),
                      "the jubilee row is missing")
        // The seed plants one snapshot record nine weeks back, so the jubilee
        // must carry its "then → now" comparison (issue #26) — built by the
        // real Retrospective path, not stubbed.
        XCTAssertTrue(app.staticTexts.matching(identifier: AX.jubileeRetro).firstMatch.exists,
                      "the jubilee should show the then → now line")
        // Match on the rendered label: Kicker uppercases, so the catalog key
        // ("More volume") and what is on screen deliberately differ.
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label == %@", "MORE VOLUME")).count, 2,
            "both set-band rows should be listed")
        // NO life line here, and that is the rule, not a gap: the line belongs
        // to a NEW VARIATION (issue #25), and both rows above are SET BANDS —
        // since v3 a seed can only plant those, because entering a variation
        // needs a probe passed inside the workout (§40.4). Their kicker says
        // "More volume" since the UI-truth audit (27.08.2026) — it used to
        // say "New variation" over more sets of the same movement, which is
        // the wording BACKLOG had logged. The variation-up row and its life
        // line stay covered by MilestoneTests at unit level.
        XCTAssertEqual(
            app.staticTexts.matching(identifier: AX.milestoneLife).count, 0,
            "a set band is the same ability grown — it carries no life line")

        app.buttons[AX.milestoneDone].tap()
        XCTAssertTrue(app.staticTexts["Workout 10 completed"].waitForExistence(timeout: 5),
                      "Done should return to Today with the workout recorded")
    }

    func testNoMilestoneScreenForAnOrdinaryWorkout() {
        walkAWholeWorkout()
        XCTAssertFalse(app.buttons[AX.milestoneDone].exists,
                       "workout 1 earns nothing and must not show the screen")
    }
}
