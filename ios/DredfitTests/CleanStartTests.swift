//
//  A state written before v3 is READ AND CARRIED OVER.
//
//  Also pinned below: the workout journal survives untouched, an old exercise
//  line keeps the movement it was written with, and a state that is neither
//  v2 nor v3 still gives a clean start.
//
//  The migration's own arithmetic is pinned elsewhere: the 480-cell safety
//  sweep in MigrationV2Tests, and the tier→variation table itself in
//  MigrationV2Tests+Table, against a snapshot that does not come out of the
//  table. This file reads its own expectations from that same snapshot
//  (`V2FormatSnapshot`) and never from `Engine.v2TierToVariation`, which
//  would make the assertion below unfailable.
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
        return makeStore()
    }

    /// The engine keeps the place the person had earned. L=24 is tier 4 in v2
    /// at 4 reps, so every pattern lands on its tier-4 variation, not on its
    /// first — and the journal records the dose they land on there.
    func testAV2StateIsCarriedOverNotReset() throws {
        let store = try storeFromBefore()
        for p in Pattern.allCases {
            // NOT `Engine.v2TierToVariation[p]?[3]`. Reading the expectation
            // out of the table under test makes this assertion a tautology: the
            // whole mapping could be replaced by `[1, 1, 1, 1]` — every
            // upgrading trainee thrown back to the first rung — and it would
            // stay green. `V2FormatSnapshot` is the second, independent copy.
            let expected = try XCTUnwrap(V2FormatSnapshot.tierToVariation[p]?[3],
                                         "\(p.rawValue) has no tier-4 landing in the v2 snapshot")
            XCTAssertEqual(store.engineState.vars[p], expected, "\(p.rawValue): its own rung")
            XCTAssertNotNil(store.engineState.shown[p]?[expected],
                            "\(p.rawValue): what was done there is on record")
        }
        XCTAssertEqual(store.engineState.counter, 40, "the rotation phase carries over too")
        XCTAssertTrue(store.engineState.hasBar, "and the answer about the bar")
    }

    /// …and the plan it draws stands on the rung they earned.
    ///
    /// What carries over is the RUNG: base sets, the grid floor and no probe
    /// would hold for a clean start too. The dose sits at the floor here
    /// because L=24 is the BOTTOM of v2's tier 4 (4 reps, a 10-second hold):
    /// 4 reps is already v3's floor, and a hold below it comes UP to it.
    func test_planAfterMigration_fromTheBottomOfV2sTopTier_standsOnTheEarnedRung() throws {
        let store = try storeFromBefore()
        let session = store.nextSession

        XCTAssertEqual(session.sessionNumber, 41, "the count continues where v2 left it")
        XCTAssertFalse(session.exercises.isEmpty,
                       "a session must carry slots, or the loop below asserts nothing at all")
        for ex in session.exercises {
            let earned = try XCTUnwrap(V2FormatSnapshot.tierToVariation[ex.pattern]?[3],
                                       "\(ex.pattern.rawValue) has no tier-4 landing in the v2 snapshot")
            XCTAssertEqual(ex.variation, earned,
                           "\(ex.pattern.rawValue): the rung v2's tier 4 was earned on, not the first one")
            XCTAssertEqual(ex.sets, 3,
                           "\(ex.pattern.rawValue): v2 planned three sets at L=24, and sets above the base "
                           + "exist only on the top rung anyway")
            XCTAssertEqual(ex.load, Dose.grid(ex.unit).min,
                           "\(ex.pattern.rawValue): the bottom of v2's tier 4 is already v3's grid floor — "
                           + "this is the dose they were doing, not a reset")
            XCTAssertNil(ex.probe,
                         "\(ex.pattern.rawValue): a probe is offered from the dose CEILING, and they "
                         + "stand at the floor")
        }
    }

    /// The history survives whole — that is the half the person cares about,
    /// and the half a decode failure could most easily take.
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
    /// variation: the v3 ladders put different movements at those numbers,
    /// and re-resolving would rewrite the person's history.
    func testAnOldExerciseLineKeepsTheNameItWasWrittenWith() throws {
        let store = try storeFromBefore()
        let exercises = try XCTUnwrap(store.records.first?.exercises)
        let squat = try XCTUnwrap(exercises.first)
        XCTAssertEqual(squat.pattern, .squat)
        XCTAssertEqual(squat.load, 9)
        XCTAssertEqual(squat.variation, 0,
                       "a record from before v3 marks itself as predating the ladders")
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

    /// A state that is neither v2 nor v3 still gives a clean start: there is
    /// nothing in it to carry over.
    func testGarbageStillGivesACleanStart() throws {
        try Data(#"{"engineState":{"nonsense":1},"records":[],"settings":null}"#.utf8)
            .write(to: tempURL)
        let store = makeStore()
        for p in Pattern.allCases {
            XCTAssertEqual(store.engineState.vars[p], 1, "\(p.rawValue): first rung")
        }
        XCTAssertEqual(store.engineState.counter, 0)
    }
}
