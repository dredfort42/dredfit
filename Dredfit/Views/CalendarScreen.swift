//
//  CalendarScreen.swift
//  Dredfit
//
//  Four day states: completed (fill), planned (outline), today (accent ring),
//  rest (no mark). Missed days are NOT flagged — the engine adapts anyway.
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
                HStack(spacing: 26) {
                    Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(Text("Previous month"))
                    Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(Text("Next month"))
                }
                .dredfitFont(16, weight: .medium)
                .foregroundStyle(Theme.ink3)
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

    private enum DayState { case done, planned, today, rest, out }

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
                    Circle().stroke(Color(red: 0.85, green: 0.85, blue: 0.86), lineWidth: 1.5)
                case .today:
                    Circle().stroke(Theme.accent, lineWidth: 2)
                case .rest, .out:
                    EmptyView()
                }
            }
            .frame(height: 44)
    }

    private func foreground(_ s: DayState) -> Color {
        switch s {
        case .done:    return .white
        case .planned, .today: return Theme.ink
        case .rest:    return Theme.ink3
        case .out:     return Theme.hairline
        }
    }

    // MARK: - Month data

    private var shownMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: .now)!
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
            } else if calendar.isDateInToday(d) {
                state = .today
            } else if store.isRestDay(d) {
                state = .rest
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
        HStack(spacing: 20) {
            legendItem(AnyView(Circle().fill(Theme.ink)), label: String(localized: "completed"))
            legendItem(AnyView(Circle().stroke(Theme.ink3, lineWidth: 1.5)), label: String(localized: "planned"))
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
