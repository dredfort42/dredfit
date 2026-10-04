//
//  After every persisted change the app rewrites the two-week snapshot and
//  pokes WidgetKit; the widget never computes rest days itself. Without the
//  entitlement everything degrades silently. Unit tests run hosted in the
//  app, and on a signed local run the default URL is the real App Group, so
//  a test store passes `widgetSnapshotURL: nil` or a temp URL.
//

import Foundation
import WidgetKit
import DredfitCore

extension AppStore {

    func refreshWidgetSnapshot(now: Date = .now) {
        // A frozen launch knows nothing about the user: publishing that
        // emptiness would put "nothing done" over a perfectly fine history.
        guard !journalFrozen else { return }
        // Injected so unit tests can point it at a temp directory.
        guard let url = widgetSnapshotURL else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        // Monday-first, like the Calendar tab: starting on Monday rather than
        // today is what lets a timeline entry days ahead draw its own week.
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = cal.timeZone
        guard let thisWeek = iso.dateInterval(of: .weekOfYear, for: today) else { return }

        // Not cheap — resolve once rather than per day.
        let next = nextSession
        let days: [WidgetSnapshot.Day] = (0..<14).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: thisWeek.start) else {
                return nil
            }
            let status = widgetStatus(of: day, today: today)
            let isToday = cal.isDate(day, inSameDayAs: today)
            return .init(date: day, status: status,
                         sessionNumber: isToday && status == .workout ? next.sessionNumber : nil,
                         // Relative to the day the entry renders on, not to
                         // this write: a rest-day entry shown days from now
                         // must not say a stale "today".
                         nextLabel: day >= today && status != .workout
                             ? nextTrainingDateLabel(from: day) : nil)
        }

        let summary = weekSummary(for: today)
        // Both ends out of one call: the widget prints the same length range
        // as Today does (PlanLength), and two numbers resolved at different
        // moments could disagree about which end is which. `full` is
        // `nextSession.estimatedTotalMin`.
        let length = sessionLengthRange()
        let snapshot = WidgetSnapshot(
            days: days,
            totalSteps: totalProgress,
            week: .init(workouts: summary.workouts, stepsDelta: summary.stepsDelta),
            weekStart: thisWeek.start,
            planSessionNumber: next.sessionNumber,
            planMinutes: length.full,
            planMinutesFloor: length.floor,
            plan: next.exercises.map { .init(name: $0.name, detail: $0.display) }
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Past days come from the journal, not `isDone(on:)`, which only ever
    /// knows about the latest record. A missed training day stays *unmarked*
    /// — the Calendar leaves those unshamed and the widget follows.
    private func widgetStatus(of day: Date, today: Date) -> WidgetSnapshot.DayStatus {
        if record(on: day) != nil { return .done }
        // TODAY follows `restApplies`, the rest of the grid `isRestDay`
        // (`planRests`). Rest is rest FROM something: a fresh install whose
        // onboarding ended on a marked weekday sees the plan on Today, and the
        // widget must not tell that person "Rest day — next workout tomorrow".
        // Only today, though: the marked weekdays still describe the days
        // ahead, and a blanket swap would paint the whole fortnight as
        // workouts.
        if planRests(on: day, today: today) { return .rest }
        return day < today ? .unmarked : .workout
    }
}
