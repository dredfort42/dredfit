//
//  TodayStatusWidget.swift
//  DredfitWidgets
//
//  Today's status — a planned workout, "done", or a rest day — on the home
//  screen and on the lock screen. The app writes a two-week snapshot into the
//  App Group; the widget only reads it, one timeline entry per day, so the
//  status flips at midnight without the app's help.
//
//  What each family answers is deliberately different, so two accessories on
//  the same lock screen never say the same thing twice:
//    · circular      — is there a workout today? one glyph, no reading
//    · inline / rect — which workout, and how much of it
//    · small         — the same question the widget has always answered
//    · medium        — plus the week and the total level
//    · large         — plus the plan itself
//

import WidgetKit
import SwiftUI

struct TodayEntry: TimelineEntry {
    let date: Date
    let status: WidgetSnapshot.Day.Status?
    let sessionNumber: Int?
    /// The Monday–Sunday week containing `date`, for the strip.
    let week: [WidgetSnapshot.Day]
    let totalLevel: Int?
    let summary: WidgetSnapshot.Week?
    let nextDateLabel: String?
    let planSessionNumber: Int?
    let planMinutes: Int?
    let plan: [WidgetSnapshot.PlanRow]

    static let empty = TodayEntry(date: .now, status: nil, sessionNumber: nil, week: [],
                                  totalLevel: nil, summary: nil, nextDateLabel: nil,
                                  planSessionNumber: nil, planMinutes: nil, plan: [])
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, status: .workout, sessionNumber: 1, week: [],
                   totalLevel: nil, summary: nil, nextDateLabel: nil,
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
    /// the timeline but stay in each entry's week strip.
    private func entries(from snapshot: WidgetSnapshot?) -> [TodayEntry] {
        guard let snapshot else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
        var iso = Calendar(identifier: .iso8601)   // Monday-first, as the app writes it
        iso.timeZone = Calendar.current.timeZone
        return snapshot.days
            .filter { $0.date >= today }
            .map { day in
                let week = iso.dateInterval(of: .weekOfYear, for: day.date)
                return TodayEntry(
                    date: day.date,
                    status: day.status,
                    sessionNumber: day.sessionNumber,
                    week: snapshot.days.filter { d in
                        guard let week else { return false }
                        return d.date >= week.start && d.date < week.end
                    },
                    totalLevel: snapshot.totalLevel,
                    summary: snapshot.week,
                    nextDateLabel: snapshot.nextDateLabel,
                    planSessionNumber: snapshot.planSessionNumber,
                    planMinutes: snapshot.planMinutes,
                    plan: snapshot.plan ?? []
                )
            }
    }
}

// MARK: - View

struct TodayStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge: large
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            kicker
            Spacer(minLength: 0)
            statusBlock(size: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WidgetTheme.background, for: .widget)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                kicker
                Spacer(minLength: 0)
                statusBlock(size: 20)
            }
            VStack(alignment: .trailing, spacing: 0) {
                totalLevelLine
                Spacer(minLength: 8)
                weekStrip
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WidgetTheme.background, for: .widget)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker
                .padding(.bottom, 10)
            statusBlock(size: 22)
            nextPlanLabel
                .padding(.top, 12)
            planList
                .padding(.top, 10)
            Spacer(minLength: 10)
            weekSummaryLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WidgetTheme.background, for: .widget)
    }

    // MARK: Lock screen

    /// One glyph, no reading: the only question worth answering at a glance.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: glyph)
                .font(.system(size: 24, weight: .medium))
        }
        .accessibilityLabel(headline)
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Today")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .widgetAccentable()
            headline
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            subline
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        Label {
            switch entry.status {
            case .workout:
                if let n = entry.sessionNumber, let min = entry.planMinutes {
                    Text("Workout \(n)") + Text(verbatim: " · ") + Text("≈ \(min) min")
                } else {
                    headline
                }
            default:
                headline
            }
        } icon: {
            Image(systemName: glyph)
        }
        .containerBackground(.clear, for: .widget)
    }

    // MARK: Pieces

    private var kicker: some View {
        Text("Today")
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.2)
            .textCase(.uppercase)
            .foregroundStyle(WidgetTheme.ink2)
    }

    /// The accent dot plus the headline — the shape the small family has
    /// always had, reused so every size reads as one family.
    @ViewBuilder
    private func statusBlock(size: CGFloat) -> some View {
        if entry.status == .workout {
            Circle()
                .fill(WidgetTheme.accent)
                .frame(width: 10, height: 10)
        }
        headline
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(entry.status == .rest ? WidgetTheme.ink2 : WidgetTheme.ink)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }

    @ViewBuilder
    private var totalLevelLine: some View {
        if let level = entry.totalLevel {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(level)")
                    .font(.system(size: 22, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.ink)
                Text("level")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WidgetTheme.ink2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    /// The same marks the Calendar tab uses, so a filled dot cannot come to
    /// mean one thing on the home screen and another inside the app.
    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(entry.week, id: \.date) { day in
                VStack(spacing: 5) {
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(WidgetTheme.ink2)
                    mark(for: day)
                }
            }
        }
    }

    @ViewBuilder
    private func mark(for day: WidgetSnapshot.Day) -> some View {
        let isToday = Calendar.current.isDate(day.date, inSameDayAs: entry.date)
        ZStack {
            switch day.status {
            case .done:
                Circle().fill(WidgetTheme.accent)
            case .rest:
                Circle().fill(WidgetTheme.restFill)
            case .workout:
                Circle().strokeBorder(WidgetTheme.planned, lineWidth: 1.5)
            case .unmarked:
                // A missed training day. Left blank on purpose.
                Color.clear
            }
            // "Done" is already the loudest mark on the strip; ringing it too
            // would only blur which day is today.
            if isToday && day.status != .done {
                Circle().strokeBorder(WidgetTheme.accent, lineWidth: 2)
            }
        }
        .frame(width: 14, height: 14)
    }

    /// On a rest day or once today is done, the plan below is the *next*
    /// session — say so, rather than letting it read as today's.
    @ViewBuilder
    private var nextPlanLabel: some View {
        if entry.status != .workout, let n = entry.planSessionNumber, let when = entry.nextDateLabel {
            Text("Next: Workout \(n) · \(when)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetTheme.ink2)
                .lineLimit(1)
        }
    }

    private var planList: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.plan.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(WidgetTheme.hairline)
                        .frame(height: 0.5)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13.5))
                        .foregroundStyle(WidgetTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(row.detail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetTheme.ink2)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
            }
        }
    }

    /// Worded exactly as the Progress screen words it, deload weeks and all.
    @ViewBuilder
    private var weekSummaryLine: some View {
        if let week = entry.summary {
            let sign = week.levelsDelta >= 0 ? "+" : ""
            (Text("This week")
                + Text(verbatim: " · ")
                + Text("\(week.workouts) workouts")
                + Text(" · \(sign)", comment: "A separator dot followed by the sign of the level change.")
                + Text("\(week.levelsDelta) levels"))
                .font(.system(size: 11.5))
                .foregroundStyle(WidgetTheme.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: Words and glyphs

    private var headline: Text {
        switch entry.status {
        case .workout:
            if let n = entry.sessionNumber { return Text("Workout \(n)") }
            return Text("Workout day")
        case .done:
            return Text("Done ✓")
        case .rest:
            return Text("Rest day")
        case .unmarked, nil:
            return Text("Dredfit")
        }
    }

    private var subline: Text {
        switch entry.status {
        case .workout:
            if let min = entry.planMinutes, !entry.plan.isEmpty {
                return Text("≈ \(min) min · \(entry.plan.count) exercises")
            }
            return Text("Dredfit")
        default:
            if let when = entry.nextDateLabel { return Text("Next workout \(when)") }
            return Text("Dredfit")
        }
    }

    /// Two of the three already exist in the app's tiny symbol vocabulary:
    /// `checkmark` is the done state on Today, `figure.strengthtraining
    /// .functional` is how the Live Activity signs itself in the Dynamic
    /// Island. A rest day never had a glyph — `moon.fill` is the one silhouette
    /// that cannot be confused with the figure at accessory size.
    private var glyph: String {
        switch entry.status {
        case .done: return "checkmark"
        case .rest: return "moon.fill"
        default: return "figure.strengthtraining.functional"
        }
    }
}

struct TodayStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DredfitToday", provider: TodayProvider()) { entry in
            TodayStatusView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Today's status"))
        .description(String(localized: "Workout, done or a rest day at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
