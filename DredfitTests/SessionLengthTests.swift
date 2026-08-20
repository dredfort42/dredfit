//
//  SessionLengthTests.swift
//  DredfitTests
//
//  v2.17 (spec §28.3, #136): the trainee's own answer to "how long do I
//  have today". The engine owns the trimming; this covers the app's half —
//  that the answer is stored, survives a relaunch, reaches the plan, and
//  buys its minutes out of the sets rather than out of the levels.
//
//  v2.24 (spec §35.3, #136/#147): and that the answer nobody gave is 45
//  minutes rather than "no limit". The budget shipped switched off, so it
//  protected only the people who went looking for it while everyone else kept
//  being handed a longer workout every month.
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
    /// Seeded through the state file, the way the app itself would load it —
    /// and with no `timeBudgetChosen` key, exactly like a file written before
    /// v2.24.
    private func advancedStore(counter: Int = 0, level: Int = 40,
                               records: String = "") throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(counter),"levels":[\(levels)],"failStreak":[\(zeros)]},
         "records":[\(records)],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    /// One finished workout, so the store counts as an existing install.
    private static let oneRecord =
        "{\"sessionNumber\":1,\"date\":0,\"result\":\"plan\",\"totalLevelAfter\":360}"

    // MARK: - The answer itself

    /// v2.24: RE-MARKED from "no limit" to 45, with the cause. "Nothing may
    /// change for someone who never opens the setting" was the v2.17 promise,
    /// and the audit found it was the wrong promise: the app never stops
    /// lengthening the workout, so leaving the handle off by default protected
    /// only the people who went looking for it.
    func testAnInstallThatNeverChoseGetsTheDefaultBudget() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.engineState.timeBudgetMin, AppStore.defaultTimeBudgetMin)
        XCTAssertEqual(AppStore.defaultTimeBudgetMin, 45)
        XCTAssertFalse(store.settings.timeBudgetChosen,
                       "a default is not a choice")
    }

    /// The population the default is really for: a file written before the flag
    /// existed. No key means never chose, which means 45.
    func testAPreV224FileGetsTheDefaultToo() throws {
        let store = try advancedStore()
        XCTAssertEqual(store.engineState.timeBudgetMin, 45)
        XCTAssertLessThanOrEqual(store.nextSession.estimatedTotalMin, 45)
    }

    /// Choosing "no limit" is a decision, and a decision must survive the next
    /// launch — otherwise the default would quietly overwrite it forever.
    func testChoosingNoLimitIsRememberedAsAChoice() throws {
        let store = try advancedStore()
        store.setTimeBudget(0)
        XCTAssertTrue(store.settings.timeBudgetChosen)
        let relaunched = AppStore(storageURL: tempURL)
        XCTAssertEqual(relaunched.engineState.timeBudgetMin, 0,
                       "the default must not reclaim a deliberate 'no limit'")
    }

    /// Even choosing the value already in force counts: 45 is the default, and
    /// tapping it is how a trainee says "yes, this one".
    func testChoosingTheDefaultValueStillCountsAsChoosing() throws {
        let store = try advancedStore()
        store.setTimeBudget(45)
        XCTAssertTrue(store.settings.timeBudgetChosen)
        XCTAssertEqual(AppStore(storageURL: tempURL).engineState.timeBudgetMin, 45)
    }

    // MARK: - Reset keeps it (spec §35.3)

    func testResettingProgressKeepsTheBudget() throws {
        let store = try advancedStore()
        store.setTimeBudget(35)
        store.resetProgress()
        XCTAssertEqual(store.engineState.timeBudgetMin, 35,
                       "starting the levels over is not a request for longer workouts")
        XCTAssertTrue(store.settings.timeBudgetChosen)
        XCTAssertEqual(AppStore(storageURL: tempURL).engineState.timeBudgetMin, 35)
    }

    func testResettingProgressKeepsADeliberateNoLimit() throws {
        let store = try advancedStore()
        store.setTimeBudget(0)
        store.resetProgress()
        XCTAssertEqual(store.engineState.timeBudgetMin, 0)
        XCTAssertEqual(AppStore(storageURL: tempURL).engineState.timeBudgetMin, 0)
    }

    // MARK: - The one-off line (spec §35.3)

    func testTheWhatsNewLineShowsOnceAndOnlyToExistingInstalls() throws {
        let fresh = AppStore(storageURL: tempURL)
        XCTAssertFalse(fresh.shouldShowBudgetDefaultNotice,
                       "a first launch has no 'new' to be told about")
        // And it must not turn up later either: a fresh install closes the line
        // at birth, so finishing a workout — or relaunching — cannot revive it.
        fresh.setSounds(fresh.settings.soundsEnabled)   // any persist()
        XCTAssertFalse(AppStore(storageURL: tempURL).shouldShowBudgetDefaultNotice,
                       "a fresh install must never be shown an upgrade notice")

        let existing = try advancedStore(records: Self.oneRecord)
        XCTAssertTrue(existing.shouldShowBudgetDefaultNotice)
        existing.markBudgetDefaultNoticeSeen()
        XCTAssertFalse(existing.shouldShowBudgetDefaultNotice)
        XCTAssertFalse(AppStore(storageURL: tempURL).shouldShowBudgetDefaultNotice,
                       "and it does not come back on the next launch")
    }

    func testChoosingALengthAlsoRetiresTheLine() throws {
        let store = try advancedStore(records: Self.oneRecord)
        XCTAssertTrue(store.shouldShowBudgetDefaultNotice)
        store.setTimeBudget(35)
        XCTAssertFalse(store.shouldShowBudgetDefaultNotice,
                       "someone who has already been to the setting needs no announcement")
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

    /// v2.24: RE-MARKED from all three rungs to the two above the shortest,
    /// with the cause. Since §35.2 the budget never drops a movement, so the
    /// tightest rung is a target rather than a promise: high up the scale six
    /// movements at two sets each already run past 20 minutes. 35 and 45 still
    /// fit everywhere, and they are pinned here without any hedge.
    func testTheRungsAboveTheShortestAreHonouredExactly() throws {
        for rung in [35, 45] {
            let store = try advancedStore()
            store.setTimeBudget(rung)
            XCTAssertLessThanOrEqual(store.nextSession.estimatedTotalMin, Double(rung),
                                     "the \(rung)-minute answer was not honoured")
        }
    }

    /// And what the shortest rung DOES promise: everything it can take, taken —
    /// every exercise on the floor — with the movement list untouched.
    func testTheShortestRungTakesEverySetItCanAndNoMovements() throws {
        for counter in 0..<12 {
            let store = try advancedStore(counter: counter)
            let full = store.nextSession.exercises.map(\.pattern)
            store.setTimeBudget(20)
            let short = store.nextSession
            XCTAssertEqual(short.exercises.map(\.pattern), full,
                           "session \(counter + 1) lost a movement to the clock")
            if short.estimatedTotalMin > 20 {
                XCTAssertTrue(short.exercises.allSatisfy { $0.sets == EngineConfig.setsFloor },
                              "session \(counter + 1) ran long without reaching the floor")
            }
        }
    }

    func testTheBudgetCostsSetsNotLevels() throws {
        let store = try advancedStore()
        store.setTimeBudget(0)          // the unbudgeted plan to compare against
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
