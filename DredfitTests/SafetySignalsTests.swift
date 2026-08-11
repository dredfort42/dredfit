//
//  SafetySignalsTests.swift
//  DredfitTests
//
//  The quiet signals of issues #100 and #98: the per-movement pain trend
//  and the run of consecutive training days. Both are derived from the
//  journal — nothing is persisted, so the same journal must always produce
//  the same answers.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SafetySignalsTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-signals-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now))!
            .addingTimeInterval(10 * 3600)
    }

    // MARK: - Pain trend (#100)

    /// The pull is in every session, so consecutive reports build the streak
    /// directly — and one clean appearance takes it back to zero.
    func testPainStreakCountsReportsAndResetsOnACleanAppearance() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              discomfort: [.pull], date: day(-6))
        XCTAssertEqual(store.discomfortStreak(.pull), 1)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              discomfort: [.pull], date: day(-4))
        XCTAssertEqual(store.discomfortStreak(.pull), 2)
        store.completeWorkout(session: store.nextSession, result: .plan, date: day(-2))
        XCTAssertEqual(store.discomfortStreak(.pull), 0,
                       "a clean appearance ends the trend the same day")
    }

    /// The streak counts APPEARANCES: a session the movement was not part of
    /// neither breaks nor extends the run — same arithmetic as the freeze.
    func testPainStreakIgnoresSessionsWithoutTheMovement() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan, date: day(-8))
        store.completeWorkout(session: store.nextSession, result: .plan, date: day(-6))
        // Session 3 (counter 2) contains the calf; session 4 (counter 3) does not.
        var session = store.nextSession
        XCTAssertTrue(session.exercises.contains { $0.pattern == .calf })
        store.completeWorkout(session: session, result: .plan,
                              discomfort: [.calf], date: day(-4))
        session = store.nextSession
        XCTAssertFalse(session.exercises.contains { $0.pattern == .calf })
        store.completeWorkout(session: session, result: .plan, date: day(-2))
        XCTAssertEqual(store.discomfortStreak(.calf), 1,
                       "a session without the calf must not break its run")
    }

    /// A record too old to know its exercises (pre-1.4) ends the walk
    /// instead of guessing.
    func testLegacyRecordEndsThePainWalk() throws {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              discomfort: [.pull], date: day(-4))
        store.completeWorkout(session: store.nextSession, result: .plan,
                              discomfort: [.pull], date: day(-2))

        // Prepend a legacy record — no exercises, the pre-1.4 shape.
        var json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: tempURL)) as! [String: Any]
        var records = json["records"] as! [[String: Any]]
        records.insert(["sessionNumber": 0, "date": -86400.0,
                        "result": "plan", "totalLevelAfter": 5], at: 0)
        json["records"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: tempURL)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.records.count, 3, "the legacy record must decode")
        XCTAssertEqual(reloaded.discomfortStreak(.pull), 2,
                       "the walk counts the modern records and stops at the legacy one")
    }

    // MARK: - Consecutive training days (#98)

    func testConsecutiveDaysCountRunsAndBreakOnAGap() {
        let store = AppStore(storageURL: tempURL)
        for offset in [-5, -4, -2, -1] {
            store.completeWorkout(session: store.nextSession, result: .plan,
                                  date: day(offset))
        }
        XCTAssertEqual(store.consecutiveTrainingDays(endingOn: day(-1)), 2,
                       "the gap on day −3 breaks the run")
        XCTAssertEqual(store.consecutiveTrainingDays(endingOn: day(-4)), 2)
        XCTAssertEqual(store.consecutiveTrainingDays(endingOn: day(-3)), 0,
                       "an untrained day carries no run")
    }

    func testTwoWorkoutsOnOneDayCountOnce() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan, date: day(-1))
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: day(-1).addingTimeInterval(3600))
        XCTAssertEqual(store.consecutiveTrainingDays(endingOn: day(-1)), 1,
                       "days are counted, not records")
    }

    /// The offer appears exactly when today would be the fourth day in a
    /// row, and never once today's workout is done — it is an offer before
    /// the fact, not a remark after it.
    func testLongRunOfferThreshold() {
        let two = AppStore(storageURL: tempURL)
        for offset in [-2, -1] {
            two.completeWorkout(session: two.nextSession, result: .plan, date: day(offset))
        }
        XCTAssertEqual(two.wouldBeConsecutiveDay, 3)
        XCTAssertFalse(two.todayWouldExtendALongRun, "a third day in a row is fine")

        let threeURL = tempURL.deletingPathExtension().appendingPathExtension("three.json")
        defer { try? FileManager.default.removeItem(at: threeURL) }
        let three = AppStore(storageURL: threeURL)
        for offset in [-3, -2, -1] {
            three.completeWorkout(session: three.nextSession, result: .plan, date: day(offset))
        }
        XCTAssertEqual(three.wouldBeConsecutiveDay, 4)
        XCTAssertTrue(three.todayWouldExtendALongRun,
                      "a would-be fourth day earns the one quiet sentence")

        three.completeWorkout(session: three.nextSession, result: .plan)
        XCTAssertFalse(three.todayWouldExtendALongRun,
                       "once today is trained the offer is moot")
    }
}
