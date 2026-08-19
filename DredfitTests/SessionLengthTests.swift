//
//  SessionLengthTests.swift
//  DredfitTests
//
//  v2.17 (spec §28.3, #136): the trainee's own answer to "how long do I
//  have today". The engine owns the trimming; this covers the app's half —
//  that the answer is stored, survives a relaunch, reaches the plan, and
//  buys its minutes out of the sets rather than out of the levels.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SessionLengthTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-budget-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A trainee well up the scale, where an unbudgeted session runs long.
    /// Seeded through the state file, the way the app itself would load it.
    private func advancedStore(counter: Int = 0, level: Int = 40) throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(counter),"levels":[\(levels)],"failStreak":[\(zeros)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    // MARK: - The answer itself

    func testAFreshInstallHasNoLimit() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.engineState.timeBudgetMin, 0,
                       "nothing may change for someone who never opens the setting")
    }

    func testTheChoiceSurvivesARelaunch() throws {
        let store = try advancedStore()
        store.setTimeBudget(35)
        XCTAssertEqual(AppStore(storageURL: tempURL).engineState.timeBudgetMin, 35)
    }

    func testNoLimitIsReachableAgain() throws {
        let store = try advancedStore()
        store.setTimeBudget(20)
        store.setTimeBudget(0)
        XCTAssertEqual(AppStore(storageURL: tempURL).engineState.timeBudgetMin, 0)
    }

    // MARK: - What it buys

    func testEveryRungKeepsTheSessionInsideIt() throws {
        for rung in [20, 35, 45] {
            let store = try advancedStore()
            store.setTimeBudget(rung)
            XCTAssertLessThanOrEqual(store.nextSession.estimatedTotalMin, Double(rung),
                                     "the \(rung)-minute answer was not honoured")
        }
    }

    func testTheShortestRungStillTrainsThreeMovements() throws {
        for counter in 0..<12 {
            let store = try advancedStore(counter: counter)
            store.setTimeBudget(20)
            XCTAssertGreaterThanOrEqual(store.nextSession.exercises.count, 3,
                                        "session \(counter + 1) fell below three movements")
        }
    }

    func testTheBudgetCostsSetsNotLevels() throws {
        let store = try advancedStore()
        let full = store.nextSession
        store.setTimeBudget(20)
        let short = store.nextSession

        for pattern in Pattern.allCases {
            XCTAssertEqual(store.engineState.levels[pattern], 40,
                           "\(pattern): choosing less time must not move a level")
        }
        for exercise in short.exercises {
            guard let same = full.exercises.first(where: { $0.pattern == exercise.pattern }) else {
                return XCTFail("the short plan invented \(exercise.pattern)")
            }
            XCTAssertEqual(exercise.load, same.load,
                           "\(exercise.pattern): the dose is the level's, not the clock's")
            XCTAssertLessThanOrEqual(exercise.sets, same.sets)
        }
        XCTAssertLessThan(short.estimatedTotalMin, full.estimatedTotalMin)
    }
}
