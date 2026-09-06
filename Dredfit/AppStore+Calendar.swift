//
//  Where the plan lands on a calendar: the next training day, the label the
//  cards show for it, and the week summary. All read-only — the mutating
//  decisions stay in AppStore proper. Split out when the class outgrew the
//  lint's ceiling; the code is unchanged.
//

import Foundation
import DredfitCore

extension AppStore {

    var nextTrainingDate: Date { nextTrainingDate(from: today) }

    func nextTrainingDate(from now: Date) -> Date {
        let cal = Calendar.current
        var d = now
        if isDone(on: now) || isRestDay(d) {
            var hops = 0
            repeat {
                d = cal.date(byAdding: .day, value: 1, to: d)!
                hops += 1
            } while isRestDay(d) && hops < 7   // toggleRestDay guarantees ≥ 1 training day
        }
        return d
    }

    /// Whether the PLAN rests on this day — the question Today and the widget
    /// ask, as opposed to "is this weekday marked as rest", which is what
    /// `isRestDay` answers for the settings rows and the calendar grid.
    ///
    /// Rest is rest FROM something. An install that has never trained lands on
    /// a rest day whenever onboarding happens to end on one, and the first
    /// thing the app then says is "come back on Tuesday" — to the one person
    /// who has just decided to start (UX review 05.09.2026, finding 7). The
    /// marked weekdays keep their meaning everywhere else, including the next
    /// training date: the difference is only that nothing is being rested yet.
    ///
    /// The widget reads it for TODAY as well (`widgetStatus`), or the two
    /// disagree on the first day — which they did until review 06.09.2026,
    /// while this line already claimed otherwise. Only for today: the other
    /// thirteen days of the widget's grid are the plan ahead, and the marked
    /// weekdays still describe it.
    func restApplies(on date: Date) -> Bool { !records.isEmpty && isRestDay(date) }

    var restAppliesToday: Bool { restApplies(on: today) }

    /// The week is Monday–Sunday regardless of locale.
    struct WeekSummary: Equatable {
        let workouts: Int
        let stepsDelta: Int
    }

    /// Deload weeks can be negative — that is honest, not an error.
    /// nil `date` = the store's anchor, so callers stay midnight-reactive.
    func weekSummary(for date: Date? = nil) -> WeekSummary {
        let date = date ?? today
        var cal = Calendar(identifier: .iso8601)   // Monday-first weeks
        cal.timeZone = Calendar.current.timeZone
        guard let week = cal.dateInterval(of: .weekOfYear, for: date) else {
            return WeekSummary(workouts: 0, stepsDelta: 0)
        }
        let inWeek = records.filter { $0.date >= week.start && $0.date < week.end }
        guard let last = inWeek.last else { return WeekSummary(workouts: 0, stepsDelta: 0) }
        // Records from before v3 carry no point on this scale, so a week that
        // straddles the update measures from zero rather than from a number
        // that meant something else. A clean start reads zero too, so the
        // first v3 week is honest either way.
        let baseline = records.last { $0.date < week.start }?.totalProgressAfter ?? 0
        return WeekSummary(workouts: inWeek.count,
                           stepsDelta: (last.totalProgressAfter ?? baseline) - baseline)
    }

    var nextTrainingDateLabel: String { nextTrainingDateLabel(from: today) }

    /// From an arbitrary day: the widget carries one per day, because a
    /// timeline entry rendered days after the write must still say the right
    /// relative word.
    func nextTrainingDateLabel(from day: Date) -> String {
        let cal = Calendar.current
        let d = nextTrainingDate(from: day)
        if cal.isDate(d, inSameDayAs: day) { return String(localized: "today") }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: day),
           cal.isDate(d, inSameDayAs: tomorrow) { return String(localized: "tomorrow") }
        let weekday = d.formatted(.dateTime.weekday(.wide))
        let index = cal.component(.weekday, from: d)   // 1 = Sunday … 7 = Saturday
        switch Locale.current.language.languageCode {
        case .russian:
            return russianOnWeekday(index)
        case .portuguese:
            // Weekday gender: o sábado / o domingo, a segunda…sexta-feira.
            return (index == 1 || index == 7 ? "no " : "na ") + weekday
        default:
            return String(localized: "on \(weekday)")
        }
    }

    /// The formatter only gives the nominative; this needs the accusative.
    private func russianOnWeekday(_ index: Int) -> String {
        switch index {
        case 1: return "в воскресенье"
        case 2: return "в понедельник"
        case 3: return "во вторник"
        case 4: return "в среду"
        case 5: return "в четверг"
        case 6: return "в пятницу"
        default: return "в субботу"
        }
    }
}
