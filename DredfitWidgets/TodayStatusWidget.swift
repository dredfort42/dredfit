//
//  The app writes a two-week snapshot into the App Group; the widget only
//  reads it, one timeline entry per day. The timeline itself lives in
//  TodayProvider.swift, where the unit tests can reach it.
//

import WidgetKit
import SwiftUI

// MARK: - View

/// Explicit @MainActor, like TodayProvider: the unit tests compile this file
/// without the widget target's default MainActor isolation.
@MainActor
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
        .containerBackground(Theme.bg, for: .widget)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                kicker
                Spacer(minLength: 0)
                totalStepsLine
            }
            Spacer(minLength: 8)
            statusBlock(size: 22)
            Spacer(minLength: 8)
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
                .padding(.bottom, 10)
            weekStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(Theme.bg, for: .widget)
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
        .containerBackground(Theme.bg, for: .widget)
    }

    // MARK: Lock screen

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
            Text(headline)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subline)
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
                    Text(headline)
                }
            default:
                Text(headline)
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
            .foregroundStyle(Theme.ink2)
    }

    private func statusBlock(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.status == .workout {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
            }
            Text(headline)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(entry.status == .rest ? Theme.ink2 : Theme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var totalStepsLine: some View {
        if let steps = entry.totalSteps {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(steps)")
                    .font(.system(size: 22, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("steps")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.ink2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(entry.week, id: \.date) { day in
                VStack(spacing: 5) {
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10, weight: .semibold))
                        // A missed day carries no mark, so without dimming its
                        // letter the column reads as a failed render.
                        .foregroundStyle(day.status == .unmarked
                                         ? Theme.ink3 : Theme.ink2)
                    mark(for: day)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func mark(for day: WidgetSnapshot.Day) -> some View {
        let isToday = Calendar.current.isDate(day.date, inSameDayAs: entry.date)
        ZStack {
            switch day.status {
            case .done:
                Circle().fill(Theme.accent)
            case .rest:
                Circle().fill(Theme.restFill)
            case .workout:
                Circle().strokeBorder(Theme.planned, lineWidth: 1.5)
            case .unmarked:
                Color.clear
            }
            if isToday && day.status != .done {
                Circle().strokeBorder(Theme.accent, lineWidth: 2)
            }
        }
        .frame(width: 14, height: 14)
    }

    @ViewBuilder
    private var nextPlanLabel: some View {
        if let text = nextPlanText {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
        }
    }

    var nextPlanText: String? {
        guard entry.status != .workout, let n = entry.planSessionNumber,
              let when = entry.nextLabel else { return nil }
        return String(localized: "Next: Workout \(n) · \(when)")
    }

    private var planList: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.plan.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 0.5)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        // Shrink rather than truncate (I-12): sibling
                        // variations differ at the END of the name, which is
                        // exactly what an ellipsis would hide.
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(row.detail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink2)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var weekSummaryLine: some View {
        if let week = entry.summary {
            weekSummaryText(week)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// A snapshot written before the scale changed carries no `stepsDelta`,
    /// so the line drops that segment instead of reading a level count as
    /// steps. One `Text` chain, built once: the modifiers above have to land
    /// on the whole line either way.
    private func weekSummaryText(_ week: WidgetSnapshot.Week) -> Text {
        let head = Text("This week")
            + Text(verbatim: " · ")
            + Text("\(week.workouts) workouts")
        guard let delta = week.stepsDelta else { return head }
        let sign = delta >= 0 ? "+" : ""
        return head
            + Text(" · \(sign)", comment: "A separator dot followed by the sign of the weekly change.")
            + Text("\(delta) steps")
    }

    // MARK: Words and glyphs
    //
    // headline and subline are internal rather than private: the unit tests
    // pin these per status. glyph has no such reader and stays private.
    // Resolved Strings rather than Text — two Texts with identical words do
    // not reliably compare equal (I-8).

    var headline: String {
        switch entry.status {
        case .workout:
            if let n = entry.sessionNumber { return String(localized: "Workout \(n)") }
            return String(localized: "Workout day")
        case .done:
            return String(localized: "Done ✓")
        case .rest:
            return String(localized: "Rest day")
        case .unmarked, nil:
            return String(localized: "Dredfit")
        }
    }

    var subline: String {
        switch entry.status {
        case .workout:
            if let min = entry.planMinutes, !entry.plan.isEmpty {
                return String(localized: "≈ \(min) min · \(entry.plan.count) exercises")
            }
            return String(localized: "Dredfit")
        default:
            if let when = entry.nextLabel { return String(localized: "Next workout \(when)") }
            return String(localized: "Dredfit")
        }
    }

    private var glyph: String {
        switch entry.status {
        case .done: return "checkmark"
        case .rest: return "moon.fill"
        default: return "figure.strengthtraining.functional"
        }
    }
}

@MainActor
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
