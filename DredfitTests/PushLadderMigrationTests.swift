//
//  The app half of the ladder change. The library
//  reshuffle is silent by design — the stored level keeps its number, so the
//  only thing an existing trainee notices is that the movement at that level
//  is easier than the one they closed with. These tests are the migration:
//  there is no migration code, and that is the claim being checked.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class PushLadderMigrationTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-ladder-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A journal written by an older build, parked at the given push_v level.
    private func storeFromBefore(pushV level: Int) throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\($0 == .pushV ? level : 12)" }.joined(separator: ",")
        let zeros = Pattern.allCases.map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":40,"levels":[\(levels)],"failStreak":[\(zeros)]},
         "records":[{"sessionNumber":40,"date":0,"result":"plan","totalLevelAfter":180}],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    private func pushV(_ store: AppStore) -> SessionExercise? {
        store.nextSession.exercises.first { $0.pattern == .pushV }
    }

    func testAStoredLevelKeepsItsNumber() throws {
        for level in [16, 24, 31, 47] {
            let store = try storeFromBefore(pushV: level)
            XCTAssertEqual(store.engineState.levels[.pushV], level,
                           "the update must not rewrite anyone's level")
        }
    }

    func testTheMovementAtThatLevelIsTheEasierOne() throws {
        let midway = try storeFromBefore(pushV: 16)
        XCTAssertEqual(pushV(midway)?.name, "Feet-elevated pike push-up",
                       "where a kick-up into a handstand used to wait")

        let high = try storeFromBefore(pushV: 24)
        XCTAssertEqual(pushV(high)?.name, "Wall handstand push-up",
                       "and the handstand is now the top of the ladder")
    }

    func testTheDoseAtThatLevelIsUnchanged() throws {
        // Same level, same sets and reps as before the reshuffle — the library
        // moved, the encoding did not.
        let store = try storeFromBefore(pushV: 24)
        let ex = try XCTUnwrap(pushV(store))
        XCTAssertEqual(ex.tier, 4)
        XCTAssertEqual(ex.load, Level.decode(24).reps)
        XCTAssertEqual(ex.sets, Level.decode(24).sets)
    }

    /// The reason the owner chose "keep the number": the error can only fall
    /// on the safe side. Nobody opens the app to a plan harder than the one
    /// they finished with.
    func testNoStoredLevelBecomesHarderThanItWas() throws {
        let retired = ["Chest-to-wall handstand push-up"]
        for level in stride(from: 16, through: 47, by: 1) {
            let store = try storeFromBefore(pushV: level)
            let name = pushV(store)?.name
            XCTAssertNotNil(name)
            XCTAssertFalse(retired.contains(name ?? ""),
                           "level \(level) still resolves to a movement that left the library")
        }
    }
}
