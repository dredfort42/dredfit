//
//  WidgetTimelineTests.swift
//  DredfitTests
//
//  The widget side of the snapshot contract. The provider's mapping and the
//  views' word choices compile straight into this test bundle (see the
//  DredfitTests membership exceptions on the DredfitWidgets and Shared
//  folders), so WidgetSnapshot here is the widget's own type — no app import,
//  no @testable, exactly what the extension executes.
//
//  What must hold: entries start today, every day speaks its own pre-computed
//  label, and the week tally never crosses into a week it does not describe —
//  the stale "Next workout today" on a rest-day entry is the bug this file
//  keeps out.
//

import XCTest
import SwiftUI

@MainActor
final class WidgetTimelineTests: XCTestCase {

    // MARK: - Fixtures

    private var iso: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = Calendar.current.timeZone
        return cal
    }

    /// Monday of the current week — the anchor the app writes snapshots from.
    private var monday: Date { iso.dateInterval(of: .weekOfYear, for: .now)!.start }

    private func date(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: monday)!
    }

    private func day(_ offset: Int, _ status: WidgetSnapshot.Day.Status,
                     label: String? = nil) -> WidgetSnapshot.Day {
        WidgetSnapshot.Day(date: date(offset), status: status,
                           sessionNumber: nil, nextLabel: label)
    }

    /// Two weeks the way WidgetBridge writes them: the write week fully
    /// statused, the next week planned, per-day labels where a non-workout
    /// day would need one. "Today" is Wednesday of the write week.
    private func fixture() -> (snapshot: WidgetSnapshot, today: Date) {
        let days: [WidgetSnapshot.Day] = [
            day(0, .done), day(1, .unmarked),
            day(2, .rest, label: "tomorrow"),          // today
            day(3, .workout), day(4, .workout), day(5, .workout),
            day(6, .rest, label: "tomorrow"),
            day(7, .workout), day(8, .workout),
            day(9, .rest, label: "tomorrow"),
            day(10, .workout), day(11, .workout), day(12, .workout),
            day(13, .rest, label: "on Monday"),
        ]
        let snapshot = WidgetSnapshot(
            days: days,
            totalLevel: 27,
            week: .init(workouts: 3, levelsDelta: 6),
            weekStart: monday,
            planSessionNumber: 12,
            planMinutes: 34,
            plan: [.init(name: "Push-up", detail: "3×12")])
        return (snapshot, date(2))
    }

    // MARK: - The timeline mapping

    func testEntriesStartTodayAndKeepThePastInTheWeekStrip() {
        let (snapshot, today) = fixture()
        let entries = TodayProvider().entries(from: snapshot, today: today)

        XCTAssertEqual(entries.count, 12, "past days are dropped from the timeline")
        XCTAssertEqual(entries.first?.date, today)
        // The strip still shows the whole calendar week, done Monday included.
        XCTAssertEqual(entries.first?.week.map(\.date), (0..<7).map(date))
        // An entry in the second week draws the second week around itself.
        let nextMonday = entries.first { $0.date == date(7) }
        XCTAssertEqual(nextMonday?.week.map(\.date), (7..<14).map(date))
    }

    func testEveryEntrySpeaksItsOwnLabel() {
        let (snapshot, today) = fixture()
        let entries = TodayProvider().entries(from: snapshot, today: today)

        for entry in entries {
            let source = snapshot.days.first { $0.date == entry.date }
            XCTAssertEqual(entry.nextLabel, source?.nextLabel,
                           "\(entry.date): the entry must carry its own day's label")
        }
        // And concretely: the far rest day says its own word, not today's.
        XCTAssertEqual(entries.first { $0.date == date(13) }?.nextLabel, "on Monday")
        XCTAssertEqual(entries.first?.nextLabel, "tomorrow")
    }

    func testWeekTallyStaysInsideItsWeek() {
        let (snapshot, today) = fixture()
        let entries = TodayProvider().entries(from: snapshot, today: today)

        for entry in entries {
            if entry.date < date(7) {
                XCTAssertNotNil(entry.summary,
                                "\(entry.date): the write week keeps its tally")
            } else {
                XCTAssertNil(entry.summary,
                             "\(entry.date): last week's numbers must not read as \"This week\"")
            }
        }
    }

    /// A snapshot from the previous build carries no weekStart: the tally has
    /// no week to belong to, so it is shown nowhere rather than guessed.
    func testTallyWithoutWeekStartIsShownNowhere() {
        let (snapshot, today) = fixture()
        let legacy = WidgetSnapshot(days: snapshot.days, totalLevel: snapshot.totalLevel,
                                    week: snapshot.week, weekStart: nil,
                                    planSessionNumber: snapshot.planSessionNumber,
                                    planMinutes: snapshot.planMinutes, plan: snapshot.plan)
        for entry in TodayProvider().entries(from: legacy, today: today) {
            XCTAssertNil(entry.summary)
        }
    }

    func testNoSnapshotMeansNoEntries() {
        XCTAssertTrue(TodayProvider().entries(from: nil).isEmpty)
    }

    // MARK: - The views' words

    private func entry(_ status: WidgetSnapshot.Day.Status?,
                       nextLabel: String? = nil,
                       planSession: Int? = nil,
                       planMinutes: Int? = nil,
                       plan: [WidgetSnapshot.PlanRow] = []) -> TodayEntry {
        TodayEntry(date: date(2), status: status, sessionNumber: nil, week: [],
                   totalLevel: nil, summary: nil, nextLabel: nextLabel,
                   planSessionNumber: planSession, planMinutes: planMinutes, plan: plan)
    }

    func testRestDayWordsUseTheEntrysOwnLabel() {
        let view = TodayStatusView(entry: entry(.rest, nextLabel: "tomorrow",
                                                planSession: 12))
        XCTAssertEqual(view.headline, Text("Rest day"))
        XCTAssertEqual(view.subline, Text("Next workout \("tomorrow")"))
        XCTAssertEqual(view.nextPlanText, Text("Next: Workout \(12) · \("tomorrow")"))
    }

    func testWorkoutDayWordsCarryThePlanNotALabel() {
        let rows = [WidgetSnapshot.PlanRow(name: "Push-up", detail: "3×12")]
        let view = TodayStatusView(entry: entry(.workout, nextLabel: nil,
                                                planSession: 12, planMinutes: 34,
                                                plan: rows))
        XCTAssertEqual(view.subline, Text("≈ \(34) min · \(1) exercises"))
        XCTAssertNil(view.nextPlanText, "a planned day IS the workout — no next label")
    }

    func testDoneAndEmptyWords() {
        XCTAssertEqual(TodayStatusView(entry: entry(.done, nextLabel: "tomorrow")).headline,
                       Text("Done ✓"))
        XCTAssertEqual(TodayStatusView(entry: entry(.done, nextLabel: "tomorrow")).subline,
                       Text("Next workout \("tomorrow")"))
        XCTAssertEqual(TodayStatusView(entry: .empty).subline, Text("Dredfit"),
                       "no snapshot yet — the widget signs itself, it does not guess")
    }
}
