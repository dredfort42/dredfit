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

    private func day(_ offset: Int, _ status: WidgetSnapshot.DayStatus,
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
            totalSteps: 27,
            week: .init(workouts: 3, stepsDelta: 6),
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

    func testTallyWithoutWeekStartIsShownNowhere() {
        let (snapshot, today) = fixture()
        let legacy = WidgetSnapshot(days: snapshot.days, totalSteps: snapshot.totalSteps,
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

    // MARK: - When to come back for the next timeline

    func testAnExpiredTimelineIsNotAskedForAgainImmediately() {
        let provider = TodayProvider()
        let (snapshot, today) = fixture()
        let now = today.addingTimeInterval(11 * 60 * 60)   // 11:00 on the fixture's today
        let entries = provider.entries(from: snapshot, today: today)

        // Healthy: the last entry is eleven days out, so .atEnd is right.
        XCTAssertNil(provider.nextReload(after: entries, now: now))

        // Spent: today's entry is the last one, stamped at this morning's
        // midnight. Come back after midnight, not inside this same second.
        let spent = entries.filter { $0.date <= today }
        XCTAssertEqual(spent.count, 1, "the fixture's today must be the only one left")
        XCTAssertEqual(provider.nextReload(after: spent, now: now), date(3))

        // Run out entirely: nothing to end on at all.
        XCTAssertEqual(provider.nextReload(after: [], now: now), date(3))

        // ...and the fallback entry the provider substitutes is dated at
        // render time, which is not a future either. Built before the clock
        // is read, and read against the real one: `.empty` stamps itself with
        // `.now`, so the fixture's Wednesday says nothing about it.
        let fallback = TodayEntry.empty
        let realNow = Date.now
        XCTAssertEqual(provider.nextReload(after: [fallback], now: realNow),
                       Calendar.current.startOfDay(
                           for: Calendar.current.date(byAdding: .day, value: 1, to: realNow)!),
                       "the substituted entry has already expired when it is handed over")
    }

    // MARK: - The views' words

    private func entry(_ status: WidgetSnapshot.DayStatus?,
                       sessionNumber: Int? = nil,
                       nextLabel: String? = nil,
                       planSession: Int? = nil,
                       planMinutes: Int? = nil,
                       plan: [WidgetSnapshot.PlanRow] = []) -> TodayEntry {
        TodayEntry(date: date(2), status: status, sessionNumber: sessionNumber, week: [],
                   totalSteps: nil, summary: nil, nextLabel: nextLabel,
                   planSessionNumber: planSession, planMinutes: planMinutes, plan: plan)
    }

    func testRestDayWordsUseTheEntrysOwnLabel() {
        let view = TodayStatusView(entry: entry(.rest, nextLabel: "tomorrow",
                                                planSession: 12))
        XCTAssertEqual(view.headline, String(localized: "Rest day"))
        XCTAssertEqual(view.subline, String(localized: "Next workout \("tomorrow")"))
        XCTAssertEqual(view.nextPlanText, String(localized: "Next: Workout \(12) · \("tomorrow")"))
    }

    func testWorkoutDayWordsCarryThePlanNotALabel() {
        let rows = [WidgetSnapshot.PlanRow(name: "Push-up", detail: "3×12")]
        let view = TodayStatusView(entry: entry(.workout, nextLabel: nil,
                                                planSession: 12, planMinutes: 34,
                                                plan: rows))
        XCTAssertEqual(view.subline, String(localized: "≈ \(34) min · \(1) exercises"))
        XCTAssertNil(view.nextPlanText, "a planned day IS the workout — no next label")
    }

    func testDoneAndEmptyWords() {
        XCTAssertEqual(TodayStatusView(entry: entry(.done, nextLabel: "tomorrow")).headline,
                       String(localized: "Done ✓"))
        XCTAssertEqual(TodayStatusView(entry: entry(.done, nextLabel: "tomorrow")).subline,
                       String(localized: "Next workout \("tomorrow")"))
        XCTAssertEqual(TodayStatusView(entry: .empty).subline, String(localized: "Dredfit"),
                       "no snapshot yet — the widget signs itself, it does not guess")
    }

    /// The number comes from the snapshot's day, never from the view: a
    /// snapshot written before the app knew the session number carries none,
    /// and the widget then has a workout day with no name for it.
    func test_headline_onAWorkoutDay_namesTheSessionOnlyWhenTheSnapshotCarriedItsNumber() {
        XCTAssertEqual(TodayStatusView(entry: entry(.workout, sessionNumber: 12)).headline,
                       String(localized: "Workout \(12)"),
                       "the day's own number is what the home screen shows")
        XCTAssertEqual(TodayStatusView(entry: entry(.workout)).headline,
                       String(localized: "Workout day"),
                       "and with no number the day is still a workout day, not a blank")
    }

    /// A snapshot from an older build carries no plan rows. The minutes may
    /// still be there, and "≈ 34 min · 0 exercises" is the sentence that would
    /// then be printed — a promise about a workout the widget cannot describe.
    func test_subline_onAWorkoutDayWhosePlanIsMissing_signsItselfRatherThanCountingZeroExercises() {
        let view = TodayStatusView(entry: entry(.workout, planMinutes: 34, plan: []))

        XCTAssertEqual(view.subline, String(localized: "Dredfit"),
                       "with no rows there is nothing to count, and a count of zero is worse than silence")
    }

    /// Both halves of "Next: Workout 12 · tomorrow" come out of the snapshot,
    /// and the line exists only when both arrived.
    func test_nextPlanText_whenEitherHalfOfTheLineIsMissing_isNotShownAtAll() {
        XCTAssertNotNil(TodayStatusView(entry: entry(.rest, nextLabel: "tomorrow", planSession: 12))
            .nextPlanText, "the fixture must produce the line when both halves are there")
        XCTAssertNil(TodayStatusView(entry: entry(.rest, nextLabel: "tomorrow")).nextPlanText,
                     "without a session number there is no workout to point at")
        XCTAssertNil(TodayStatusView(entry: entry(.rest, planSession: 12)).nextPlanText,
                     "and without a day there is no when — a half-line reads as a promise for today")
    }

    /// The plan rows arrived with v3. A snapshot still on disk from the build
    /// before it must render as a plain workout day, not blank the widget.
    func test_entries_fromASnapshotWrittenBeforeThePlanExisted_carryAnEmptyPlan() {
        let (whole, today) = fixture()
        let legacy = WidgetSnapshot(days: whole.days, totalSteps: whole.totalSteps,
                                    week: whole.week, weekStart: whole.weekStart,
                                    planSessionNumber: whole.planSessionNumber,
                                    planMinutes: whole.planMinutes, plan: nil)
        let entries = TodayProvider().entries(from: legacy, today: today)

        XCTAssertFalse(entries.isEmpty, "a snapshot without rows is still a snapshot")
        XCTAssertTrue(entries.allSatisfy { $0.plan.isEmpty },
                      "the absent rows read as none rather than reaching the views as an optional "
                      + "they would each have to unwrap")
    }
}

// NOT COVERED HERE, and not coverable as the code stands:
//
//  * `TodayStatusView.weekSummaryText(_:)` — "A snapshot written before the
//    scale changed carries no `stepsDelta`, so the line drops that segment
//    instead of reading a level count as steps."
//
// The DECODE half of that contract is guarded (AppStoreTests+WidgetSnapshot:
// `testWidgetSnapshotWeekFromBeforeTheScaleChangeStillDecodes`); the RENDER
// half is not, and cannot be: the function returns a `Text` chain, and two
// Texts with identical words do not reliably compare equal (I-8) — which is
// why every other word-builder in that file was turned into a resolved
// `String` and this one was left behind.
//
// The minimal change that would make it testable: finish I-8 here too —
// `func weekSummaryString(_ week: WidgetSnapshot.Week) -> String` built from
// `String(localized:)`, with `weekSummaryLine` wrapping it in a single
// `Text(verbatim:)`. Two assertions then cover the rule: a week WITH a delta
// prints it with its sign (TESTPLAN §12.12 wants a negative one shown, not
// hidden), and a week without one prints the two leading segments and stops.
