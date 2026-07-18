//
//  ComebackTests.swift
//  DredfitTests
//
//  The app-layer half of the v1.5 comeback: when the card is offered, what
//  each answer does, and that the question is asked once per break.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class ComebackTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-comeback-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A store whose single journal entry is `daysAgo` old, with every pattern
    /// parked at `level`.
    private func storeWithLastWorkout(daysAgo: Int, level: Int = 20) throws -> AppStore {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        // Dates encode as seconds since the reference date by default.
        let stamp = date.timeIntervalSinceReferenceDate
        let json = """
        {"engineState":{"counter":11,"levels":[\(levels)],"failStreak":[\(zeros)]},
         "records":[{"sessionNumber":11,"date":\(stamp),"result":"plan","totalLevelAfter":\(level * 9)}],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    // MARK: - When the card appears

    func testNoCardBelowTwoWeeks() throws {
        for days in [0, 1, 7, 13] {
            let store = try storeWithLastWorkout(daysAgo: days)
            XCTAssertFalse(store.shouldOfferComeback(), "\(days) days is not a break yet")
        }
    }

    func testCardAppearsFromFourteenDays() throws {
        for days in [14, 30, 200] {
            let store = try storeWithLastWorkout(daysAgo: days)
            XCTAssertTrue(store.shouldOfferComeback(), "\(days) days should offer the card")
        }
    }

    func testNoCardWithoutHistory() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertFalse(store.shouldOfferComeback(),
                       "a fresh install has nothing to come back from")
        XCTAssertNil(store.gapDays())
    }

    func testGapIsCountedInWholeCalendarDays() throws {
        let store = try storeWithLastWorkout(daysAgo: 20)
        XCTAssertEqual(store.gapDays(), 20)
    }

    // MARK: - What the answers do

    func testStartEasierLowersLevelsAndClosesTheQuestion() throws {
        let store = try storeWithLastWorkout(daysAgo: 35, level: 20)
        XCTAssertEqual(store.comebackDrop(), 3, "35 days is a three-step drop")

        store.acceptComeback()

        XCTAssertEqual(store.engineState.levels[.pull], 17)
        XCTAssertEqual(store.engineState.counter, 11, "a comeback is not a workout")
        XCTAssertEqual(store.records.count, 1, "nothing is written to the journal")
        XCTAssertFalse(store.shouldOfferComeback(), "the question is answered for this break")
    }

    func testLeaveAsItWasChangesNothingButStillCloses() throws {
        let store = try storeWithLastWorkout(daysAgo: 35, level: 20)

        store.declineComeback()

        XCTAssertEqual(store.engineState.levels[.pull], 20, "levels untouched")
        XCTAssertFalse(store.shouldOfferComeback(), "but the card does not come back")
    }

    func testDecisionSurvivesRelaunch() throws {
        let store = try storeWithLastWorkout(daysAgo: 40)
        store.declineComeback()

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertFalse(reloaded.shouldOfferComeback(),
                       "the answer is persisted, not just held in memory")
    }

    /// The stamp is keyed on the last workout's date, so it expires by itself:
    /// train once, take another break, and the card is offered again.
    func testTheQuestionIsAskedAgainAfterTheNextWorkout() throws {
        let store = try storeWithLastWorkout(daysAgo: 40)
        store.declineComeback()
        XCTAssertFalse(store.shouldOfferComeback())

        // A workout happens, then another long break.
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: Calendar.current.date(byAdding: .day, value: -20, to: .now)!)
        XCTAssertTrue(store.shouldOfferComeback(),
                      "a new break is a new question")
    }

    // MARK: - Fresh start

    func testFreshStartOnlyOfferedAfterHalfAYear() throws {
        XCTAssertFalse(try storeWithLastWorkout(daysAgo: 100).offersFreshStart())
        XCTAssertTrue(try storeWithLastWorkout(daysAgo: 180).offersFreshStart())
    }

    func testFreshStartResetsLevelsButKeepsHistoryAndTheBar() throws {
        let store = try storeWithLastWorkout(daysAgo: 200, level: 30)
        store.setHasBar(true)

        store.resetProgress()

        XCTAssertEqual(store.engineState.levels[.pull], 0, "levels back to the beginning")
        XCTAssertEqual(store.engineState.counter, 0)
        XCTAssertEqual(store.records.count, 1, "the journal survives")
        XCTAssertTrue(store.engineState.hasBar,
                      "the pull-up bar did not disappear from the doorway")
    }

    // MARK: - Migration

    /// A v1.4 file knows nothing about comebacks and must load unchanged.
    func testV14FileLoadsWithComebackDefaults() throws {
        let v14 = """
        {"engineState":{"counter":6,
          "levels":["squat",9,"push_h",8,"hinge",7,"pull",6,"push_v",5,"lunge",4,
                    "core_anti_ext",3,"core_rot",2,"calf",1,"pull_bar",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",1,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0,"pull_bar",0]},
         "records":[],
         "settings":{"restWeekdays":[3],"soundsEnabled":false,
                     "reminderEnabled":true,"reminderHour":18,"reminderMinute":45,
                     "healthEnabled":true,"healthExportedThrough":5,
                     "onboardingCompleted":true}}
        """
        try Data(v14.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)

        // everything v1.4 knew survives
        XCTAssertEqual(store.settings.restWeekdays, [3])
        XCTAssertEqual(store.settings.reminderHour, 18)
        XCTAssertEqual(store.settings.reminderMinute, 45)
        XCTAssertTrue(store.settings.healthEnabled)
        XCTAssertEqual(store.settings.healthExportedThrough, 5)
        XCTAssertTrue(store.settings.onboardingCompleted)
        XCTAssertEqual(store.engineState.levels[.pull], 6)
        XCTAssertEqual(store.engineState.failStreak[.pull], 1)
        // and the new field defaults to "never asked"
        XCTAssertNil(store.settings.comebackDecidedFor)
    }

    func testComebackFieldSurvivesReload() throws {
        let store = try storeWithLastWorkout(daysAgo: 30)
        store.acceptComeback()
        let stamped = store.settings.comebackDecidedFor

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.settings.comebackDecidedFor, stamped)
    }
}
