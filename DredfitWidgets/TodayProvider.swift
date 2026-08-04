//
//  TodayProvider.swift
//  DredfitWidgets
//
//  Split out of TodayStatusWidget.swift so the unit tests can compile the
//  mapping without the views' palette.
//

import WidgetKit
import Foundation

// @MainActor is spelled out on the types below (and in the view files)
// rather than inherited: the widget target compiles with default MainActor
// isolation, the test target does not.

@MainActor
struct TodayEntry: TimelineEntry {
    let date: Date
    let status: WidgetSnapshot.Day.Status?
    let sessionNumber: Int?
    let week: [WidgetSnapshot.Day]
    let totalLevel: Int?
    let summary: WidgetSnapshot.Week?
    let nextLabel: String?
    let planSessionNumber: Int?
    let planMinutes: Int?
    let plan: [WidgetSnapshot.PlanRow]

    /// Computed, not a `static let`: a stored static would freeze `.now` at
    /// its first access and hand every later timeline request in the same
    /// extension process an entry already dated in the past (I-9).
    static var empty: TodayEntry {
        TodayEntry(date: .now, status: nil, sessionNumber: nil, week: [],
                   totalLevel: nil, summary: nil, nextLabel: nil,
                   planSessionNumber: nil, planMinutes: nil, plan: [])
    }
}

@MainActor
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, status: .workout, sessionNumber: 1, week: [],
                   totalLevel: nil, summary: nil, nextLabel: nil,
                   planSessionNumber: nil, planMinutes: nil, plan: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entries(from: loadSnapshot()).first ?? .empty)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        var list = entries(from: loadSnapshot())
        if list.isEmpty { list = [.empty] }
        if let next = nextReload(after: list) {
            completion(Timeline(entries: list, policy: .after(next)))
        } else {
            completion(Timeline(entries: list, policy: .atEnd))
        }
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let url = SharedStorage.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// One entry per snapshot day, starting today; past days are dropped from
    /// the timeline but stay in each entry's week strip. `today` is a
    /// parameter only so tests can pin the clock.
    func entries(from snapshot: WidgetSnapshot?,
                 today: Date = Calendar.current.startOfDay(for: .now)) -> [TodayEntry] {
        guard let snapshot else { return [] }
        var iso = Calendar(identifier: .iso8601)   // Monday-first, as the app writes it
        iso.timeZone = Calendar.current.timeZone
        return snapshot.days
            .filter { $0.date >= today }
            .map { day in
                let week = iso.dateInterval(of: .weekOfYear, for: day.date)
                // The tally travels only with the week it was written in:
                // last week's numbers must not read as "This week".
                let sameWeek = snapshot.weekStart.map { week?.contains($0) ?? false } ?? false
                return TodayEntry(
                    date: day.date,
                    status: day.status,
                    sessionNumber: day.sessionNumber,
                    week: snapshot.days.filter { d in
                        guard let week else { return false }
                        return d.date >= week.start && d.date < week.end
                    },
                    totalLevel: snapshot.totalLevel,
                    summary: sameWeek ? snapshot.week : nil,
                    nextLabel: day.nextLabel,
                    planSessionNumber: snapshot.planSessionNumber,
                    planMinutes: snapshot.planMinutes,
                    plan: snapshot.plan ?? []
                )
            }
    }

    /// nil means `.atEnd`. Entries are stamped at the start of their day, so
    /// once today's is the last one the timeline has already expired: `.atEnd`
    /// would be re-requested immediately, answered with the same expired
    /// timeline, and spend the day's whole reload budget. `now` is a
    /// parameter only so tests can pin the clock.
    func nextReload(after entries: [TodayEntry], now: Date = .now) -> Date? {
        if let last = entries.last, last.date > now { return nil }
        let cal = Calendar.current
        // The fallback must stay strictly ahead of `now` — a date in the past
        // here reinstates the loop above.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(24 * 60 * 60)
        return cal.startOfDay(for: tomorrow)
    }
}
