//
//  §41.7: a state written before v3 is READ AND CARRIED OVER.
//
//  RE-MARKED WHOLESALE (v3.1, 26.08.2026), class: reversal of an owner
//  decision. This file used to pin the opposite — §40.8's "there is no
//  migration", every movement back to its first rung at 3×4. The decision was
//  reversed on 26.08.2026 because the way back it counted on never reached
//  anyone: entering facts is explained by exactly one line in the app, and
//  that line shows only when the journal is empty — which, by the same
//  paragraph, an upgrading trainee's journal never is.
//
//  What did NOT change and is still pinned below: the workout journal survives
//  untouched, an old exercise line keeps the movement it was written with, and
//  a state that is neither v2 nor v3 still gives a clean start.
//
//  The migration's own arithmetic — the tier→variation table, the 480-cell
//  safety sweep — is pinned in MigrationV2Tests.
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

    /// The engine keeps the place the person had earned. L=24 is tier 4 in v2
    /// at 4 reps, so every pattern lands on its tier-4 variation, not on its
    /// first — and the journal records the dose, so the very first descent has
    /// somewhere to land other than the floor.
    func testAV2StateIsCarriedOverNotReset() throws {
        let store = try storeFromBefore()
        for p in Pattern.allCases {
            let expected = try XCTUnwrap(Engine.v2TierToVariation[p]?[3])
            XCTAssertEqual(store.engineState.vars[p], expected, "\(p.rawValue): its own rung")
            XCTAssertNotNil(store.engineState.shown[p]?[expected],
                            "\(p.rawValue): what was done there is on record")
        }
        XCTAssertEqual(store.engineState.counter, 40, "the rotation phase carries over too")
        XCTAssertTrue(store.engineState.hasBar, "and the answer about the bar")
    }

    /// …and the plan it draws is the one they were doing, not the beginning.
    func testThePlanAfterMigrationIsTheirOwn() throws {
        let store = try storeFromBefore()
        let session = store.nextSession
        XCTAssertEqual(session.sessionNumber, 41, "the count continues")
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

    /// And the store is usable straight away: a workout completed on the
    /// carried-over state writes a v3 record beside the old ones.
    func testTheStoreIsUsableImmediatelyAfterMigration() throws {
        let store = try storeFromBefore()
        _ = store.completeWorkout(session: store.nextSession, result: .plan)
        XCTAssertEqual(store.records.count, 3)
        XCTAssertNotNil(store.records.last?.positionsAfter)
        XCTAssertEqual(store.records.last?.sessionNumber, 41)
    }

    /// A state that is neither v2 nor v3 still gives a clean start — that half
    /// of §40.8 stands, and it is the only half that ever protected anything.
    func testGarbageStillGivesACleanStart() throws {
        try Data(#"{"engineState":{"nonsense":1},"records":[],"settings":null}"#.utf8)
            .write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        for p in Pattern.allCases {
            XCTAssertEqual(store.engineState.vars[p], 1, "\(p.rawValue): first rung")
        }
        XCTAssertEqual(store.engineState.counter, 0)
    }
}
