//
//  A workout that was trained and never rated. The journal is written by
//  `completeWorkout` alone, whose only caller is the tap on a rating card, so
//  putting the phone down on "How did it go?" and letting iOS unload the
//  process erased the whole session (UX review 05.09.2026, 🔴 01).
//
//  Three bands, not two (owner, 06.09.2026): inside three hours the card
//  offers to carry on; past it and up to twelve hours the athlete is ASKED
//  whether to continue or to finish and rate it; only a workout nobody came
//  back to for twelve hours is recorded without being asked.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class AbandonedWorkoutTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-abandoned" }

    private let window = AppStore.workoutResumeWindow
    private let forgotten = AppStore.workoutForgottenAfter

    /// A snapshot parked on the rating screen: every exercise behind, nothing
    /// left to do but answer.
    private func atFeedback(for store: AppStore, savedAt: Date) -> WorkoutSnapshot {
        WorkoutSnapshot(sessionNumber: 1,
                        exIndex: store.nextSession.exercises.count,
                        setIndex: 0,
                        setActuals: [.pushH: [12, 9]],
                        workoutStart: savedAt.addingTimeInterval(-30 * 60),
                        savedAt: savedAt,
                        fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession),
                        atFeedback: true)
    }

    // MARK: - The defect itself

    func testAWorkoutLeftOnTheRatingIsRecordedAfterTheOccasionPasses() {
        let store = AppStore(storageURL: tempURL)
        let last = Date.now.addingTimeInterval(-forgotten - 60)
        store.saveWorkoutSnapshot(atFeedback(for: store, savedAt: last))

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertNil(relaunched.resumableWorkout(),
                     "the occasion is over — it is not offered back")
        XCTAssertTrue(relaunched.settleAbandonedWorkout())
        XCTAssertEqual(relaunched.records.count, 1,
                       "the workout happened; it must exist in the journal")
        XCTAssertEqual(relaunched.records.first?.result, .plan,
                       "an unrated workout counts as on plan (owner, 05.09.2026)")
        XCTAssertNil(relaunched.pendingWorkout, "settled means no longer pending")
    }

    /// The half of the fix that is easy to leave out: rating yesterday's
    /// session this morning must not move it into today.
    func testTheSettledWorkoutKeepsTheDayItHappenedOn() throws {
        let store = AppStore(storageURL: tempURL)
        let lastNight = Date.now.addingTimeInterval(-forgotten - 2 * 60 * 60)
        store.saveWorkoutSnapshot(atFeedback(for: store, savedAt: lastNight))

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertTrue(relaunched.settleAbandonedWorkout())
        let record = try XCTUnwrap(relaunched.records.first)
        XCTAssertEqual(record.date.timeIntervalSince1970,
                       lastNight.addingTimeInterval(-30 * 60).timeIntervalSince1970,
                       accuracy: 1,
                       "dated from workoutStart, not from the moment it was noticed")
    }

    func testAFreshSnapshotIsLeftAloneToBeResumed() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(atFeedback(for: store, savedAt: .now))

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertFalse(relaunched.settleAbandonedWorkout(),
                       "inside the window it is the same occasion — offer it back")
        XCTAssertNotNil(relaunched.pendingWorkout)
        XCTAssertTrue(relaunched.records.isEmpty)
    }

    /// The guards that make the numbers meaningful: a snapshot describing a
    /// plan the engine would no longer hand out has nothing honest to record.
    func testASnapshotOfADifferentPlanIsDroppedRatherThanRecorded() {
        let store = AppStore(storageURL: tempURL)
        let last = Date.now.addingTimeInterval(-forgotten - 60)
        var snap = atFeedback(for: store, savedAt: last)
        snap.fingerprint = "not the plan on offer"
        store.saveWorkoutSnapshot(snap)

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertFalse(relaunched.settleAbandonedWorkout())
        XCTAssertTrue(relaunched.records.isEmpty,
                      "a plan nobody trained must not reach the journal")
        XCTAssertNil(relaunched.pendingWorkout, "and it must not linger either")
    }

    func testASnapshotWithoutProgressRecordsNothing() {
        let store = AppStore(storageURL: tempURL)
        let last = Date.now.addingTimeInterval(-forgotten - 60)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 0, setIndex: 0,
            workoutStart: last.addingTimeInterval(-60), savedAt: last,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession)))

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertFalse(relaunched.settleAbandonedWorkout())
        XCTAssertTrue(relaunched.records.isEmpty)
    }

    /// `activate()` is the one entry point both a cold launch and a
    /// foreground run through, and the settlement has to happen there — and
    /// BEFORE the day re-anchors, or the decay measures a gap to a workout
    /// that had not been written yet.
    func testActivateSettlesTheAbandonedWorkout() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-forgotten - 60)))

        let relaunched = AppStore(storageURL: tempURL)
        relaunched.activate()
        XCTAssertEqual(relaunched.records.count, 1)
    }

    /// `activate()` runs on EVERY foreground, and the workout flow is a cover
    /// presented from a screen that stays alive underneath it — so a return to
    /// the app a day into an idle session used to settle the workout out
    /// from under the athlete still standing in it. The counter advanced, the
    /// rating they then gave failed `completeWorkout`'s replay guard, and the
    /// session stood recorded "on plan" with the honest answer dropped in
    /// silence (self-review 06.09.2026).
    ///
    /// Every other test here settles through a freshly built store — process
    /// death only — which is why the live-app case was green by omission.
    func testAWorkoutStillOnScreenIsNeverSettledUnderneathIt() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-forgotten - 60)))
        store.workoutFlowAppeared()

        store.activate()
        XCTAssertTrue(store.records.isEmpty,
                      "the flow owns this snapshot and will finish the workout itself")
        XCTAssertNotNil(store.pendingWorkout)
        XCTAssertEqual(store.engineState.counter, 0,
                       "advancing the counter is what silently invalidated the rating")

        // And once the flow is gone, the same snapshot settles as it should.
        store.workoutFlowDisappeared()
        store.activate()
        XCTAssertEqual(store.records.count, 1)
    }

    // MARK: - The band where the athlete is asked (owner, 06.09.2026)

    /// Three hours is a long lunch, not a lost session. Past the occasion the
    /// card stops offering to carry on and starts ASKING — and nothing is
    /// written until the answer comes.
    func testPastTheOccasionTheWorkoutIsOfferedForAnAnswerAndNotRecorded() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-window - 60)))

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertNil(relaunched.resumableWorkout(),
                     "not the same occasion any more")
        XCTAssertNotNil(relaunched.unfinishedWorkoutAwaitingAnswer(),
                        "but not forgotten either — it is a question, not a verdict")
        relaunched.activate()
        XCTAssertTrue(relaunched.records.isEmpty,
                      "recording it unasked is exactly what the owner removed")
        XCTAssertNotNil(relaunched.pendingWorkout)
    }

    /// The store deliberately has NO way to record a workout in this band:
    /// answering the card opens the flow on its rating screen, and the athlete
    /// says how it went themselves (owner, 06.09.2026). The only thing decided
    /// for them is a workout nobody came back to for twelve hours.
    func testNothingInThisBandCanBeRecordedWithoutTheAthlete() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-window - 60)))

        let relaunched = AppStore(storageURL: tempURL)
        // Every automatic path there is, run twice for good measure.
        relaunched.activate()
        XCTAssertFalse(relaunched.settleAbandonedWorkout())
        relaunched.activate()
        XCTAssertTrue(relaunched.records.isEmpty)
        XCTAssertNotNil(relaunched.unfinishedWorkoutAwaitingAnswer(),
                        "the question has to still be there to be answered")
    }

    /// Twelve hours is the line, and it is elapsed time rather than the
    /// midnight `trainingDays` counts: a session left at 23:30 and opened at
    /// 00:30 is one midnight and one hour, and one hour is not "forgotten".
    func testTheQuestionStandsUntilTheWorkoutIsForgotten() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-forgotten + 60)))

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertNotNil(relaunched.unfinishedWorkoutAwaitingAnswer(),
                        "a minute short of the threshold is still a question")
        XCTAssertFalse(relaunched.settleAbandonedWorkout())
        XCTAssertTrue(relaunched.records.isEmpty)
    }

    /// Once it IS forgotten, the question is gone — the card must not offer an
    /// answer to something already recorded.
    func testAForgottenWorkoutIsNoLongerOfferedAsAQuestion() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-forgotten - 60)))

        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertNil(relaunched.unfinishedWorkoutAwaitingAnswer())
        XCTAssertTrue(relaunched.settleAbandonedWorkout())
    }

    // MARK: - Time charged to an absence

    /// The rule the away time rests on, and it had no test at all: the flow
    /// changed what "absence" means and nothing anywhere read the result back
    /// (review 06.09.2026). A rest running on schedule is training whether or
    /// not the process survived it.
    func testAScheduledRestIsTrainingEvenWhenTheProcessDies() {
        let restStart = Date.now.addingTimeInterval(-3600)
        let restEnd = restStart.addingTimeInterval(90)

        // Locked at the top of a 90 s rest, opened five seconds before its end:
        // the athlete was resting the whole time, and none of it is absence.
        XCTAssertEqual(SetFacts.awayGained(savedAt: restStart, restEndDate: restEnd,
                                           now: restStart.addingTimeInterval(85)), 0)
        // Back long after it: only what is past the rest's end counts.
        XCTAssertEqual(SetFacts.awayGained(savedAt: restStart, restEndDate: restEnd,
                                           now: restStart.addingTimeInterval(3000)), 2910)
        // Exactly at the end is still nothing owed.
        XCTAssertEqual(SetFacts.awayGained(savedAt: restStart, restEndDate: restEnd,
                                           now: restEnd), 0)
    }

    /// Off a rest there is no end date to lean on, so the whole gap counts —
    /// the known floor of the rule, written down so a later change to it is a
    /// decision rather than a surprise.
    func testWithoutARestTheWholeGapIsAbsence() {
        let saved = Date.now.addingTimeInterval(-600)
        XCTAssertEqual(SetFacts.awayGained(savedAt: saved, restEndDate: nil, now: .now),
                       600, accuracy: 1)
        // A clock that moved backwards must not hand back a negative.
        XCTAssertEqual(SetFacts.awayGained(savedAt: .now, restEndDate: nil,
                                           now: .now.addingTimeInterval(-500)), 0)
    }

    // MARK: - What an interruption amounts to

    /// 🔴 02: the summary of a finished hold is the same fact as the rest
    /// after a last set — every set is behind. It used to be catalogued as
    /// unfinished, which handed a fully performed movement to the engine as a
    /// skip and erased the seconds that screen exists to confirm.
    func testAFinishedMovementOnItsSummaryIsNotASkip() {
        let exercises = AppStore(storageURL: tempURL).nextSession.exercises
        let settled = SetFacts.settlement(in: exercises,
                                          exIndex: 0,
                                          setsBehind: exercises[0].sets,
                                          currentIsDone: true,
                                          alreadySkipped: [:])
        XCTAssertFalse(settled.skipped.contains(exercises[0].pattern),
                       "every set is done — it was trained")
        XCTAssertNil(settled.interrupted)
        XCTAssertEqual(settled.setsSkipped[exercises[0].pattern] ?? 0, 0)
    }

    /// 🔴 03: "finish now" promises to keep what you have done. A movement
    /// with enough sets behind keeps its numbers, and the sets never reached
    /// travel as skipped SETS — the statement an in-workout skip makes.
    func testAMovementWithEnoughSetsBehindKeepsItsNumbers() {
        // Built rather than borrowed from session 1: the rule is about the
        // arithmetic of sets, and a plan that happens to ship three of them
        // would make this test pass or fail for an unrelated reason.
        let deep = SessionExercise(pattern: .pushH, name: "Push-up", variation: 1,
                                   unit: .reps, load: 8, perSide: false, sets: 4,
                                   restSetSec: 60, restExerciseSec: 90,
                                   loads: nil, probe: nil)
        let settled = SetFacts.settlement(in: [deep],
                                          exIndex: 0,
                                          setsBehind: 2,
                                          currentIsDone: false,
                                          alreadySkipped: [:])
        XCTAssertFalse(settled.skipped.contains(.pushH),
                       "two sets performed is a trained movement, not a skip")
        XCTAssertNil(settled.interrupted)
        XCTAssertEqual(settled.setsSkipped[.pushH], 2,
                       "the two sets never reached are the ones taken off")
    }

    /// Below the floor there is no movement to keep, and it is named as
    /// unfinished rather than quietly counted.
    func testASingleSetIntoAMovementLeavesItUnfinished() throws {
        let exercises = AppStore(storageURL: tempURL).nextSession.exercises
        let settled = SetFacts.settlement(in: exercises,
                                          exIndex: 1,
                                          setsBehind: 1,
                                          currentIsDone: false,
                                          alreadySkipped: [:])
        XCTAssertEqual(settled.interrupted, exercises[1].pattern)
        XCTAssertTrue(settled.skipped.contains(exercises[1].pattern),
                      "to the engine it is still a skip — only the label differs")
    }

    func testMovementsNeverReachedAreSkips() {
        let exercises = AppStore(storageURL: tempURL).nextSession.exercises
        let settled = SetFacts.settlement(in: exercises,
                                          exIndex: 1,
                                          setsBehind: 0,
                                          currentIsDone: false,
                                          alreadySkipped: [:])
        for ex in exercises[1...] {
            XCTAssertTrue(settled.skipped.contains(ex.pattern),
                          "\(ex.pattern) was never reached")
        }
        XCTAssertFalse(settled.skipped.contains(exercises[0].pattern),
                       "the one behind us was trained")
    }

    /// The journal has to be able to say which movement was left half-done —
    /// "not finished" and "skipped" are different facts to a person even
    /// though the engine freezes the ladder either way (owner, 05.09.2026).
    func testTheJournalNamesTheUnfinishedMovement() throws {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        store.completeWorkout(session: session, result: .plan,
                              skipped: [session.exercises[2].pattern],
                              interrupted: session.exercises[2].pattern)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.interrupted, session.exercises[2].pattern)
    }

    func testTheUnfinishedMovementSurvivesARelaunch() throws {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        store.completeWorkout(session: session, result: .plan,
                              skipped: [session.exercises[2].pattern],
                              interrupted: session.exercises[2].pattern)

        let relaunched = AppStore(storageURL: tempURL)
        let record = try XCTUnwrap(relaunched.records.first)
        XCTAssertEqual(record.interrupted, session.exercises[2].pattern,
                       "a persisted field that does not come back is not persisted")
    }
}
