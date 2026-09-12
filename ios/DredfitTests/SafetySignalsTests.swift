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
final class SafetySignalsTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-signals" }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now))!
            .addingTimeInterval(10 * 3600)
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

    // SNIPPED: the three pain-streak tests. The streak counted pain reports
    // over a movement's appearances, and there are none to count.
    //
    // The run-of-days signal, which is the other half of this suite, is
    // untouched — it never read the pain channel.
}
