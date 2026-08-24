//
// The trainee's own rhythm and the training day (#134, #147). A steady cadence
// is not a break: when a new gap lands within ±1 day of any of the last three
// gaps between workouts, the silent decay and the comeback card both stand
// down — the plan simply waits as it is. Everything here is read-only; the
// callers in AppStore proper make the mutating decisions.
//

import Foundation
import DredfitCore

extension AppStore {

    /// CALENDAR days in the local zone — the number of midnights between the
    /// two workouts, not the number of whole 24-hour periods. Everything about
    /// rhythm is calendar-shaped in the trainee's head: "yesterday", "every
    /// Sunday", "two weeks off". Counting elapsed hours instead put Monday
    /// 23:00 → Tuesday 01:00 at ZERO days, which is a gap the decay, the
    /// comeback card, the cadence detector and the frequency guard all read —
    /// and it made a clock change or a flight into a phantom day in either
    /// direction. The autumn DST day is 25 hours long and the spring one 23,
    /// and `startOfDay` is right about both.
    ///
    /// The thresholds themselves (7–13 decay, ≥14 comeback, ≥90 fresh start,
    /// 2–14 illness) are untouched: this changes what a day IS, not how many
    /// of them mean what.
    ///
    /// The weekly window keeps its own fractional gap (`gapFraction`) — the
    /// engine's weekly window ages in fractions of a day and must not be
    /// rounded to midnights. The calendar is a parameter only so the DST
    /// boundary can be pinned by a test in a zone that actually has one —
    /// production always passes `.current`, which is the trainee's own zone.
    static func trainingDays(from start: Date, to end: Date,
                             calendar cal: Calendar = .current) -> Int {
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: start),
                                      to: cal.startOfDay(for: end)).day
        // Clamped at zero: the phone's timezone can move between sessions (and
        // its clock can be set backwards), which would otherwise hand the
        // engine a negative gap. Capped at countMax for the same reason the
        // old arithmetic was — a corrupt journal date must not overflow.
        guard let days else { return 0 }
        return min(max(days, 0), EngineConfig.countMax)
    }

    /// Training days since the last workout — the one number the engine's
    /// time functions read. Nil while the journal is empty. Measured to the
    /// real clock, not the `today` anchor: `today` freezes at the day's first
    /// activation, which was harmless under midnight math but would hold the
    /// card and the quiet offers up to a day behind the decay path now.
    func gapDays(now: Date? = nil) -> Int? {
        guard let last = records.last else { return nil }
        return Self.trainingDays(from: last.date, to: now ?? Date())
    }

    /// The same elapsed time, NOT floored — the fraction of a day the engine's
    /// weekly window needs. `trainingDays` throws it away, so two workouts
    /// inside one day handed the engine a zero, the window never aged, and the
    /// weekly growth budget was spent once for a lifetime (48 levels against
    /// 423 over 120 sessions). This feeds `applyFeedback` and nothing else:
    /// the decay, the comeback and the cadence keep counting whole training
    /// days.
    func gapFraction(now: Date? = nil) -> Double? {
        guard let last = records.last else { return nil }
        let days = (now ?? Date()).timeIntervalSince(last.date) / 86_400
        guard days.isFinite else { return 0 }
        return min(max(days, 0), Double(EngineConfig.countMax))
    }

    /// The last up-to-three gaps between consecutive journal entries — the
    /// memory a new break is compared against. Three is enough to see a
    /// rhythm through one outlier and cheap enough to recompute on the fly.
    var recentGaps: [Int] {
        let dates = records.suffix(4).map(\.date)
        guard dates.count >= 2 else { return [] }
        return zip(dates, dates.dropFirst()).map { Self.trainingDays(from: $0, to: $1) }
    }

    /// (owner decisions 16.08.2026): a break is the trainee's own rhythm when
    /// it lands within ±1 day of any of the last three gaps — with no upper
    /// cap, so any consistent ritual is respected. A real one-off break falls
    /// outside the window and is treated as before.
    ///
    /// The second clause covers mid-cycle opens: reminders fire on every
    /// non-rest day, so a 10-day-cadence trainee routinely opens the app on
    /// day 7 of the cycle — a silence that has not yet outgrown the rhythm is
    /// no break either. That window comes only from gaps that repeat (have a
    /// ±1 partner among the last three), so one long vacation does not shield
    /// the next absence from the comeback.
    func isRhythmBreak(_ gap: Int) -> Bool {
        let gaps = recentGaps
        if gaps.contains(where: { abs($0 - gap) <= 1 }) { return true }
        let rhythmic = gaps.indices.filter { i in
            gaps.indices.contains { j in j != i && abs(gaps[j] - gaps[i]) <= 1 }
        }.map { gaps[$0] }
        guard let ceiling = rhythmic.max() else { return false }
        return gap <= ceiling + 1
    }
}
