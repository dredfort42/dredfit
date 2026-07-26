//
//  WidgetBridge.swift
//  Dredfit
//
//  The app side of the widget contract. After every persisted change the
//  app rewrites a two-week status snapshot in the App Group and pokes
//  WidgetKit; the widget itself never computes rest days. Without the
//  entitlement (or in unit tests) everything degrades silently.
//

import Foundation
import WidgetKit
import DredfitCore

extension AppStore {

    func refreshWidgetSnapshot(now: Date = .now) {
        // A launch that could not read the journal knows nothing about the
        // user: publishing that emptiness would put "nothing done" on the
        // home screen for a week over a history that is perfectly fine.
        guard !journalFrozen else { return }
        // The URL is injected (App Group by default) so unit tests can
        // point it at a temp directory and actually exercise the mirroring.
        guard let url = widgetSnapshotURL else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        // Monday-first, like the Calendar tab and the weekly summary. Starting
        // on Monday rather than today is what lets a timeline entry days ahead
        // still draw its own full week.
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = cal.timeZone
        guard let thisWeek = iso.dateInterval(of: .weekOfYear, for: today) else { return }

        // A pure function of state, and not a cheap one — resolve it once
        // rather than per day.
        let next = nextSession
        let days: [WidgetSnapshot.Day] = (0..<14).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: thisWeek.start) else {
                return nil
            }
            let status = widgetStatus(of: day, today: today)
            let isToday = cal.isDate(day, inSameDayAs: today)
            return .init(date: day, status: status,
                         sessionNumber: isToday && status == .workout ? next.sessionNumber : nil)
        }

        let summary = weekSummary(for: today)
        let snapshot = WidgetSnapshot(
            days: days,
            totalLevel: totalLevel,
            week: .init(workouts: summary.workouts, levelsDelta: summary.levelsDelta),
            nextDateLabel: nextTrainingDateLabel,
            planSessionNumber: next.sessionNumber,
            planMinutes: Int(next.estimatedTotalMin.rounded()),
            plan: next.exercises.map { .init(name: $0.name, detail: $0.display) }
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// A day's status for the strip. Past days are read from the journal —
    /// `isDone(on:)` only ever knows about the latest record — and a past
    /// training day that was not done stays *unmarked*: the Calendar leaves
    /// missed days unshamed, and the widget is not the place to start.
    private func widgetStatus(of day: Date, today: Date) -> WidgetSnapshot.Day.Status {
        if record(on: day) != nil { return .done }
        if isRestDay(day) { return .rest }
        return day < today ? .unmarked : .workout
    }
}
