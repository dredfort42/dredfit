//
//  CalendarScreen.swift
//  Dredfit
//
//  Day states: completed (fill), planned (outline, future only), today
//  (accent ring), rest (quiet fill). Missed days are NOT flagged — they are
//  plain dimmed numbers, deliberately unmarked and unshamed, and since v1.7
//  the code finally agrees with this sentence.
//  UPDATE-3: tapping a completed day opens that workout's history.
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
                // 44pt frames: the bare chevron glyphs were ~20pt tap targets
                // sitting 26pt apart — easy to mis-tap.
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

            // Weekday header, Monday-first, localized by the system calendar
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
                        .foregroundStyle(.white)
                    Text("Next: workout \(store.nextSession.sessionNumber) · \(store.nextTrainingDateLabel)")
                        .dredfitFont(13)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .dredfitFont(14, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Day cell

    // v1.7 adds `missed`: a past training day that did not happen. It is NOT
    // the same as `planned` — the header's promise ("missed days are left as
    // plain dimmed numbers, deliberately unmarked and unshamed") used to be
    // broken by giving past days the planned ring.
    private enum DayState { case done, planned, missed, today, rest, out }

    private struct Day {
        let date: Date
        let number: Int
        let state: DayState
    }

    @ViewBuilder
    private func dayCell(_ day: Day) -> some View {
        if day.state == .done {
            // UPDATE-3: a completed day is tappable and opens history
            Button {
                historyRecord = store.record(on: day.date)
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
                    // v1.4 (I-4): a rest day used to carry no mark at all,
                    // leaving it to read like a day outside the month. A soft
                    // fill says "a day, deliberately quiet".
                    // restFill, not cardBG (v1.7): cardBG on white is 1.07:1 —
                    // on most real screens the fill simply was not there and
                    // the I-4 fix never landed.
                    Circle().fill(Theme.restFill)
                case .missed, .out:
                    EmptyView()
                }
            }
            .frame(height: 44)
            // VoiceOver: a bare number reads as noise — say the date and the
            // state the ring conveys visually. Out-of-month padding is noise
            // either way and disappears from the accessibility tree.
            .accessibilityHidden(day.state == .out)
            .accessibilityLabel(Text(accessibilityText(day)))
            // UI tests address cells by number: the label now carries the
            // full spoken date, so it is no longer a stable query key.
            .accessibilityIdentifier("day-\(day.number)")
    }

    private func accessibilityText(_ day: Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        switch day.state {
        case .done:    return date + ", " + String(localized: "completed")
        case .planned: return date + ", " + String(localized: "planned")
        case .today:   return date + ", " + String(localized: "today")
        case .rest:    return date + ", " + String(localized: "rest")
        // Deliberately just the date: VoiceOver gets the same unshamed
        // silence about a missed day that sighted users do.
        case .missed, .out: return date
        }
    }

    private func foreground(_ s: DayState) -> Color {
        switch s {
        case .done:    return .white
        case .planned, .today: return Theme.ink
        // ink2, not ink3 (v1.7): the rest fill is now visible, so its digit
        // has to be readable on it too.
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
                // A "planned" ring on a day already in the past would be a
                // shaming mark wearing a neutral name (v1.7).
                state = .missed
            } else {
                state = .planned
            }
            days.append(Day(date: d, number: n, state: state))
        }
        // pad the grid to a full week with days of the next month
        var tail = 1
        while days.count % 7 != 0 {
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
            Text("This month")
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
