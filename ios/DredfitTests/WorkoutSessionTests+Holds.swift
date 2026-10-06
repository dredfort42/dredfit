import XCTest
import DredfitCore
@testable import Dredfit

/// Holds: the count-in, the clock, Stop, the side switch and the summary a
/// hold movement ends on. The hands-free run and the declared time have
/// files of their own (+HoldRun, +DeclaredTime).
extension WorkoutSessionTests {

    func holdFlow(_ pattern: Pattern, in session: Session? = nil) throws -> (WorkoutSession, AppStore) {
        let store = makeStore()
        let flow = makeFlow(store, session: session ?? holdSession())
        flow.declineWarmup()
        flow.exIndex = try index(of: pattern, in: flow)
        signals.events.removeAll()
        return (flow, store)
    }

    /// A set at the plan is written as nothing at all, so a test that has to
    /// see what the clock ran declares a time off the plan first.
    func declare(_ seconds: Int, on flow: WorkoutSession) {
        flow.startDeclaringHoldTime()
        flow.adjustValue = seconds
        flow.commitSetEdit()
    }

    func testAHoldCountsInThenRunsAndRecordsWhatTheClockRan() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(20, on: flow)
        flow.startHold()
        XCTAssertTrue(flow.holdCountingIn)
        XCTAssertEqual(flow.holdCountInClock.remaining, GetReady.countInSeconds)
        XCTAssertFalse(flow.holding)

        run(flow, for: GetReady.countInSeconds)
        XCTAssertTrue(flow.holding)
        XCTAssertEqual(flow.holdClock.remaining, 20)

        run(flow, for: 20)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [20])
        XCTAssertEqual(flow.holdMeasured[0], 20)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go, .tick, .tick, .tick, .done])
    }

    func testAHoldThatRanOutWhileAwayIsCreditedInFull() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(20, on: flow)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds)
        clock += 3_600
        flow.tick()
        XCTAssertEqual(flow.actuals[.coreAntiExt], [20],
                       "a hold that ran to the end of its clock counts as held, whatever came after")
    }

    func testACountInThatEndedOutOfEarshotStartsOver() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        clock += 30
        flow.tick()
        XCTAssertTrue(flow.holdCountingIn, "a go nobody could hear must not start a plank")
        XCTAssertEqual(flow.holdCountInClock.remaining, GetReady.countInSeconds)
        XCTAssertFalse(flow.holding)
    }

    func testACountInThatStartsOverIsPrimedAgain() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        clock += 30
        signals.primes = 0
        flow.tick()
        XCTAssertTrue(flow.holdCountingIn, "the premise")
        XCTAssertEqual(signals.primes, 1, "the absence that ended the first count-in let the engine go cold")
        run(flow, for: GetReady.countInSeconds)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(signals.primes, 1, "one prime per 3-2-1")
    }

    func testAStopInsideTheMisTapGraceHandsTheSetBack() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 2)
        flow.stopHoldEarly()
        XCTAssertFalse(flow.holding)
        XCTAssertEqual(flow.holdClock.remaining, 15, "the set stands at its full length again")
        XCTAssertNil(flow.actuals[.coreAntiExt])
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.setIndex, 0)
    }

    func testAStopPastTheGraceIsRecordedAsAnEstimate() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        let expected = SetFacts.snap(Double(SetFacts.holdEndedByTap(heldSeconds: 10)), unit: .hold)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [expected])
        XCTAssertTrue(flow.holdApproxSets.contains(0), "a number the app guessed at says so")
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
    }

    func testTheSecondSideRunsForWhatTheFirstSideRan() throws {
        let (flow, _) = try holdFlow(.coreRot)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        let firstSide = SetFacts.holdEndedByTap(heldSeconds: 10)
        XCTAssertTrue(flow.holdSwitchPausing)
        XCTAssertEqual(flow.firstSideHeld, firstSide)
        XCTAssertEqual(signals.tones.last, .switchSides)

        run(flow, for: Cooldown.switchPauseSeconds)
        XCTAssertTrue(flow.holding)
        XCTAssertEqual(flow.holdTotal, SetFacts.holdSideSeconds(planned: 15, firstSideHeld: firstSide))

        let secondSide = flow.holdTotal
        run(flow, until: { !flow.holding })
        XCTAssertEqual(flow.actuals[.coreRot],
                       [SetFacts.snap(Double(min(secondSide, firstSide)), unit: .hold)],
                       "one set of a per-side hold is the smaller of its two sides")
        XCTAssertFalse(flow.holdSecondSide)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
    }

    func testTheLastHoldOfAMovementEndsOnItsSummary() throws {
        let (flow, store) = try holdFlow(.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(store.pendingWorkout?.atExerciseSummary, true)
        XCTAssertEqual(signals.tones.last, .done, "the end sounds where the effort stopped")

        signals.events.removeAll()
        flow.leaveExerciseSummary()
        XCTAssertEqual(flow.phase, .rest(seconds: flow.exercise.restExerciseSec))
        XCTAssertTrue(flow.holdMeasured.isEmpty)
        XCTAssertEqual(signals.tones, [], "the summary's Done confirms numbers; the end already sounded")
    }

    /// On the plank the engine itself hands out with a probe, neither working
    /// set can be skipped on its own: the skip would leave fewer sets than
    /// the shared floor, so the work screen offers "Skip exercise" instead and
    /// the tap takes the whole movement. The probe's Done opens the movement's
    /// summary, whose last card is the one a person may correct, under a line
    /// saying what the clock saw — a lone skip of the last working set would
    /// put a set no clock ran on that card.
    ///
    /// The engine's own floor for this exercise is one, the probe holding the
    /// slot's other set. The skip rule reads the shared floor of two; read
    /// from the exercise, it would offer exactly that skip.
    func testTheEnginesProbingPlankOffersNoSkipOfALastWorkingSet() throws {
        // Session 2 carries the plank. On its ceiling, journalled there and
        // below the top of its ladder, it is offered a probe.
        var state = EngineState.initial
        state.counter = 1
        state.doses[.coreAntiExt] = Dose.hold.max
        state.shown[.coreAntiExt] = [1: Dose.hold.max]
        let (flow, _) = try holdFlow(.coreAntiExt, in: Engine.generateSession(state))
        XCTAssertEqual(flow.exercise.sets, 2)
        XCTAssertEqual(flow.totalSets, 3)
        XCTAssertEqual(flow.exercise.setsFloor, 1, "the engine's floor, which the skip rule must not read")

        XCTAssertFalse(flow.skipsLeaveAMovement(1), "set one: \"Skip this set\" is not offered")
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + Dose.hold.max)
        flow.skipRest()
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertFalse(flow.skipsLeaveAMovement(1), "set two: \"Skip this set\" is not offered")
        flow.skipSet()
        XCTAssertTrue(flow.skippedPatterns.contains(.coreAntiExt), "the tap takes the whole movement")
        XCTAssertNotEqual(flow.exercise.pattern, .coreAntiExt,
                          "the flow is past the movement: its probe, and the summary the probe opens, never come")
    }

    func testFinishNowOnTheSummaryCountsEverySetOfTheMovementDone() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(flow.phase, .exerciseSummary)
        flow.finishNow()
        XCTAssertNil(flow.setsSkipped[.coreAntiExt],
                     "every set is behind and on the screen — none of them was skipped")
        XCTAssertFalse(flow.skippedPatterns.contains(.coreAntiExt))
        XCTAssertNil(flow.interruptedPattern)
    }

    /// A set a thumb ended at 33 s on the clock records 30, the clock less the
    /// reach allowance, and the line above its panel names that number as the
    /// estimate it is. A correction does not change who ended the set, so the
    /// line says the same after one — "the clock saw 30 s" would pass the
    /// estimate off as a measurement. The card's "≈" stands while the card
    /// carries the thumb's number: OK on it keeps the mark, a number of the
    /// person's own takes it off.
    func testACorrectedSetStoppedByHandIsNotPassedOffAsTheClocksCount() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        declare(45, on: flow)
        flow.setIndex = 2
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 33)
        flow.stopHoldEarly()
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [15, 15, 30], "33 s on the clock less the 3 s reach")
        let estimate = String(localized: "set \(3) · stopped by hand at about \(30) s")

        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.summaryPanelLine(set: 2), estimate)
        XCTAssertTrue(flow.summaryCardIsApproximate(set: 2))

        flow.commitSummaryEdit(set: 2)   // OK on the number as it stands
        XCTAssertTrue(flow.summaryCardIsApproximate(set: 2), "the card still carries the thumb's number")
        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.summaryPanelLine(set: 2), estimate)

        flow.adjustValue = 35   // one "+" on the panel's five-second grid
        flow.commitSummaryEdit(set: 2)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [15, 15, 35])
        XCTAssertFalse(flow.summaryCardIsApproximate(set: 2), "the card carries the person's number now")
        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.summaryPanelLine(set: 2), estimate, "the clock saw neither 30 nor 35")
    }

    /// A per-side set whose first side a thumb ended is marked as an estimate
    /// before it has recorded anything. A second side stopped inside the
    /// mis-tap grace hands the set back with "Skip this set" live, and a set
    /// skipped from there records nothing — its card on the summary shows the
    /// number it falls back to, and must not print "≈ · stopped by hand" over
    /// it. A set that did record an estimate keeps its mark through the skip.
    func testASkippedSetLeavesNoEstimateOnTheSummary() throws {
        let (flow, _) = try holdFlow(.coreRot)
        // Set one: a thumb ends the first side, the clock the second.
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 10)
        flow.stopHoldEarly()
        run(flow, until: { flow.phase != .work })
        flow.skipRest()

        // Set two: a thumb ends the first side, the second is handed back.
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 5)
        flow.stopHoldEarly()
        run(flow, for: Cooldown.switchPauseSeconds + 2)
        flow.stopHoldEarly()
        XCTAssertTrue(flow.holdSecondSide, "the grace handed the second side back")
        flow.skipSet()

        // Set three runs on the clock to the summary.
        flow.startHold()
        run(flow, until: { flow.phase == .exerciseSummary })
        XCTAssertTrue(flow.summaryCardIsApproximate(set: 0), "set one recorded an estimate")
        XCTAssertFalse(flow.summaryCardIsApproximate(set: 1), "set two recorded nothing")
    }

    func testTheSummaryCorrectsOnlyTheCardThatWasTapped() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.setIndex = 2
        flow.actuals[.coreAntiExt] = [15, 15]
        flow.startHold()
        run(flow, for: GetReady.countInSeconds + 15)
        flow.startSummaryAdjusting(set: 0)
        XCTAssertNil(flow.editing, "only the last card opens the panel")
        flow.startSummaryAdjusting(set: 2)
        XCTAssertEqual(flow.editing, .summaryCard(2))
        flow.adjustValue = 20
        flow.commitSummaryEdit(set: 2)
        XCTAssertEqual(flow.actuals[.coreAntiExt], [15, 15, 20])
        XCTAssertNil(flow.editing)
    }

    // MARK: - What a Stop records

    /// `ticks` seconds of the running hold pass the way the view's timer runs
    /// them, then `plus` more with no tick — where a thumb lands — and Stop is
    /// tapped. Returns the figure the last tick put on the button, read before
    /// the gap: the button is drawn on the tick, and a figure read at the tap
    /// would agree with a record taken off the live clock by moving with it.
    private func tapStop(_ flow: WorkoutSession, afterTicks ticks: Int,
                         plus: TimeInterval) -> Int? {
        run(flow, for: ticks)
        let named = flow.holdStopRecords
        clock += plus
        flow.stopHoldEarly()
        return named
    }

    /// The figure on the button moves only on a tick, and the clock does not
    /// wait for one: seven tenths past the tick it is nearer the next second
    /// than the one the button names, and a tick that comes late leaves the
    /// button more than a second behind it.
    func testAStopBetweenTwoTicksStoresTheFigureTheButtonNamed() throws {
        for gap in [0.7, 1.2] {
            let (flow, _) = try holdFlow(.coreAntiExt)
            flow.startHold()
            run(flow, for: GetReady.countInSeconds)
            let named = try XCTUnwrap(tapStop(flow, afterTicks: 10, plus: gap))
            XCTAssertEqual(flow.holdMeasured[0], named, "\(gap) s past the tick")
        }
    }

    /// On the tick itself: on the whole second, and on a tick the timer
    /// delivered late, as it does when the main thread is busy — that one
    /// puts the clock's ROUNDED second on the button, a second more than a
    /// truncated clock would store.
    func testAStopOnATickStoresTheFigureThatTickPutOnTheButton() throws {
        for late in [0.0, 0.6] {
            let (flow, _) = try holdFlow(.coreAntiExt)
            flow.startHold()
            run(flow, for: GetReady.countInSeconds + 10)
            clock += late
            flow.tick()
            let named = try XCTUnwrap(tapStop(flow, afterTicks: 0, plus: 0))
            XCTAssertEqual(flow.holdMeasured[0], named, "a tick \(late) s late")
        }
    }

    /// A plain "Stop" is the grace, even with the clock already past its
    /// three seconds: the tap does what the button says, and it names nothing.
    func testAStopWhileTheButtonNamesNoFigureStoresNothing() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds)
        XCTAssertNil(tapStop(flow, afterTicks: 3, plus: 0.5), "the button names no figure")
        XCTAssertEqual(flow.holdClock.remaining, 15, "the set stands at its full length again")
        XCTAssertNil(flow.actuals[.coreAntiExt])
        XCTAssertTrue(flow.holdApproxSets.isEmpty)
        XCTAssertEqual(flow.phase, .work)
    }

    /// The first side's figure is what the second side runs for, and the
    /// second side's is what the set stores. Declared at 30 s so both figures
    /// stand clear of the five-second floor, where a second more or less
    /// would not show.
    func testEachSideOfAPerSideHoldStoresTheFigureItsButtonNamed() throws {
        let (flow, _) = try holdFlow(.coreRot)
        declare(30, on: flow)
        flow.startHold()
        run(flow, for: GetReady.countInSeconds)
        let firstSide = try XCTUnwrap(tapStop(flow, afterTicks: 20, plus: 0.7))
        XCTAssertEqual(flow.firstSideHeld, firstSide)

        run(flow, for: Cooldown.switchPauseSeconds)
        XCTAssertTrue(flow.holding, "the second side runs")
        let secondSide = try XCTUnwrap(tapStop(flow, afterTicks: 12, plus: 0.7))
        XCTAssertEqual(flow.holdMeasured[0], secondSide)
    }

    /// A set the hands-free run opened on the rest's own go stops like any
    /// other.
    func testAStopInASetTheRunOpenedStoresTheFigureTheButtonNamed() throws {
        let (flow, _) = try holdFlow(.coreAntiExt)
        flow.startHoldExercise()
        run(flow, for: GetReady.countInSeconds + 15 + 60)
        XCTAssertEqual(flow.setIndex, 1)
        XCTAssertTrue(flow.holding, "the rest's go opened the set")
        let named = try XCTUnwrap(tapStop(flow, afterTicks: 10, plus: 0.7))
        XCTAssertEqual(flow.holdMeasured[1], named)
    }
}
