//
//  §40.8: there is no migration from v2, and this is what that means where a
//  person meets it.
//
//  A state written by an older build does not decode — `vars` and `doses` are
//  required, and a v2 file has `levels` instead — so the store hands the
//  engine `initial`: every movement on its first rung at 3×4 (3×15 s). The
//  WORKOUT JOURNAL is a different thing and is not touched: it is what
//  actually happened, and losing it would be losing the person's history.
//
//  This file replaces PushLadderMigrationTests, whose whole subject — "the
//  stored level keeps its number through a library reshuffle" — stopped
//  existing with the level itself. The claim being checked is still that
//  there is no migration code; only the consequence changed.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class CleanStartTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-clean-start" }

    /// A storage file exactly as a v2 build wrote it: engine state keyed by
    /// `levels`, and a journal of two workouts beside it.
    private func storeFromBefore() throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",24" }.joined(separator: ",")
        let zeros = Pattern.allCases.map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":40,"levels":[\(levels)],"failStreak":[\(zeros)],
                        "hasBar":true,"lessRun":0,"returnRun":0,"rampWindow":0,
                        "weekAgeDays":0},
         "records":[
           {"sessionNumber":39,"date":0,"result":"plan","totalLevelAfter":170,
            "exercises":[{"pattern":"squat","name":"Bulgarian split squat","tier":3,
                          "unit":"reps","load":9,"perSide":true,"sets":3,
                          "restSetSec":90,"restExerciseSec":60,"display":"3×9 per side"}]},
           {"sessionNumber":40,"date":86400,"result":"more","totalLevelAfter":180}],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    /// The engine starts clean: first variation, 3×4, nothing shown yet.
    func testAnIncompatibleStateGivesACleanStart() throws {
        let store = try storeFromBefore()
        for p in Pattern.allCases {
            XCTAssertEqual(store.engineState.vars[p], 1, "\(p.rawValue): first rung")
            XCTAssertEqual(store.engineState.doses[p], Dose.grid(Library.unit(p, 1)).min,
                           "\(p.rawValue): the floor of the grid")
        }
        XCTAssertTrue(store.engineState.shown.isEmpty, "nothing has been shown to this engine")
        XCTAssertEqual(store.totalProgress, 0)
        XCTAssertEqual(store.engineState.counter, 0,
                       "the counter belongs to the state, and the state is new")
    }

    /// …and the plan it draws is the declared beginning, for everyone.
    func testThePlanAfterACleanStartIsThreeByTheFloor() throws {
        let store = try storeFromBefore()
        let session = store.nextSession
        XCTAssertEqual(session.sessionNumber, 1)
        for ex in session.exercises {
            XCTAssertEqual(ex.sets, 3, "\(ex.pattern.rawValue)")
            XCTAssertEqual(ex.load, Dose.grid(ex.unit).min, "\(ex.pattern.rawValue)")
            XCTAssertNil(ex.probe, "nothing to probe from the floor")
        }
    }

    /// The history survives whole — that is the half of §40.8 the person cares
    /// about, and the half a decode failure could most easily have taken.
    func testTheWorkoutJournalSurvivesIntact() throws {
        let store = try storeFromBefore()
        XCTAssertEqual(store.records.count, 2, "both workouts are still there")
        XCTAssertEqual(store.records.map(\.sessionNumber), [39, 40])
        XCTAssertEqual(store.records.last?.result, .more)
        // A record written before v3 carries no point on the v3 scale, and
        // says so rather than stating a number from a scale that is gone.
        XCTAssertNil(store.records.first?.totalProgressAfter)
        XCTAssertNil(store.records.first?.positionsAfter)
    }

    /// An exercise line from an old record still renders, and renders the
    /// movement it was actually done at. Its `tier` is NOT read as a v3
    /// variation: the ladders of §40.1 put different movements at those
    /// numbers, and re-resolving would rewrite the person's history.
    func testAnOldExerciseLineKeepsTheNameItWasWrittenWith() throws {
        let store = try storeFromBefore()
        let exercises = try XCTUnwrap(store.records.first?.exercises)
        let squat = try XCTUnwrap(exercises.first)
        XCTAssertEqual(squat.pattern, .squat)
        XCTAssertEqual(squat.load, 9)
        XCTAssertEqual(squat.variation, 0,
                       "a record from before §40.1 marks itself as predating the ladders")
        XCTAssertNil(squat.probe)
    }

    /// And the store is usable straight away: a workout completed on the clean
    /// state writes a v3 record beside the old ones.
    func testTheStoreIsUsableImmediatelyAfterACleanStart() throws {
        let store = try storeFromBefore()
        let earned = store.completeWorkout(session: store.nextSession, result: .plan)
        XCTAssertTrue(earned.isEmpty)
        XCTAssertEqual(store.records.count, 3)
        XCTAssertNotNil(store.records.last?.positionsAfter)
        XCTAssertEqual(store.records.last?.sessionNumber, 1)
    }
}
