import XCTest
import DredfitCore
@testable import Dredfit

/// What survives a backgrounded phone and a process death, and the two
/// guided blocks with their pause.
extension WorkoutSessionTests {

    // MARK: - Restoring after a process death

    func testARestorePicksUpInsideARestStillRunning() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        clock += 10
        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertEqual(flow.restClock.remaining, 50)
        XCTAssertEqual(flow.awaySec, 0, "a rest running on schedule is training, not absence")
    }

    func testARestRestoredInItsLastHalfSecondStillEnds() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        clock += 59.7
        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .rest(seconds: 60))
        XCTAssertEqual(flow.restClock.remaining, 0)
        run(flow, for: 1)
        XCTAssertEqual(flow.phase, .work, "the rest ends instead of hanging on 0")
        XCTAssertEqual(flow.setIndex, 1)
    }

    func testARestoreAfterTheRestRanOutLandsOnTheNextSetAndCountsTheAbsence() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        clock += 60 + 300
        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.setIndex, 1, "the advance the timer would have made")
        XCTAssertEqual(flow.awaySec, 300, "measured from the end of the rest, not from the last write")
    }

    func testARestorePastTheLastSetsRestOpensTheNextMovementWithoutItsDeclaration() throws {
        let store = makeStore()
        let first = makeFlow(store, session: holdSession())
        first.declineWarmup()
        let index = try index(of: .coreAntiExt, in: first)
        XCTAssertLessThan(index, first.exercises.count - 1, "a movement must follow it")
        first.exIndex = index
        first.holdDeclared = 45
        first.setIndex = 2
        first.completeSet()
        XCTAssertEqual(first.phase, .exerciseSummary)
        first.leaveExerciseSummary()
        let snapshot = try XCTUnwrap(store.pendingWorkout)
        XCTAssertEqual(snapshot.holdDeclaredSec, 45)

        clock += 600
        let flow = makeFlow(store, session: holdSession(), resume: snapshot)
        XCTAssertEqual(flow.exIndex, index + 1)
        XCTAssertEqual(flow.setIndex, 0)
        XCTAssertNil(flow.holdDeclared, "the declaration belongs to the movement behind")
    }

    func testARestoreFromTheCoolDownLandsOnTheRating() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.exIndex = first.exercises.count - 1
        first.setIndex = 2
        first.completeSet()
        XCTAssertEqual(first.phase, .cooldownIntro)
        let snapshot = try XCTUnwrap(store.pendingWorkout)

        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .feedback)
    }

    func testTheSummaryOfAFinishedHoldSurvivesAProcessDeath() throws {
        let store = makeStore()
        let first = makeFlow(store, session: holdSession())
        first.declineWarmup()
        first.exIndex = try index(of: .coreAntiExt, in: first)
        first.setIndex = 2
        first.startHold()
        run(first, for: GetReady.countInSeconds + 15)
        XCTAssertEqual(first.phase, .exerciseSummary)

        let flow = makeFlow(store, session: holdSession(), resume: try XCTUnwrap(store.pendingWorkout))
        XCTAssertEqual(flow.phase, .exerciseSummary)
        XCTAssertEqual(flow.holdMeasured[2], 15)
    }

    func testKeepingTheWorkoutFromTodayCataloguesItWithoutRunningIt() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.completeSet()
        let snapshot = try XCTUnwrap(store.pendingWorkout)
        tile.started = nil

        let flow = makeFlow(store, resume: snapshot, settle: true)
        XCTAssertEqual(flow.phase, .feedback)
        XCTAssertNil(tile.started, "nothing for the lock screen to describe on the rating")
    }

    // MARK: - An absence the process lived through

    func testAnAbsenceIsSubtractedAndARunningRestIsNot() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.sceneLeft()
        clock += 1_800
        flow.sceneCameBack()
        XCTAssertEqual(flow.awaySec, 1_800)

        flow.completeSet()
        flow.sceneLeft()
        clock += 600
        flow.sceneCameBack()
        XCTAssertEqual(flow.awaySec, 1_800 + 540, "the 60 s rest that was running is training")
    }

    func testOnlyTheFirstLeavingCounts() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.sceneLeft()
        clock += 100
        flow.sceneLeft()
        clock += 100
        flow.sceneCameBack()
        XCTAssertEqual(flow.awaySec, 200)
    }

    // MARK: - The guided blocks

    func testTheWarmUpWaitsToBeAskedAndNoMeansStraightToTheWork() {
        let store = makeStore()
        let flow = makeFlow(store)
        XCTAssertEqual(flow.phase, .warmupIntro)
        XCTAssertEqual(tile.started?.title, String(localized: "WARM-UP"))
        flow.declineWarmup()
        XCTAssertEqual(flow.phase, .work)
        XCTAssertEqual(flow.warmupSec, 0, "a declined block bills nothing")
        XCTAssertEqual(store.pendingWorkout?.warmupSec, 0)
    }

    func testTheWarmUpRunsToTheWorkAndBillsTheTimeItRan() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        XCTAssertEqual(flow.phase, .warmup)
        XCTAssertEqual(flow.warmup.clock.remaining, GetReady.countInSeconds,
                       "a start tap opens on the count-in")
        let ran = run(flow, until: { flow.phase == .work }, limit: 1_000)
        XCTAssertEqual(flow.warmupSec, ran)
        XCTAssertEqual(signals.tones.last, .done)
    }

    func testAWarmUpBoundaryCrossedWhileAwayFreezesTheBlockAndBillsNothingOfIt() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        clock += 600
        flow.tick()
        XCTAssertTrue(flow.blockPause.isHeld)
        XCTAssertEqual(flow.phase, .warmup)
        XCTAssertFalse(flow.warmup.clock.isRunning)
        XCTAssertEqual(flow.warmup.clock.remaining, GetReady.countInSeconds,
                       "frozen on the second it showed")
        XCTAssertEqual(flow.blockPausedSec, 600 - GetReady.countInSeconds)
        XCTAssertTrue(signals.events.contains(.announce(String(localized: "Paused"))))

        clock += 100
        flow.tick()
        XCTAssertTrue(flow.blockPause.isHeld, "a held block has nothing left to run out")
        flow.toggleBlockPause()
        XCTAssertFalse(flow.blockPause.isPaused, "a frozen transition is its own way back in")
        XCTAssertTrue(flow.warmup.clock.isRunning)
        XCTAssertEqual(flow.blockPausedSec, 700 - GetReady.countInSeconds)
    }

    func testAPausedMoveCountsTheAthleteBackInBeforeItRunsOn() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.beginWarmup()
        run(flow, until: { flow.warmup.stage != .getReady })
        run(flow, for: 3)
        let frozen = flow.warmup.clock.remaining
        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isHeld)
        clock += 50
        flow.toggleBlockPause()
        XCTAssertTrue(flow.blockPause.isReentering)
        XCTAssertEqual(flow.blockPause.reentryRemaining, BlockPause.reentrySeconds)

        signals.events.removeAll()
        run(flow, for: BlockPause.reentrySeconds)
        XCTAssertFalse(flow.blockPause.isPaused)
        XCTAssertEqual(flow.warmup.clock.remaining, frozen, "the move picks up the seconds it froze with")
        XCTAssertEqual(flow.warmup.clock.endDate, clock + TimeInterval(frozen))
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .go])
        XCTAssertEqual(flow.blockPausedSec, 50, "the way back in is the block again")
    }

    func testTheCoolDownIsOfferedAfterTheLastSetAndEndsOnTheRating() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        XCTAssertEqual(flow.phase, .cooldownIntro)
        flow.beginCooldown()
        XCTAssertEqual(flow.phase, .cooldown)
        let ran = run(flow, until: { flow.phase == .feedback }, limit: 1_000)
        XCTAssertEqual(flow.cooldownSec, ran)
        XCTAssertEqual(store.pendingWorkout?.cooldownSec, ran, "a process death on the rating keeps it")
        XCTAssertEqual(signals.tones.last, .workoutDone)
        XCTAssertEqual(tile.ended, 1)
        _ = flow.rate(.plan, overrides: [:])
        XCTAssertEqual(store.records.last?.cooldownSec, ran, "the record keeps what the block ran")
    }

    func testDecliningTheCoolDownGoesStraightToTheRating() {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.declineCooldown()
        XCTAssertEqual(flow.phase, .feedback)
        XCTAssertEqual(flow.cooldownSec, 0)
        _ = flow.rate(.plan, overrides: [:])
        XCTAssertEqual(store.records.last?.cooldownSec, 0)
    }

    // MARK: - A cool-down the workout never reached

    /// A block never begun is zero, the same as a declined one. Left nil, the
    /// record reads as one from before the blocks were measured, and both the
    /// Health energy and the history's plan clock charge it the planned
    /// minutes.
    func testFinishNowFromTheWorkRecordsNoCoolDown() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipRest()
        flow.finishNow()
        XCTAssertEqual(store.pendingWorkout?.cooldownSec, 0,
                       "a process death on the rating must not bring the planned minutes back")
        _ = flow.rate(.plan, overrides: [:])
        try assertNoCoolDownBilled(XCTUnwrap(store.records.last))
    }

    /// The zero is written only over nil: whatever ends the workout once the
    /// block has ended by itself must not turn what it ran into nothing.
    func testFinishNowAfterTheCoolDownEndedKeepsWhatItRan() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        let ran = run(flow, until: { flow.phase == .feedback }, limit: 1_000)
        flow.finishNow()
        _ = flow.rate(.plan, overrides: [:])
        XCTAssertEqual(try XCTUnwrap(store.records.last).cooldownSec, ran)
    }

    /// The same interruption recorded twelve hours later from the snapshot the
    /// work wrote: whether the process survived must not decide the cool-down.
    func testAWorkoutAbandonedInTheWorkSettlesWithNoCoolDown() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.completeSet()
        flow.skipRest()
        let snapshot = try XCTUnwrap(store.pendingWorkout)
        XCTAssertNil(snapshot.restEndDate, "on the work screen, not in a rest")
        XCTAssertNil(snapshot.cooldownSec, "the block is still ahead")

        let relaunched = makeStore()
        XCTAssertTrue(relaunched.settleAbandonedWorkout(now: clock + WorkoutSessionStore.forgottenAfter))
        try assertNoCoolDownBilled(XCTUnwrap(relaunched.records.last))
    }

    /// Nothing performed, nothing to stretch: the flow goes to the rating
    /// without offering the block.
    func testAWorkoutOfPureSkipsRecordsNoCoolDown() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        for _ in flow.exercises { flow.leaveExercise() }
        XCTAssertEqual(flow.phase, .feedback)
        _ = flow.rate(.plan, overrides: [:])
        try assertNoCoolDownBilled(XCTUnwrap(store.records.last))
    }

    /// A restore from the offer lands on the rating, where the block can no
    /// longer begin. Left there, by "Finish later" or a process death, and
    /// rated from Today's "Rate the workout", it was never begun.
    func testAWorkoutLeftOnTheCoolDownsOfferIsRatedWithNoCoolDown() throws {
        let store = makeStore()
        let first = makeFlow(store)
        first.declineWarmup()
        first.exIndex = first.exercises.count - 1
        first.setIndex = 2
        first.completeSet()
        XCTAssertEqual(first.phase, .cooldownIntro)
        let snapshot = try XCTUnwrap(store.pendingWorkout)
        XCTAssertEqual(snapshot.cooldownSec, 0, "what a restore from the offer will record")

        let flow = makeFlow(store, resume: snapshot)
        XCTAssertEqual(flow.phase, .feedback)
        _ = flow.rate(.plan, overrides: [:])
        try assertNoCoolDownBilled(XCTUnwrap(store.records.last))
    }

    /// The same offer, recorded by the store twelve hours later.
    func testAWorkoutAbandonedOnTheCoolDownsOfferSettlesWithNoCoolDown() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        XCTAssertEqual(flow.phase, .cooldownIntro)

        let relaunched = makeStore()
        XCTAssertTrue(relaunched.settleAbandonedWorkout(now: clock + WorkoutSessionStore.forgottenAfter))
        try assertNoCoolDownBilled(XCTUnwrap(relaunched.records.last))
    }

    /// Where the zero stops: a snapshot taken inside the cool-down carries no
    /// measurement either, and a block that may be half done stays unknown,
    /// which falls back to its plan, rather than reading as declined.
    func testAWorkoutAbandonedInsideTheCoolDownLeavesItUnmeasured() throws {
        let store = makeStore()
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow, for: 30)

        let relaunched = makeStore()
        XCTAssertTrue(relaunched.settleAbandonedWorkout(now: clock + WorkoutSessionStore.forgottenAfter))
        XCTAssertNil(try XCTUnwrap(relaunched.records.last).cooldownSec)
    }

    /// The record, and what the call both of its readers price it through
    /// makes of it: the Health export's energy and the history's plan clock.
    private func assertNoCoolDownBilled(_ record: WorkoutRecord,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) throws {
        XCTAssertEqual(record.cooldownSec, 0, file: file, line: line)
        let plan = try XCTUnwrap(EnergyEstimate.segments(exercises: XCTUnwrap(record.exercises),
                                                          skipped: record.skipped ?? [],
                                                          warmupSec: record.warmupSec,
                                                          cooldownSec: record.cooldownSec),
                                 file: file, line: line)
        XCTAssertEqual(plan.cooldownSec, 0, "the planned minutes are not billed", file: file, line: line)
    }
}
