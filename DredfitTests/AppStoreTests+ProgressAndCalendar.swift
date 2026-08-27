//
//  The progress curve, week summary, pull-up bar branch and calendar/rest-day
//  logic, moved out of AppStoreTests.swift to keep it under the linter's file
//  and type-body ceilings. Grouped here because each reads the same journal
//  from a different angle — as a curve, as an ISO week, as a next-training
//  date — rather than testing persistence or migration itself. The code
//  moved unchanged.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Level curve
extension AppStoreTests {

    func testProgressCurveIsCutAtTheGivenDate() throws {
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: nil)
        _ = store.completeWorkout(session: store.nextSession, result: .plan)

        XCTAssertEqual(store.progressCurve(), store.records.compactMap(\.totalProgressAfter))
        XCTAssertEqual(store.progressCurve(through: .distantPast), [],
                       "nothing was recorded before the cut, so there is no curve")
        XCTAssertEqual(store.progressCurve(through: .distantFuture).count,
                       store.records.count)
    }

    // MARK: - Week summary

    func testWeekSummaryUsesMondayFirstIsoWeeks() throws {
        let store = AppStore(storageURL: tempURL)
        // Sunday Jul 12, 2026 closes the ISO week Mon Jul 6 – Sun Jul 12.
        _ = store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 12))
        let sundaySteps = try XCTUnwrap(store.records.last?.totalProgressAfter)
        // Monday Jul 13 opens the next ISO week Mon Jul 13 – Sun Jul 19.
        _ = store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        _ = store.completeWorkout(session: store.nextSession, result: .more, date: date(2026, 7, 16))
        let last = try XCTUnwrap(store.records.last?.totalProgressAfter)

        // The week of Wed Jul 15 must contain ONLY the two Mon–Sun workouts.
        // A Sunday-first calendar (US default) would wrongly pull in Jul 12.
        let thisWeek = store.weekSummary(for: date(2026, 7, 15))
        XCTAssertEqual(thisWeek.workouts, 2,
                       "the Sunday-Jul-12 workout must fall in the previous ISO week")
        XCTAssertEqual(thisWeek.stepsDelta, last - sundaySteps,
                       "the delta counts from the last record before Monday")

        // The Sunday workout belongs to the previous ISO week on its own.
        let prevWeek = store.weekSummary(for: date(2026, 7, 12))
        XCTAssertEqual(prevWeek.workouts, 1, "Sunday closes the previous ISO week")
        XCTAssertEqual(prevWeek.stepsDelta, sundaySteps, "the first week counts from zero")
    }

    func testWeekSummaryEmptyWeekIsZero() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .more, date: date(2026, 7, 10))
        let week = store.weekSummary(for: date(2026, 7, 22))
        XCTAssertEqual(week, AppStore.WeekSummary(workouts: 0, stepsDelta: 0),
                       "a week without workouts must read 0 · +0, not carry old gains")
    }

    // MARK: - Pull-up bar

    func testHasBarPersistsAndDrivesAlternation() {
        let store = AppStore(storageURL: tempURL)
        store.setHasBar(true)
        // session 1 (counter 0) stays horizontal even with the bar on
        XCTAssertFalse(store.nextSession.exercises.contains { $0.pattern == .pullBar })
        store.completeWorkout(session: store.nextSession, result: .plan)
        // session 2 (counter 1) trains the vertical branch
        let second = store.nextSession
        XCTAssertTrue(second.exercises.contains { $0.pattern == .pullBar },
                      "with the bar on, the second session must swap in the vertical pull")
        XCTAssertFalse(second.exercises.contains { $0.pattern == .pull })

        // the toggle and the branch snapshot survive a reload
        store.completeWorkout(session: second, result: .more)
        // The cross-credit moves the branch on pull sessions too, so the level
        // is read from the engine rather than spelled out — this test is about
        // the snapshot and the reload.
        let barPosition = store.engineState.position(.pullBar)
        XCTAssertEqual(store.records.last?.positionsAfter?[.pullBar],
                       RecordedPosition(variation: barPosition.variation,
                                        sets: barPosition.sets, dose: barPosition.dose),
                       "the journal snapshot must include the pull_bar position")
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertTrue(reloaded.engineState.hasBar)
        XCTAssertEqual(reloaded.engineState.position(.pullBar), barPosition)

        // turning the bar off freezes the branch but keeps its progress
        reloaded.setHasBar(false)
        XCTAssertFalse(reloaded.nextSession.exercises.contains { $0.pattern == .pullBar })
        XCTAssertEqual(reloaded.engineState.position(.pullBar), barPosition,
                       "turning the bar off keeps the branch where it was")
    }

    // MARK: - Calendar logic

    func testIsRestDayOnSundays() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.isRestDay(date(2026, 7, 19)), "Sunday should be a rest day")
        XCTAssertFalse(store.isRestDay(date(2026, 7, 16)), "Thursday is not a rest day")
    }

    func testNextTrainingDateFromFreeWeekday() {
        let store = AppStore(storageURL: tempURL)
        let thursday = date(2026, 7, 16)
        XCTAssertEqual(store.nextTrainingDate(from: thursday), thursday,
                       "no workout today and not a rest day → today")
    }

    func testNextTrainingDateSkipsSunday() {
        let store = AppStore(storageURL: tempURL)
        let sunday = date(2026, 7, 19)
        let next = store.nextTrainingDate(from: sunday)
        XCTAssertTrue(Calendar.current.isDate(next, inSameDayAs: date(2026, 7, 20)),
                      "from Sunday the next workout is on Monday")
    }

    func testNextTrainingDateAfterDoneSaturdaySkipsToMonday() {
        let store = AppStore(storageURL: tempURL)
        let saturday = date(2026, 7, 18)
        store.completeWorkout(session: store.nextSession, result: .plan, date: saturday)
        let next = store.nextTrainingDate(from: saturday)
        XCTAssertTrue(Calendar.current.isDate(next, inSameDayAs: date(2026, 7, 20)),
                      "Saturday completed → next on Monday (Sun is a rest day)")
    }

    func testDoneTodayAndRecordLookup() {
        let store = AppStore(storageURL: tempURL)
        let day = date(2026, 7, 16)
        store.completeWorkout(session: store.nextSession, result: .plan, date: day)
        XCTAssertTrue(store.isDone(on: day))
        XCTAssertFalse(store.isDone(on: date(2026, 7, 17)),
                       "the next day, done should reset without migrations")
        XCTAssertNotNil(store.record(on: day))
        XCTAssertNil(store.record(on: date(2026, 7, 15)))
    }

    // MARK: - A full month of workouts

    func testMonthOfWorkoutsAccumulatesConsistently() {
        let store = AppStore(storageURL: tempURL)
        var day = date(2026, 7, 1)
        var completed = 0
        while completed < 24 {
            if !store.isRestDay(day) {
                store.completeWorkout(session: store.nextSession, result: .plan, date: day)
                completed += 1
            }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        XCTAssertEqual(store.records.count, 24)
        XCTAssertEqual(store.records.map(\.sessionNumber), Array(1...24))
        let chart = store.records.compactMap(\.totalProgressAfter)
        XCTAssertEqual(chart, chart.sorted(), "the total must not drop with \"on plan\"")
        XCTAssertEqual(AppStore(storageURL: tempURL).records.count, 24)
    }
}
