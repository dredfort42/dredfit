//
//  The declared hold time and the exercise summary walks, split from
//  DredfitUITests+HoldTimer.swift to keep each file under the linter's file
//  ceiling. They start from the same session-2 arrange as the hold-timer
//  walks, `launchIntoSession2AndReachPlank`, which lives there.
//

import XCTest

// MARK: - The declared time and the exercise summary
extension DredfitUITests {

    /// Opens the pre-effort entry and walks the stepper to `seconds`.
    ///
    /// Reads where the panel OPENED rather than assuming it, and steps in
    /// whichever direction is needed. A helper that only walked up would work
    /// on the plank and never reach a target below the plan — and the panel
    /// opens on the plan, which moves whenever the engine says so.
    private func declareHoldTime(_ seconds: Int) {
        coordinateTap(app.buttons[AX.holdSetTime])
        let plus = app.buttons[AX.adjustPlus]
        XCTAssertTrue(plus.waitForExistence(timeout: 5),
                      "the entry did not open its stepper")
        let target = app.staticTexts["\(seconds) s"]
        // The panel's own value, which is the only static text on the screen
        // that is a bare number of seconds.
        let value = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+ s$")).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5),
                      "the stepper is not showing a value to walk from")
        let opened = Int(value.label.replacingOccurrences(of: " s", with: "")) ?? 0
        let step = opened < seconds ? plus : app.buttons[AX.adjustMinus]
        var taps = 0
        while !target.exists && taps < abs(seconds - opened) + 5 {
            step.tap()
            taps += 1
        }
        XCTAssertTrue(target.exists,
                      "the stepper never reached \(seconds) s from \(opened)")
        app.buttons[AX.adjustConfirm].tap()
    }

    /// THE channel for "more than the plan" on a hold: say so before the
    /// effort, while you are standing up and can reach the phone. The clock
    /// then runs from that number on every set, and what the engine reads is
    /// still what the clock measured.
    func testADeclaredTimeGovernsEverySetAndReachesTheSummary() {
        // 20 is above the plank's own plan, which is what the summary
        // compares each card against — so this walk is the "more than the
        // plan" case, the one the declaration exists for.
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        XCTAssertTrue(app.buttons[AX.holdSetTime].exists,
                      "a hold must let you say how long it will run")

        declareHoldTime(20)
        coordinateTap(app.buttons[AX.holdStartExercise])

        let lastCard = app.buttons[AX.summarySet(3)]
        XCTAssertTrue(lastCard.waitForExistence(timeout: 150),
                      "the exercise did not run itself out at the declared time")
        for set in 1...3 {
            let label = app.buttons[AX.summarySet(set)].label
            XCTAssertTrue(label.contains("20 seconds"),
                          "set \(set) did not run the declared time — got “\(label)”")
        }
        XCTAssertTrue(lastCard.label.contains("planned 15"),
                      "the summary must still compare against the PLAN, not "
                        + "against what was declared")
    }

    /// The declaration belongs to the MOVEMENT, and a skipped set is not the
    /// end of a movement.
    ///
    /// `skipSet` clears the per-side pair so a stale second side cannot cross
    /// into the next set, and that reset must leave the declaration standing:
    /// carried off with it, "hold 20" followed by one skipped set would put
    /// the sets after it back on the plan, with nothing on screen to say the
    /// decision had been undone.
    ///
    /// Asserted on the SUMMARY rather than on a running clock: what the sets
    /// ran at is what they recorded, and a card is a number that has stopped
    /// moving.
    func testADeclaredTimeSurvivesASkippedSet() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        declareHoldTime(20)

        XCTAssertTrue(driver.skip(control: AX.exerciseSkipSet),
                      "a three-set hold must let one set go and still count as trained")
        // The skip hands the exercise back un-run: one tap buys it again.
        let start = app.buttons[AX.holdStartExercise]
        XCTAssertTrue(start.waitForExistence(timeout: 5),
                      "the skip must leave the exercise startable")
        coordinateTap(start)

        let lastCard = app.buttons[AX.summarySet(3)]
        XCTAssertTrue(lastCard.waitForExistence(timeout: 150),
                      "the exercise did not run itself out after the skipped set")
        // Set one was never performed and has no card; the two behind it are
        // the ones the declaration governs.
        for set in 2...3 {
            let label = app.buttons[AX.summarySet(set)].label
            XCTAssertTrue(label.contains("20 seconds"),
                          "set \(set) lost the declared time to the skip — got “\(label)”")
        }
    }

    /// …and it does not outlive the movement either. The ordinary way out of
    /// an exercise is the last set's rest, and the move into the next
    /// movement clears the declaration (`leaveExerciseState`) — or a time set
    /// for the plank would arrive at the side plank and set its clock to a
    /// number nobody asked of that movement (the side plank's own plan is the
    /// bottom of the hold grid, 15 s per side).
    ///
    /// The observation is the pre-effort entry, which opens on
    /// `SetFacts.holdTarget` — the declared time while one stands, the plan
    /// otherwise — so nothing waits on a countdown to read a value that is
    /// already decided. The length seed is not in it: under
    /// `--uitest-hold-short` the clock would run 5 s, while the entry reads
    /// the plan's 15.
    func testADeclaredTimeDoesNotFollowTheMovementItWasSetFor() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        declareHoldTime(20)
        coordinateTap(app.buttons[AX.holdStartExercise])

        let lastCard = app.buttons[AX.summarySet(3)]
        XCTAssertTrue(lastCard.waitForExistence(timeout: 180),
                      "the plank did not run itself out at the declared time")
        coordinateTap(app.buttons[AX.exerciseDone])

        // The side plank follows the plank in session 2, and it is a hold of
        // its own with a plan of its own.
        let perSideCaption = app.staticTexts["seconds per side"]
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 60),
                      "the per-side hold must follow the plank in session 2")
        XCTAssertTrue(app.buttons[AX.holdSetTime].waitForExistence(timeout: 10),
                      "the next hold must open on its own intro screen")
        coordinateTap(app.buttons[AX.holdSetTime])
        let value = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+ s$")).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5),
                      "the entry did not open its stepper")
        XCTAssertEqual(value.label, "15 s",
                       "the side plank's clock opened on the time declared for the "
                         + "PLANK — its own plan is 15 s")
    }

    /// The case nothing after the plan could ever serve: a per-side hold records the
    /// SMALLER of its two sides, so nothing that happens after the plan is met
    /// can raise its number. A declared time can, because both sides run from
    /// it — the same code, with no exception for this shape.
    func testAPerSideHoldTakesADeclaredTimeOnBothSides() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        let perSideCaption = app.staticTexts["seconds per side"]
        skipExercises(until: perSideCaption, limit: 2)
        XCTAssertTrue(perSideCaption.waitForExistence(timeout: 3),
                      "the per-side hold must follow the plank in session 2")

        // Below this movement's plan, deliberately: two sides of three sets
        // at a raised time outlast the test's budget, and what this walk is
        // about is that BOTH SIDES run the declared number at all. The "more
        // than the plan" direction is the plank walk above.
        declareHoldTime(10)
        coordinateTap(app.buttons[AX.holdStartExercise])

        let lastCard = app.buttons[AX.summarySet(3)]
        XCTAssertTrue(lastCard.waitForExistence(timeout: 180),
                      "a per-side hold must reach the summary like any other")
        XCTAssertTrue(lastCard.label.contains("10 seconds"),
                      "both sides must run the declared time — got “\(lastCard.label)”")
    }

    /// A declared time outlives the process dying. Coming back to the plan's
    /// number would undo the decision without saying so.
    func testADeclaredTimeSurvivesTheAppBeingKilled() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        declareHoldTime(20)
        coordinateTap(app.buttons[AX.holdStartExercise])
        XCTAssertTrue(app.buttons[AX.holdStop].waitForExistence(timeout: 15),
                      "the declared hold never started")
        app.terminate()

        let relaunch = XCUIApplication.launchedOnStoredState("--uitest-fast",
                                                            "--uitest-hold-short")
        XCTAssertTrue(relaunch.buttons[AX.resumeContinue].waitForExistence(timeout: 10),
                      "an interrupted workout must offer to be continued")
        relaunch.buttons[AX.resumeContinue].tap()
        // The set is offered again — a hold never restores mid-count — but at
        // the DECLARED length, which is what the summary then records.
        let lastCard = relaunch.buttons[AX.summarySet(3)]
        let start = relaunch.buttons[AX.holdStartExercise]
        if start.waitForExistence(timeout: 10) { driver.coordinateTap(start) }
        XCTAssertTrue(lastCard.waitForExistence(timeout: 180),
                      "the resumed exercise never finished")
        XCTAssertTrue(lastCard.label.contains("20 seconds"),
                      "the declared time did not survive the kill — got "
                        + "“\(lastCard.label)”")
    }

    /// The work screen's writer records the set UNDER WAY and truncates what
    /// follows — correct as it stands, since those sets have not happened —
    /// so it cannot touch set one without deleting sets two and three. The
    /// summary's writer (`SetFacts.recordingSet`) changes one set and leaves
    /// the rest standing.
    ///
    /// Only the LAST card takes a correction, in both directions: every
    /// earlier set ended on its signal or under a thumb and stands as it ran
    /// (`SetFacts.correctionRange`). Those cards are inert rather than open on
    /// a panel with both ends dead, so a tap on the first card opens nothing
    /// and the line under the cards names the last set as the one to correct.
    func testCorrectingOneSetOnTheSummaryLeavesTheOthersStanding() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        coordinateTap(app.buttons[AX.holdStartExercise])

        let first = app.buttons[AX.summarySet(1)]
        XCTAssertTrue(first.waitForExistence(timeout: 90),
                      "the movement did not reach its summary")
        let firstBefore = first.label
        let secondBefore = app.buttons[AX.summarySet(2)].label
        let thirdBefore = app.buttons[AX.summarySet(3)].label

        // Set one: inert — no stepper, the Next time block stays.
        coordinateTap(first)
        let plus = app.buttons[AX.adjustPlus]
        XCTAssertFalse(plus.waitForExistence(timeout: 2), "an earlier set opens no stepper")
        XCTAssertTrue(app.staticTexts[AX.summaryNextPlan].exists,
                      "nothing was opened, so the block did not stand down")

        // Set three: nothing follows it, so both directions are open — and
        // the line above the panel says only what the clock counted.
        let last = app.buttons[AX.summarySet(3)]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        coordinateTap(last)
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "the last card did not open the stepper")
        XCTAssertTrue(plus.isEnabled, "the last set may have been held past the signal")
        for _ in 0..<3 { plus.tap() }
        app.buttons[AX.adjustConfirm].tap()

        XCTAssertTrue(app.buttons[AX.summarySet(3)].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.buttons[AX.summarySet(3)].label, thirdBefore,
                          "the tapped card must take the new number")
        XCTAssertEqual(app.buttons[AX.summarySet(1)].label, firstBefore,
                       "correcting set three must not touch set one")
        XCTAssertEqual(app.buttons[AX.summarySet(2)].label, secondBefore,
                       "…nor set two, which is the defect this screen exists for")

        // Re-opened, the line still names what the CLOCK counted — not the
        // number just typed, read back as if the clock had seen it.
        coordinateTap(app.buttons[AX.summarySet(3)])
        let line = app.element(withIdentifier: "summary-panel-line")
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.hasSuffix("the clock saw 5 s"),
                      "the panel's line must name the clock's number, got “\(line.label)”")
        app.buttons[AX.adjustConfirm].tap()
    }

    /// The addition "for next time" is its own block and its own channel — a
    /// tap on it rewrites the sentence that names the next plan, touches no
    /// card, and reaches the rating as a decision of its own.
    func testAnAdditionForNextTimeRewritesThePlanAndReachesTheRating() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        coordinateTap(app.buttons[AX.holdStartExercise])

        let sentence = app.staticTexts[AX.summaryNextPlan]
        XCTAssertTrue(sentence.waitForExistence(timeout: 90),
                      "the summary must say what the next plan will be")
        let cardsBefore = (1...3).map { app.buttons[AX.summarySet($0)].label }
        let promised = sentence.label
        // The spoken label, which is what `.label` returns for a text that
        // carries one: "+0 s" is what the eye reads.
        XCTAssertEqual(app.staticTexts[AX.raiseValue].label, "plus 0 seconds for next time")

        app.buttons[AX.raisePlus].tap()
        XCTAssertEqual(app.staticTexts[AX.raiseValue].label, "plus 5 seconds for next time")
        XCTAssertNotEqual(sentence.label, promised,
                          "the sentence itself must show the raised plan — "
                            + "not a total beside the stepper")
        XCTAssertEqual((1...3).map { app.buttons[AX.summarySet($0)].label }, cardsBefore,
                       "an addition for next time is not a fact about today")
        app.buttons[AX.raiseMinus].tap()
        XCTAssertEqual(sentence.label, promised, "minus takes the addition back")
        app.buttons[AX.raisePlus].tap()

        // The decision travels: it is listed where the rating is given.
        driver.completeWorkout()
        XCTAssertTrue(app.element(withIdentifier: AX.feedbackRaised("core_anti_ext")).exists,
                      "the rating screen must list the addition, so it is seen to stand")
    }

    /// The "Next time" stepper's target is its whole frame, corners included
    /// — the same defect the panel's "−" was found with on build 22
    /// (`SetFactsUITests.testTheStepperTakesATapAtTheCornerOfItsFrame`, #251),
    /// on the same 44 pt ring, 22 pt in radius. Against a stepper whose hit
    /// shape is the bare ring this is red on its first corner: every tap below
    /// lands at a corner of the 44 pt frame (`WorkoutDriver.corners`), 27 pt
    /// from the centre, the ring takes none of them, and the label never
    /// leaves "plus 0 seconds".
    ///
    /// Each of the eight taps is asserted on its own, because the addition
    /// cannot count to four: `EngineConfig.raiseStepsMax` is 2, so "+" is
    /// dead after two hits and a final value could not tell four hits from
    /// two. The walk climbs to 2 and comes back to 0 twice, with "+" and "−"
    /// each tapped once at every corner, and the label must move on every
    /// tap — a miss anywhere stalls it where the tap before left it.
    func testTheNextTimeStepperTakesATapAtTheCornerOfItsFrame() {
        launchIntoSession2AndReachPlank("--uitest-fast", "--uitest-hold-short")
        coordinateTap(app.buttons[AX.holdStartExercise])

        XCTAssertTrue(app.staticTexts[AX.summaryNextPlan].waitForExistence(timeout: 90),
                      "the summary must say what the next plan will be")
        expectRaised(0, "the summary opens with nothing added")
        let plus = app.buttons[AX.raisePlus]
        let minus = app.buttons[AX.raiseMinus]
        let walk = [
            CornerTap(plus, WorkoutDriver.topLeft, leaves: 1),
            CornerTap(plus, WorkoutDriver.bottomRight, leaves: 2),
            CornerTap(minus, WorkoutDriver.topRight, leaves: 1),
            CornerTap(minus, WorkoutDriver.bottomLeft, leaves: 0),
            CornerTap(plus, WorkoutDriver.topRight, leaves: 1),
            CornerTap(plus, WorkoutDriver.bottomLeft, leaves: 2),
            CornerTap(minus, WorkoutDriver.topLeft, leaves: 1),
            CornerTap(minus, WorkoutDriver.bottomRight, leaves: 0),
        ]
        for tap in walk {
            tap.button.coordinate(withNormalizedOffset: tap.corner).tap()
            expectRaised(tap.leaves,
                         "\(tap.button.identifier) at (\(tap.corner.dx), \(tap.corner.dy)) must take the tap")
        }
    }

    /// One corner tap of the walk above and the addition it must leave.
    private struct CornerTap {
        let button: XCUIElement
        let corner: CGVector
        let leaves: Int

        init(_ button: XCUIElement, _ corner: CGVector, leaves: Int) {
            self.button = button
            self.corner = corner
            self.leaves = leaves
        }
    }

    /// The addition as VoiceOver reads it — `RaiseLabel.spoken`, which is
    /// what `.label` returns for the value — waited for rather than read at
    /// once, so a tap still being delivered is not counted as a miss.
    private func expectRaised(_ steps: Int, _ message: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let spoken = "plus \(steps * 5) seconds for next time"
        let value = app.staticTexts.matching(identifier: AX.raiseValue)
            .matching(NSPredicate(format: "label == %@", spoken)).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 3),
                      "\(message): expected “\(spoken)”, got “\(app.staticTexts[AX.raiseValue].label)”",
                      file: file, line: line)
    }
}
