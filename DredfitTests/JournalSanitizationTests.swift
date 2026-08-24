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
final class JournalSanitizationTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-journal-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    private func store(records: String, levels: Int = 20) throws -> AppStore {
        let lv = Pattern.allCases.map { "\"\($0.rawValue)\",\(levels)" }.joined(separator: ",")
        let zeros = Pattern.allCases.map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":11,"levels":[\(lv)],"failStreak":[\(zeros)]},
         "records":[\(records)],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    // MARK: - Numbers that would trap the arithmetic downstream

    func testAStoredLevelOutsideTheScaleCannotTrapTheRetrospective() throws {
        // Retrospective subtracts the stored level from the current one.
        let s = try store(records: """
        {"sessionNumber":1,"date":0,"result":"plan","totalLevelAfter":180,
         "levelsAfter":["squat",-9223372036854775808,"pull",9223372036854775807]}
        """)
        XCTAssertEqual(s.records.first?.levelsAfter?[.squat], 0)
        XCTAssertEqual(s.records.first?.levelsAfter?[.pull], EngineConfig.levelMax)
        // The screen that does the subtraction still renders.
        XCTAssertNotNil(Retrospective.make(records: s.records,
                                           currentLevels: s.engineState.levels))
    }

    func testATotalOutsideAnyRealHistoryCannotTrapTheWeekSummary() throws {
        let s = try store(records: """
        {"sessionNumber":9223372036854775807,"date":0,"result":"plan",
         "totalLevelAfter":-9223372036854775808},
        {"sessionNumber":2,"date":1000,"result":"plan","totalLevelAfter":9223372036854775807}
        """)
        XCTAssertEqual(s.records.first?.totalLevelAfter, 0)
        XCTAssertEqual(s.records.first?.sessionNumber, EngineConfig.countMax)
        XCTAssertEqual(s.records.last?.totalLevelAfter, EngineConfig.countMax)
        XCTAssertNotNil(s.weekSummary(for: .now))
    }

    func testACorruptDateCannotTrapTheGapMath() throws {
        // Int(elapsed / 86_400) traps when the quotient is past Int's range —
        // it does not saturate. A date of 1e300 seconds decodes cleanly.
        let s = try store(records: """
        {"sessionNumber":1,"date":1e300,"result":"plan","totalLevelAfter":180}
        """)
        XCTAssertNotNil(s.gapDays(), "a nonsense date yields a number, not a crash")
        XCTAssertEqual(s.gapDays(), 0, "a workout in the far future is not a break")
        _ = s.recentGaps
        _ = s.shouldOfferComeback()

        let past = try store(records: """
        {"sessionNumber":1,"date":-1e300,"result":"plan","totalLevelAfter":180}
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
        func requestWriteAuthorization() async -> Bool { true }
        func saveWorkout(start: Date, end: Date) async -> Bool { start < end }
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
        {"sessionNumber":12,"date":0,"result":"more","totalLevelAfter":180,
         "levelsAfter":["squat",20,"pull",22],"durationSec":2100,
         "actuals":["squat",14],"healthExported":true}
        """)
        let r = try XCTUnwrap(s.records.first)
        XCTAssertEqual(r.sessionNumber, 12)
        XCTAssertEqual(r.result, .more)
        XCTAssertEqual(r.totalLevelAfter, 180)
        XCTAssertEqual(r.levelsAfter?[.squat], 20)
        XCTAssertEqual(r.levelsAfter?[.pull], 22)
        XCTAssertEqual(r.durationSec, 2100)
        XCTAssertEqual(r.actuals?[.squat], 14)
        XCTAssertEqual(r.healthExported, true)
    }

    /// The per-set detail is journal too, so it is sanitized like every other
    /// number in the file: values clamped, and an array longer than any
    /// exercise has sets cut back to one.
    func testPerSetFactsAreSanitizedLikeTheRest() throws {
        let s = try store(records: """
        {"sessionNumber":3,"date":0,"result":"plan","totalLevelAfter":40,
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
        {"sessionNumber":4,"date":0,"result":"less","totalLevelAfter":30,
         "actuals":["squat",11]}
        """)
        let r = try XCTUnwrap(s.records.first)
        XCTAssertEqual(r.actuals?[.squat], 11)
        XCTAssertNil(r.setActuals, "records written before the per-set shape keep reading true")
    }

    func testARecordRoundTripsThroughEncodeAndDecode() throws {
        let original = WorkoutRecord(sessionNumber: 7, date: Date(timeIntervalSince1970: 1_000),
                                     result: .plan, totalLevelAfter: 99,
                                     actuals: [.squat: 13], setActuals: [.squat: [15, 15, 10]],
                                     levelsAfter: [.squat: 11], durationSec: 1800)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutRecord.self, from: data), original)
    }
}
