//
//  Missed days are deliberately unmarked — plain dimmed numbers.
//

import SwiftUI
import DredfitCore

struct CalendarScreen: View {
    @Environment(AppStore.self) private var store
    @State private var monthOffset = 0
    @State private var nextPreviewShown = false
    @State private var historyRecord: WorkoutRecord?

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: String(localized: "Calendar"))
                .padding(.top, 18)

            HStack {
                Text(monthTitle)
                    .dredfitFont(19, weight: .bold)
                Spacer()
                // 44pt frames: the bare glyphs were ~20pt targets 26pt apart.
                HStack(spacing: 4) {
                    Button { monthOffset -= 1 } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Previous month"))
                    Button { monthOffset += 1 } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Next month"))
                }
                .dredfitFont(16, weight: .medium)
                // ink2, not ink3: interactive controls need ≥3:1 contrast.
                .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 20)

            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { d in
                    Text(d)
                        .dredfitFont(11, weight: .semibold)
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 20)

            let days = monthDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 7) {
                ForEach(days.indices, id: \.self) { i in
                    dayCell(days[i])
                }
            }
            .padding(.top, 12)

            legend.padding(.top, 22)

            if store.doneToday {
                doneCard.padding(.top, 20)
            } else {
                monthStat.padding(.top, 20)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $nextPreviewShown) {
            NextWorkoutSheet()
        }
        .sheet(item: $historyRecord) { record in
            HistorySheet(record: record)
        }
    }

    private var weekdayHeaders: [String] {
        // shortStandaloneWeekdaySymbols: index 0 = Sunday → rotate to Monday-first
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (1...7).map { symbols[$0 % 7].capitalized }
    }

    // MARK: - "Completed today → next" card

    private var doneCard: some View {
        Button {
            nextPreviewShown = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completed today ✓")
                        .dredfitFont(16, weight: .semibold)
                        .foregroundStyle(Theme.bg)
                    Text("Next: workout \(store.nextSession.sessionNumber) · \(store.nextTrainingDateLabel)")
                        .dredfitFont(13)
                        .foregroundStyle(Theme.bg.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .dredfitFont(14, weight: .semibold)
                    .foregroundStyle(Theme.bg.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Day cell

    // `missed` is distinct from `planned` so past days never carry the
    // planned ring.
    private enum DayState { case done, planned, missed, today, rest, out }

    private struct Day {
        let date: Date
        let number: Int
        let state: DayState
    }

    /// The only tappable cell among the non-completed days: the sheet always
    /// describes the one computed next workout, so no other future day has
    /// anything truthful to show.
    private func isNextTrainingDay(_ day: Day) -> Bool {
        (day.state == .planned || day.state == .today)
            && Calendar.current.isDate(day.date, inSameDayAs: store.nextTrainingDate)
    }

    @ViewBuilder
    private func dayCell(_ day: Day) -> some View {
        if day.state == .done {
            Button {
                historyRecord = store.record(on: day.date)
            } label: {
                dayLabel(day)
            }
            .buttonStyle(.plain)
        } else if isNextTrainingDay(day) {
            Button {
                nextPreviewShown = true
            } label: {
                dayLabel(day)
            }
            .buttonStyle(.plain)
        } else {
            dayLabel(day)
        }
    }

    private func dayLabel(_ day: Day) -> some View {
        Text("\(day.number)")
            .dredfitFont(15, weight: day.state == .today ? .bold : .regular)
            .monospacedDigit()
            .foregroundStyle(foreground(day.state))
            .frame(width: 36, height: 36)
            .background {
                switch day.state {
                case .done:
                    Circle().fill(Theme.ink)
                case .planned:
                    Circle().stroke(Theme.planned, lineWidth: 1.5)
                case .today:
                    Circle().stroke(Theme.accent, lineWidth: 2)
                case .rest:
                    // restFill, not cardBG: cardBG on white is 1.07:1,
                    // effectively invisible on most real screens.
                    Circle().fill(Theme.restFill)
                case .missed, .out:
                    EmptyView()
                }
            }
            .frame(height: 44)
            // A bare number reads as noise — say the date and the state the
            // ring conveys visually.
            .accessibilityHidden(day.state == .out)
            .accessibilityLabel(Text(accessibilityText(day)))
            // The label carries the full spoken date, so it is not a stable
            // query key for UI tests.
            .accessibilityIdentifier("day-\(day.number)")
    }

    private func accessibilityText(_ day: Day) -> String {
        let date = day.date.screenDateText
        switch day.state {
        case .done:    return date + ", " + String(localized: "completed")
        case .planned: return date + ", " + String(localized: "planned")
        case .today:   return date + ", " + String(localized: "today")
        case .rest:    return date + ", " + String(localized: "rest")
        // Just the date: VoiceOver gets the same silence about a missed day.
        case .missed, .out: return date
        }
    }

    private func foreground(_ s: DayState) -> Color {
        switch s {
        // bg, not .white: the digit sits on the ink fill and must flip with
        // the scheme.
        case .done:    return Theme.bg
        case .planned, .today: return Theme.ink
        // ink2, not ink3: the digit has to be readable on the rest fill.
        case .rest:    return Theme.ink2
        case .missed:  return Theme.ink3
        case .out:     return Theme.hairline
        }
    }

    // MARK: - Month data

    private var shownMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: store.today)!
    }

    private var monthTitle: String {
        shownMonth.formatted(.dateTime.month(.wide).year()).capitalized
    }

    private func monthDays() -> [Day] {
        let month = shownMonth
        let range = calendar.range(of: .day, in: .month, for: month)!
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        // Offset to Monday (weekday: 1=Sun … 7=Sat)
        let firstWeekday = calendar.component(.weekday, from: first)
        let lead = (firstWeekday + 5) % 7

        let doneDays: Set<DateComponents> = Set(store.records.map {
            calendar.dateComponents([.year, .month, .day], from: $0.date)
        })

        var days: [Day] = []
        // trailing days of the previous month
        for i in stride(from: lead, to: 0, by: -1) {
            let d = calendar.date(byAdding: .day, value: -i, to: first)!
            days.append(Day(date: d, number: calendar.component(.day, from: d), state: .out))
        }
        for n in range {
            let d = calendar.date(byAdding: .day, value: n - 1, to: first)!
            let comps = calendar.dateComponents([.year, .month, .day], from: d)
            let state: DayState
            if doneDays.contains(comps) {
                state = .done
            } else if calendar.isDate(d, inSameDayAs: store.today) {
                state = .today
            } else if store.isRestDay(d) {
                state = .rest
            } else if d < calendar.startOfDay(for: store.today) {
                state = .missed
            } else {
                state = .planned
            }
            days.append(Day(date: d, number: n, state: state))
        }
        // pad the grid to a full week with days of the next month
        var tail = 1
        while !days.count.isMultiple(of: 7) {
            let d = calendar.date(byAdding: .day, value: range.count - 1 + tail, to: first)!
            days.append(Day(date: d, number: calendar.component(.day, from: d), state: .out))
            tail += 1
        }
        return days
    }

    // MARK: - Legend and month stat

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(AnyView(Circle().fill(Theme.ink)), label: String(localized: "completed"))
            legendItem(AnyView(Circle().stroke(Theme.planned, lineWidth: 1.5)), label: String(localized: "planned"))
            legendItem(AnyView(Circle().fill(Theme.restFill)), label: String(localized: "rest"))
            legendItem(AnyView(Circle().stroke(Theme.accent, lineWidth: 2)), label: String(localized: "today"))
        }
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ shape: AnyView, label: String) -> some View {
        HStack(spacing: 7) {
            shape.frame(width: 13, height: 13)
            Text(label).dredfitFont(12.5).foregroundStyle(Theme.ink2)
        }
    }

    private var monthStat: some View {
        let comps = calendar.dateComponents([.year, .month], from: shownMonth)
        let done = store.records.filter {
            let c = calendar.dateComponents([.year, .month], from: $0.date)
            return c.year == comps.year && c.month == comps.month
        }.count

        return HStack {
            // The count follows the month on screen, so the label must too.
            Text(calendar.isDate(shownMonth, equalTo: store.today, toGranularity: .month)
                 ? String(localized: "This month")
                 : monthTitle)
                .dredfitFont(13.5)
                .foregroundStyle(Theme.ink2)
            Spacer()
            Text("\(done) completed")
                .dredfitFont(15, weight: .semibold)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 16))
    }
}
