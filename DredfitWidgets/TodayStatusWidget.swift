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
            // Dynamic Type, not three frozen sizes: `.system(size:)` ignores
            // the reader's setting outright, and the lock screen is the one
            // surface read without picking the phone up — or the glasses
            // (finding 60, UX review 05.09.2026). The sibling lock-screen file
            // settled the same question the same way: `RestLiveActivity` caps
            // only its display NUMBER and lets every word scale, so no `cap:`
            // here. What one line can take is bounded by the two rules already
            // on it — one line, and shrink before truncating.
            Text("Today")
                .dredfitFont(11, weight: .semibold)
                .kerning(0.6)
                .textCase(.uppercase)
                .widgetAccentable()
            Text(headline)
                .dredfitFont(15, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subline)
                .dredfitFont(12)
                .lineLimit(1)
                // The only line here that carries a fact, and the one that
                // was losing the day it names to an ellipsis in the longer
                // languages. Same factor as the headline two lines up: one
                // rule inside one view (UX review 05.09.2026).
                .minimumScaleFactor(0.8)
                .accessibilityLabel(sublineSpoken)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        Label {
            switch entry.status {
            case .workout:
                if let n = entry.sessionNumber, let min = entry.planMinutes {
                    // Both ends here too — inline and rectangular sit on the
                    // same lock screen, and one of them saying "32 min" while
                    // the other says "24–32 min" reads as two plans
                    // (UX review 05.09.2026).
                    Text("Workout \(n)") + Text(verbatim: " · ") + minutesText(full: min)
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

    /// Inline composes its line out of `Text` fragments, so the length clause
    /// is a Text here rather than the resolved String the other surfaces
    /// compare in tests (I-8). Same two ends as `subline`.
    private func minutesText(full: Int) -> Text {
        if let floor = entry.planMinutesFloor, floor < full {
            return Text("≈ \(floor)–\(full) min")
        }
        return Text("≈ \(full) min")
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
                        // One tone for all seven letters. Dimming the missed
                        // day to ink3 put TEXT at 2.35:1 in light and 3.02:1 in
                        // dark, both under the 4.5 this size needs, and it did
                        // it to the one column a person is most likely to be
                        // looking for (finding 69; owner's call, UX review
                        // 05.09.2026 — ink3 is a graphics tone). The day's
                        // state is the MARK below, which is what carries it for
                        // the other three statuses too.
                        .foregroundStyle(Theme.ink2)
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
                        //
                        // 0.8 was measured against English only, and every
                        // other language overruns it: the ellipsis then landed
                        // on the tail and drew the two calf steps — "on a
                        // step" and "with a pause" — as the same row
                        // (UX review 05.09.2026). Shrink further first, and
                        // when even that is not enough drop the HEAD, which
                        // is the half the sibling names share.
                        .minimumScaleFactor(0.7)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                    Text(row.detail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink2)
                        .monospacedDigit()
                        // "3×30 sec per side" is the longest dose there is,
                        // and without this it wraps to a second line under
                        // pressure — growing every row of a list that already
                        // fills the widget (UX review 05.09.2026).
                        .lineLimit(1)
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
        if let length = planLength { return length.printed }
        // The label points at the NEXT workout, so a workout day never shows
        // one — and a day with neither a plan nor a label signs itself rather
        // than guessing.
        guard entry.status != .workout, let when = entry.nextLabel else {
            return String(localized: "Dredfit")
        }
        return String(localized: "Next workout \(when)")
    }

    /// What the subline is read out as. Only the range differs: VoiceOver
    /// gets a dash between the two numbers otherwise, and the app's own line
    /// already spells this out (PlanLength).
    var sublineSpoken: String { planLength?.spoken ?? subline }

    /// The workout day's length, in the two forms the one sentence needs.
    ///
    /// It is the RANGE, not the full number alone: the lock screen is where
    /// "will this fit today" gets answered without opening the app, and the
    /// full number alone overstates what the person is agreeing to — the
    /// reason Today prints both ends (PlanLength, UX review 05.09.2026). A
    /// snapshot written before the floor existed carries one number and still
    /// prints one. nil on any day with no plan to describe.
    private var planLength: (printed: String, spoken: String)? {
        guard entry.status == .workout, let full = entry.planMinutes,
              !entry.plan.isEmpty else { return nil }
        let count = entry.plan.count
        guard let floor = entry.planMinutesFloor, floor < full else {
            let one = String(localized: "≈ \(full) min · \(count) exercises")
            return (one, one)
        }
        return (String(localized: "≈ \(floor)–\(full) min · \(count) exercises"),
                String(localized: "about \(floor) to \(full) minutes · \(count) exercises"))
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
        .description(String(localized: "Workout, done, or rest day — at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
