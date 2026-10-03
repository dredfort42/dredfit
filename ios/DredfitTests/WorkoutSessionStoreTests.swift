import XCTest
import DredfitCore
@testable import Dredfit

/// The snapshot's policy on its own: which snapshot still describes the plan
/// ahead, and what a forgotten workout is recorded as.
@MainActor
final class WorkoutSessionStoreTests: XCTestCase {

    private let plan = Engine.generateSession(.initial)
    private let start = Date(timeIntervalSince1970: 1_900_000_000)

    private func snapshot(exIndex: Int = 0, setIndex: Int = 1,
                          setActuals: [Pattern: [Int]]? = nil, skipped: Set<Pattern> = [],
                          fingerprint: String? = nil, awaySec: Int? = nil,
                          raisedSteps: [Pattern: Int]? = nil) -> WorkoutSnapshot {
        WorkoutSnapshot(sessionNumber: 1, exIndex: exIndex, setIndex: setIndex,
                        setActuals: setActuals, skipped: skipped,
                        workoutStart: start, savedAt: start + 3_600,
                        fingerprint: fingerprint ?? WorkoutSnapshot.fingerprint(of: plan),
                        awaySec: awaySec, raisedSteps: raisedSteps)
    }

    func testOnlyASnapshotOfThePlanAheadWithSomethingDoneIsValid() {
        XCTAssertNotNil(WorkoutSessionStore.valid(snapshot(), plan: plan, counter: 0))
        XCTAssertNil(WorkoutSessionStore.valid(snapshot(), plan: plan, counter: 1),
                     "another session number")
        XCTAssertNil(WorkoutSessionStore.valid(snapshot(fingerprint: "another plan"), plan: plan, counter: 0),
                     "a plan regenerated under the same number")
        XCTAssertNil(WorkoutSessionStore.valid(snapshot(setIndex: 0), plan: plan, counter: 0),
                     "nothing done yet")
        XCTAssertNil(WorkoutSessionStore.valid(nil, plan: plan, counter: 0))
    }

    func testASettlementIsDatedWhereTheWorkoutEndedLessTheTimeAway() {
        let settled = WorkoutSessionStore.settlement(of: snapshot(awaySec: 600), in: plan)
        XCTAssertEqual(settled.date, start + 3_600)
        XCTAssertEqual(settled.durationSec, 3_000)
    }

    func testASkipWinsOverAnActualAndTakesItsRaiseWithIt() {
        let first = plan.exercises[0].pattern
        let second = plan.exercises[1].pattern
        let settled = WorkoutSessionStore.settlement(
            of: snapshot(exIndex: 2, setIndex: 0,
                         setActuals: [first: [6, 6, 6], second: [5]],
                         skipped: [second],
                         raisedSteps: [first: 1, second: 2]),
            in: plan)
        XCTAssertEqual(settled.setActuals[first], [6, 6, 6])
        XCTAssertNil(settled.setActuals[second])
        XCTAssertEqual(settled.raised, [first: 1])
        XCTAssertTrue(settled.skipped.contains(second))
        XCTAssertEqual(settled.skipped, Set(plan.exercises.dropFirst().map(\.pattern)),
                       "everything from the movement it stopped at on is a skip")
    }
}
