//
//  TodayStatusWidget.swift
//  DredfitWidgets
//
//  A small home-screen widget: today's status — a planned workout,
//  "done", or a rest day. The app writes a 7-day snapshot into the
//  App Group; the widget only reads it, one timeline entry per day,
//  so the status flips at midnight without the app's help.
//

import WidgetKit
import SwiftUI

struct TodayEntry: TimelineEntry {
    let date: Date
    let status: WidgetSnapshot.Day.Status?
    let sessionNumber: Int?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, status: .workout, sessionNumber: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entries(from: loadSnapshot()).first
            ?? TodayEntry(date: .now, status: nil, sessionNumber: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        var list = entries(from: loadSnapshot())
        if list.isEmpty { list = [TodayEntry(date: .now, status: nil, sessionNumber: nil)] }
        completion(Timeline(entries: list, policy: .atEnd))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let url = SharedStorage.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// One entry per snapshot day, starting today; past days are dropped.
    private func entries(from snapshot: WidgetSnapshot?) -> [TodayEntry] {
        guard let snapshot else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
        return snapshot.days
            .filter { $0.date >= today }
            .map { TodayEntry(date: $0.date, status: $0.status, sessionNumber: $0.sessionNumber) }
    }
}

struct TodayStatusView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(WidgetTheme.ink2)

            Spacer(minLength: 0)

            switch entry.status {
            case .workout:
                Circle()
                    .fill(WidgetTheme.accent)
                    .frame(width: 10, height: 10)
                if let n = entry.sessionNumber {
                    Text("Workout \(n)")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(WidgetTheme.ink)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Workout day")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(WidgetTheme.ink)
                        .minimumScaleFactor(0.7)
                }
            case .done:
                Text("Done ✓")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(WidgetTheme.ink)
            case .rest:
                Text("Rest day")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(WidgetTheme.ink2)
            case nil:
                Text("Dredfit")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(WidgetTheme.ink2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.white, for: .widget)
    }
}

struct TodayStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DredfitToday", provider: TodayProvider()) { entry in
            TodayStatusView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Today's status"))
        .description(String(localized: "Workout, done or a rest day at a glance."))
        .supportedFamilies([.systemSmall])
    }
}
