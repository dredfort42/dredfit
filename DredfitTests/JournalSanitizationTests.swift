//
//  The journal is an input too. The engine heals the state
//  it is handed, but its own snapshots come back out of the store file and go
//  straight into arithmetic — and in Swift a subtraction or a product on a
//  hand-edited number traps the process rather than saturating. Found by the
//  adversarial review of the sanitization wave, which reproduced both crashes
//  with a compiled probe (exit 133) before these were written.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class JournalSanitizationTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-journal" }

    private func store(records: String) throws -> AppStore {
        let vars = Pattern.allCases.map { "\"\($0.rawValue)\",2" }.joined(separator: ",")
        let doses = Pattern.allCases.map { "\"\($0.rawValue)\",10" }.joined(separator: ",")
        let zeros = Pattern.allCases.map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":11,"vars":[\(vars)],"doses":[\(doses)],
                        "failStreak":[\(zeros)]},
         "records":[\(records)],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    // MARK: - Numbers that would trap the arithmetic downstream

    /// A stored POSITION outside any ladder cannot trap the retrospective,
    /// which measures it and subtracts. The engine's own reader clamps the
    /// coordinates, so a hand-edited variation of Int.max is a rung of the
    /// ladder rather than an index into nothing.
    ///
    /// The DOSE is the coordinate that actually traps, and until 28.08.2026
    /// this test carried 4 and 99 for it — both perfectly ordinary — so it
    /// could not go red. `Library.index` clamps a variation and `fit` clamps
    /// the sets before anything subtracts, but `Dose.snap` runs BEFORE
    /// `Dose.clamped` and `Dose.rung` opens with `dose - grid.min`: an
    /// `Int.min` there took the process down with SIGTRAP. Both ends of the
    /// range are walked below, and `sub`/`cut` with them.
    func testAStoredPositionOutsideTheLaddersCannotTrapTheRetrospective() throws {
        let s = try store(records: """
        {"sessionNumber":1,"date":0,"result":"plan","totalProgressAfter":180,
         "positionsAfter":["squat",{"variation":-9223372036854775808,"sets":3,"dose":4},
                           "pull",{"variation":9223372036854775807,"sets":99,"dose":99},
                           "hinge",{"variation":1,"sets":3,
                                    "dose":-9223372036854775808,
                                    "sub":-9223372036854775808,
                                    "cut":-9223372036854775808},
                           "lunge",{"variation":1,"sets":3,
                                    "dose":9223372036854775807,
                                    "sub":9223372036854775807,
                                    "cut":9223372036854775807}]}
        """)
        XCTAssertNotNil(s.records.first?.positionsAfter?[.hinge])
        XCTAssertNotNil(s.records.first?.positionsAfter?[.lunge])
        let recorded = try XCTUnwrap(s.records.first?.positionsAfter)
        XCTAssertNotNil(recorded[.squat])
        XCTAssertNotNil(recorded[.pull])
        // Measuring any of them answers a number rather than trapping — on the
        // SIX-coordinate form, which is what the chart and the retrospective
        // both call now. On the short one `sub` and `cut` are never read, so
        // the two that carry Int.min here would go untouched.
        for (p, position) in recorded {
            let steps = Engine.progress(p, variation: position.variation,
                                        sets: position.sets, dose: position.dose,
                                        sub: position.sub ?? 0, cut: position.cut ?? 0)
            XCTAssertGreaterThanOrEqual(steps, 0)
            XCTAssertLessThanOrEqual(steps, Engine.ladderSpan(p))
        }
        // The screen that does the subtraction still renders.
        _ = Retrospective.make(records: s.records, current: s.currentPositions)
    }

    func testATotalOutsideAnyRealHistoryCannotTrapTheWeekSummary() throws {
        let s = try store(records: """
        {"sessionNumber":9223372036854775807,"date":0,"result":"plan",
         "totalProgressAfter":-9223372036854775808},
        {"sessionNumber":2,"date":1000,"result":"plan",
         "totalProgressAfter":9223372036854775807}
        """)
        XCTAssertEqual(s.records.first?.totalProgressAfter, 0)
        XCTAssertEqual(s.records.first?.sessionNumber, EngineConfig.countMax)
        XCTAssertEqual(s.records.last?.totalProgressAfter, EngineConfig.countMax)
        XCTAssertNotNil(s.weekSummary(for: .now))
    }

    func testACorruptDateCannotTrapTheGapMath() throws {
        // Int(elapsed / 86_400) traps when the quotient is past Int's range —
        // it does not saturate. A date of 1e300 seconds decodes cleanly.
        let s = try store(records: """
        {"sessionNumber":1,"date":1e300,"result":"plan","totalProgressAfter":180}
        """)
        XCTAssertNotNil(s.gapDays(), "a nonsense date yields a number, not a crash")
        XCTAssertEqual(s.gapDays(), 0, "a workout in the far future is not a break")
        _ = s.recentGaps
        _ = s.shouldOfferComeback()

        let past = try store(records: """
        {"sessionNumber":1,"date":-1e300,"result":"plan","totalProgressAfter":180}
        """)
        XCTAssertEqual(past.gapDays(), EngineConfig.countMax,
                       "and one in the far past clamps to the technical ceiling")
    }

    /// A store whose journal carries the given records AND has Health export
    /// already switched on in the settings the file itself holds.
    private func healthStore(records: String) throws -> AppStore {
        let lv = Pattern.allCases.map { "\"\($0.rawValue)\",20" }.joined(separator: ",")
        let zeros = Pattern.allCases.map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":11,"levels":[\(lv)],"failStreak":[\(zeros)]},
         "records":[\(records)],
         "settings":{"restWeekdays":[],"soundsEnabled":true,"healthEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL, health: AcceptingHealth())
    }

    /// A stand-in for the HealthKit writer. Not a convenience: pointed at the
    /// real one, this test asks a simulator's HealthKit to store a workout and
    /// waits for an answer that never comes — the whole process sits idle
    /// until the runner gives up. That is what stopped CI finishing on any
    /// branch from 2026-08-17 (#164). Nothing here is under test; what is
    /// under test is the estimate the backfill computes before it calls this.
    private struct AcceptingHealth: WorkoutHealthWriting {
        var isAvailable: Bool { true }
        func requestAuthorization() async -> Bool { true }
        func latestBodyMassKg() async -> Double? { nil }
        func profile() async -> BodyProfile { BodyProfile() }
        func restingKcal(start: Date, end: Date) async -> Double? { nil }
        func foreignWorkoutIntervals(start: Date, end: Date) async -> [DateInterval] { [] }
        func saveWorkout(start: Date, end: Date, activeKcal: Double?,
                         journalID: String) async -> Bool {
            start < end
        }
    }

    func testACorruptExerciseSnapshotCannotTrapTheDurationEstimate() async throws {
        // The Health export estimates duration from the stored exercises.
        let s = try healthStore(records: """
        {"sessionNumber":1,"date":0,"result":"plan","totalLevelAfter":180,
         "exercises":[{"pattern":"squat","name":"x","tier":1,"unit":"reps",
                       "load":9223372036854775807,"perSide":true,
                       "sets":9223372036854775807,"restSetSec":9223372036854775807,
                       "restExerciseSec":60,"display":"x"}]}
        """)
        // Reached through the Health backfill, the only caller of the estimate.
        await s.backfillHealth()
        XCTAssertEqual(s.records.count, 1, "the backfill runs the estimate without trapping")
    }

    // MARK: - The valid domain is untouched

    func testAnOrdinaryRecordDecodesExactlyAsBefore() throws {
        let s = try store(records: """
        {"sessionNumber":12,"date":0,"result":"more","totalProgressAfter":180,
         "positionsAfter":["squat",{"variation":3,"sets":3,"dose":11}],
         "durationSec":2100,
         "actuals":["squat",14],"healthExported":true}
        """)
        let r = try XCTUnwrap(s.records.first)
        XCTAssertEqual(r.sessionNumber, 12)
        XCTAssertEqual(r.result, .more)
        XCTAssertEqual(r.totalProgressAfter, 180)
        XCTAssertEqual(r.positionsAfter?[.squat],
                       RecordedPosition(variation: 3, sets: 3, dose: 11))
        XCTAssertEqual(r.durationSec, 2100)
        XCTAssertEqual(r.actuals?[.squat], 14)
        XCTAssertEqual(r.healthExported, true)
    }

    /// The per-set detail is journal too, so it is sanitized like every other
    /// number in the file: values clamped, and an array longer than any
    /// exercise has sets cut back to one.
    func testPerSetFactsAreSanitizedLikeTheRest() throws {
        let s = try store(records: """
        {"sessionNumber":3,"date":0,"result":"plan","totalProgressAfter":40,
         "actuals":["squat",13],
         "setActuals":["squat",[15,15,10,-9223372036854775808,7,7,7,7]]}
        """)
        let r = try XCTUnwrap(s.records.first)
        XCTAssertEqual(r.actuals?[.squat], 13)
        XCTAssertEqual(r.setActuals?[.squat], [15, 15, 10, 0, 7],
                       "cut to the sets an exercise can have, every value inside its range")
    }

    func testARecordWithoutPerSetFactsStillDecodes() throws {
        let s = try store(records: """
        {"sessionNumber":4,"date":0,"result":"less","totalProgressAfter":30,
         "actuals":["squat",11]}
        """)
        let r = try XCTUnwrap(s.records.first)
        XCTAssertEqual(r.actuals?[.squat], 11)
        XCTAssertNil(r.setActuals, "records written before the per-set shape keep reading true")
    }

    func testARecordRoundTripsThroughEncodeAndDecode() throws {
        let original = WorkoutRecord(sessionNumber: 7, date: Date(timeIntervalSince1970: 1_000),
                                     result: .plan, totalProgressAfter: 99,
                                     actuals: [.squat: 13], setActuals: [.squat: [15, 15, 10]],
                                     probes: [.pull: 4],
                                     positionsAfter: [.squat: RecordedPosition(
                                         variation: 3, sets: 3, dose: 11)],
                                     durationSec: 1800)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutRecord.self, from: data), original)
    }

    /// The field the wave added, from both sides. A file written before it
    /// carries no key at all and must keep reading true — the whole reason
    /// every field added to a persisted type is optional with a nil default —
    /// and a hand-edited number is clamped like every other one in this file,
    /// because the journal is an input too.
    func testAProbeNumberIsReadBackAndAHandEditedOneIsClamped() throws {
        let s = try store(records: """
        {"sessionNumber":4,"date":0,"result":"plan","probes":["pull",5]}
        """)
        XCTAssertEqual(try XCTUnwrap(s.records.first).probes?[.pull], 5)

        let older = try store(records: """
        {"sessionNumber":4,"date":0,"result":"plan","actuals":["squat",11]}
        """)
        XCTAssertNil(try XCTUnwrap(older.records.first).probes,
                     "a record written before the field must not invent one")

        let absurd = try store(records: """
        {"sessionNumber":4,"date":0,"result":"plan","probes":["pull",-9223372036854775808]}
        """)
        XCTAssertEqual(try XCTUnwrap(absurd.records.first).probes?[.pull], 0,
                       "a number out of range is clamped, not carried into arithmetic")
    }
}
