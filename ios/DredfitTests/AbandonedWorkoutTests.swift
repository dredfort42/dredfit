//
//  A workout that was trained and never rated. Putting the phone down on
//  "How did it go?" and letting iOS unload the process must not erase the
//  session: the snapshot it leaves behind is what gets it into the journal.
//
//  Three bands: inside three hours the card offers to carry on; past it and
//  up to twelve hours the athlete is ASKED whether to continue or to finish
//  and rate it; only a workout nobody came back to for twelve hours is
//  recorded without being asked.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class AbandonedWorkoutTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-abandoned" }

    private let window = WorkoutSessionStore.resumeWindow
    private let forgotten = WorkoutSessionStore.forgottenAfter

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
        let store = makeStore()
        let last = Date.now.addingTimeInterval(-forgotten - 60)
        store.saveWorkoutSnapshot(atFeedback(for: store, savedAt: last))

        let relaunched = makeStore()
        XCTAssertNil(relaunched.resumableWorkout(),
                     "the occasion is over — it is not offered back")
        XCTAssertTrue(relaunched.settleAbandonedWorkout())
        XCTAssertEqual(relaunched.records.count, 1,
                       "the workout happened; it must exist in the journal")
        XCTAssertEqual(relaunched.records.first?.result, .plan,
                       "an unrated workout counts as on plan")
        XCTAssertNil(relaunched.pendingWorkout, "settled means no longer pending")
    }

    /// The half of the fix that is easy to leave out: rating yesterday's
    /// session this morning must not move it into today.
    func testTheSettledWorkoutKeepsTheDayItHappenedOn() throws {
        let store = makeStore()
        let lastNight = Date.now.addingTimeInterval(-forgotten - 2 * 60 * 60)
        store.saveWorkoutSnapshot(atFeedback(for: store, savedAt: lastNight))

        let relaunched = makeStore()
        XCTAssertTrue(relaunched.settleAbandonedWorkout())
        let record = try XCTUnwrap(relaunched.records.first)
        XCTAssertEqual(record.date.timeIntervalSince1970,
                       lastNight.timeIntervalSince1970,
                       accuracy: 1,
                       "dated where it ended (savedAt), not from the moment it was noticed")
        // A record's date is its END, as the Health export reads it: the
        // interval it spans starts at workoutStart, not half an hour early.
        let duration = TimeInterval(try XCTUnwrap(record.durationSec))
        XCTAssertEqual(record.date.addingTimeInterval(-duration).timeIntervalSince1970,
                       lastNight.addingTimeInterval(-30 * 60).timeIntervalSince1970,
                       accuracy: 1)
    }

    func testAFreshSnapshotIsLeftAloneToBeResumed() {
        let store = makeStore()
        store.saveWorkoutSnapshot(atFeedback(for: store, savedAt: .now))

        let relaunched = makeStore()
        XCTAssertFalse(relaunched.settleAbandonedWorkout(),
                       "inside the window it is the same occasion — offer it back")
        XCTAssertNotNil(relaunched.pendingWorkout)
        XCTAssertTrue(relaunched.records.isEmpty)
    }

    /// The guards that make the numbers meaningful: a snapshot describing a
    /// plan the engine would no longer hand out has nothing honest to record.
    func testASnapshotOfADifferentPlanIsDroppedRatherThanRecorded() {
        let store = makeStore()
        let last = Date.now.addingTimeInterval(-forgotten - 60)
        var snap = atFeedback(for: store, savedAt: last)
        snap.fingerprint = "not the plan on offer"
        store.saveWorkoutSnapshot(snap)

        let relaunched = makeStore()
        XCTAssertFalse(relaunched.settleAbandonedWorkout())
        XCTAssertTrue(relaunched.records.isEmpty,
                      "a plan nobody trained must not reach the journal")
        XCTAssertNil(relaunched.pendingWorkout, "and it must not linger either")
    }

    func testASnapshotWithoutProgressRecordsNothing() {
        let store = makeStore()
        let last = Date.now.addingTimeInterval(-forgotten - 60)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 0, setIndex: 0,
            workoutStart: last.addingTimeInterval(-60), savedAt: last,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession)))

        let relaunched = makeStore()
        XCTAssertFalse(relaunched.settleAbandonedWorkout())
        XCTAssertTrue(relaunched.records.isEmpty)
    }

    /// `activate()` is the one entry point both a cold launch and a
    /// foreground run through, and the settlement has to happen there — and
    /// BEFORE the day re-anchors, or the decay measures a gap to a workout
    /// that had not been written yet.
    func testActivateSettlesTheAbandonedWorkout() {
        let store = makeStore()
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-forgotten - 60)))

        let relaunched = makeStore()
        relaunched.activate()
        XCTAssertEqual(relaunched.records.count, 1)
    }

    /// `activate()` runs on EVERY foreground, and the workout flow is a cover
    /// presented from a screen that stays alive underneath it — so a return to
    /// the app a day into an idle session must not settle the workout out
    /// from under the athlete still standing in it. The counter would
    /// advance, the rating they then gave would fail `completeWorkout`'s
    /// replay guard, and the session would stand recorded "on plan" with the
    /// honest answer dropped in silence.
    ///
    /// Every other test here settles through a freshly built store — process
    /// death only — so without this one the live-app case is green by
    /// omission.
    func testAWorkoutStillOnScreenIsNeverSettledUnderneathIt() {
        let store = makeStore()
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

    // MARK: - The band where the athlete is asked

    /// Three hours is a long lunch, not a lost session. Past the occasion the
    /// card stops offering to carry on and starts ASKING — and nothing is
    /// written until the answer comes.
    func testPastTheOccasionTheWorkoutIsOfferedForAnAnswerAndNotRecorded() {
        let store = makeStore()
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-window - 60)))

        let relaunched = makeStore()
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
    /// says how it went themselves. The only thing decided for them is a
    /// workout nobody came back to for twelve hours.
    func testNothingInThisBandCanBeRecordedWithoutTheAthlete() {
        let store = makeStore()
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-window - 60)))

        let relaunched = makeStore()
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
        let store = makeStore()
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-forgotten + 60)))

        let relaunched = makeStore()
        XCTAssertNotNil(relaunched.unfinishedWorkoutAwaitingAnswer(),
                        "a minute short of the threshold is still a question")
        XCTAssertFalse(relaunched.settleAbandonedWorkout())
        XCTAssertTrue(relaunched.records.isEmpty)
    }

    /// Once it IS forgotten, the question is gone — the card must not offer an
    /// answer to something already recorded.
    func testAForgottenWorkoutIsNoLongerOfferedAsAQuestion() {
        let store = makeStore()
        store.saveWorkoutSnapshot(
            atFeedback(for: store, savedAt: .now.addingTimeInterval(-forgotten - 60)))

        let relaunched = makeStore()
        XCTAssertNil(relaunched.unfinishedWorkoutAwaitingAnswer())
        XCTAssertTrue(relaunched.settleAbandonedWorkout())
    }

    // MARK: - Time charged to an absence

    /// An absence the process lived through (locked overnight, not killed):
    /// charged from the moment of leaving, a running rest still owed, and
    /// the stamp spent once.
    func testALivedThroughAbsenceIsChargedOnceFromTheMomentOfLeaving() {
        let t = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var absence = SetFacts.Absence()
        XCTAssertEqual(absence.comeBack(now: t), 0, "nothing stamped, nothing owed")

        absence.leave(now: t, restEndDate: nil)
        absence.leave(now: t.addingTimeInterval(600), restEndDate: nil)   // the first leaving wins
        XCTAssertEqual(absence.comeBack(now: t.addingTimeInterval(11 * 3600)), 11 * 3600)
        XCTAssertEqual(absence.comeBack(now: t.addingTimeInterval(12 * 3600)), 0, "spent")

        absence.leave(now: t, restEndDate: t.addingTimeInterval(90))
        XCTAssertEqual(absence.comeBack(now: t.addingTimeInterval(85)), 0, "inside the rest")
        absence.leave(now: t, restEndDate: t.addingTimeInterval(90))
        XCTAssertEqual(absence.comeBack(now: t.addingTimeInterval(3000)), 2910)
    }

    /// The rule the away time rests on: a rest running on schedule is
    /// training whether or not the process survived it.
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

    /// The summary of a finished hold is the same fact as the rest after a
    /// last set — every set is behind. Catalogued as unfinished, it would hand
    /// a fully performed movement to the engine as a skip and erase the
    /// seconds that screen exists to confirm.
    func testAFinishedMovementOnItsSummaryIsNotASkip() {
        let exercises = makeStore().nextSession.exercises
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

    /// Both numbers come off disk, and a negative index must not trap inside
    /// `activate()` on every launch: it reads as the first exercise.
    func testANegativeSnapshotIndexSettlesLikeTheFirstExercise() {
        let exercises = makeStore().nextSession.exercises
        for done in [false, true] {
            let clamped = SetFacts.settlement(in: exercises, exIndex: -3, setsBehind: -5,
                                              currentIsDone: done, alreadySkipped: [:])
            let first = SetFacts.settlement(in: exercises, exIndex: 0, setsBehind: 0,
                                            currentIsDone: done, alreadySkipped: [:])
            XCTAssertEqual(clamped, first)
        }
    }

    /// "Finish now" promises to keep what you have done. A movement
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
        let exercises = makeStore().nextSession.exercises
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
        let exercises = makeStore().nextSession.exercises
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
    /// though the engine freezes the ladder either way.
    func testTheJournalNamesTheUnfinishedMovement() throws {
        let store = makeStore()
        let session = store.nextSession
        store.completeWorkout(session: session, result: .plan,
                              skipped: [session.exercises[2].pattern],
                              interrupted: session.exercises[2].pattern)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.interrupted, session.exercises[2].pattern)
    }

    func testTheUnfinishedMovementSurvivesARelaunch() throws {
        let store = makeStore()
        let session = store.nextSession
        store.completeWorkout(session: session, result: .plan,
                              skipped: [session.exercises[2].pattern],
                              interrupted: session.exercises[2].pattern)

        let relaunched = makeStore()
        let record = try XCTUnwrap(relaunched.records.first)
        XCTAssertEqual(record.interrupted, session.exercises[2].pattern,
                       "a persisted field that does not come back is not persisted")
    }
}
