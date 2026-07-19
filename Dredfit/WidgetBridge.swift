//
//  WidgetBridge.swift
//  Dredfit
//
//  v1.3: the app side of the widget contract. After every persisted
//  change the app rewrites a 7-day status snapshot in the App Group and
//  pokes WidgetKit; the widget itself never computes rest days. Without
//  the entitlement (or in unit tests) everything degrades silently.
//

import Foundation
import WidgetKit
import DredfitCore

extension AppStore {

    func refreshWidgetSnapshot(now: Date = .now) {
        // v1.6: the URL is injected (App Group by default) so unit tests can
        // point it at a temp directory and actually exercise the mirroring.
        guard let url = widgetSnapshotURL else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let days: [WidgetSnapshot.Day] = (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            if isDone(on: day) {
                return .init(date: day, status: .done, sessionNumber: nil)
            }
            if isRestDay(day) {
                return .init(date: day, status: .rest, sessionNumber: nil)
            }
            return .init(date: day, status: .workout,
                         sessionNumber: offset == 0 ? nextSession.sessionNumber : nil)
        }
        if let data = try? JSONEncoder().encode(WidgetSnapshot(days: days)) {
            try? data.write(to: url, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
