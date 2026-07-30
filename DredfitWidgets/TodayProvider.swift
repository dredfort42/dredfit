//
//  TodayProvider.swift
//  DredfitWidgets
//
//  The timeline: one entry per snapshot day, mapped straight from what the
//  app wrote. Split out of TodayStatusWidget.swift so the unit tests can
//  compile the mapping without dragging the views' palette along — the
//  per-day labels and the week-tally gating are exactly the logic a stale
//  snapshot once got wrong.
//

import WidgetKit
import Foundation

// @MainActor is spelled out on the types below (and in the view files)
// rather than inherited: the widget target compiles with default MainActor
// isolation, the test target does not — explicit isolation is what keeps
// the tested build semantically identical to the shipped one.

@MainActor
struct TodayEntry: TimelineEntry {
    let date: Date
    let status: WidgetSnapshot.Day.Status?
    let sessionNumber: Int?
    /// The Monday–Sunday week containing `date`, for the strip.
    let week: [WidgetSnapshot.Day]
    let totalLevel: Int?
    let summary: WidgetSnapshot.Week?
    /// This day's own "next workout" label — see WidgetSnapshot.Day.nextLabel.
    let nextLabel: String?
    let planSessionNumber: Int?
    let planMinutes: Int?
    let plan: [WidgetSnapshot.PlanRow]

    static let empty = TodayEntry(date: .now, status: nil, sessionNumber: nil, week: [],
                                  totalLevel: nil, summary: nil, nextLabel: nil,
                                  planSessionNumber: nil, planMinutes: nil, plan: [])
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
        completion(Timeline(entries: list, policy: .atEnd))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let url = SharedStorage.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// One entry per snapshot day, starting today; past days are dropped from
    /// the timeline but stay in each entry's week strip. `today` is a
    /// parameter only so tests can pin the clock; the widget always passes
    /// the real day.
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
                // last week's numbers must not read as "This week" on a
                // next-week entry.
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
}
