//
//  AppStore+Cadence.swift
//  Dredfit
//
//  The trainee's own rhythm and the training day (v2.13, spec §23 / #134, #147).
//  A steady cadence is not a break: when a new gap lands within ±1 day of any
//  of the last three gaps between workouts, the silent decay and the comeback
//  card both stand down — the plan simply waits as it is. Everything here is
//  read-only; the callers in AppStore proper make the mutating decisions.
//

import Foundation

extension AppStore {

    /// Whole 24-hour periods of true elapsed time (spec §7, #147) — the
    /// training day is anchored to the trainee, not to a wall clock. The
    /// floor crosses the 7/14-day thresholds exactly when real time does, so
    /// a drifting shift-work ritual collects no phantom break days, a rounding
    /// error only ever understates a break, and DST or a timezone trip stop
    /// being cases at all. Display places (same-day stamps, rest weekdays,
    /// the widget) stay on the calendar midnight.
    static func trainingDays(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 86_400))
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

    /// The last up-to-three gaps between consecutive journal entries — the
    /// memory a new break is compared against. Three is enough to see a
    /// rhythm through one outlier and cheap enough to recompute on the fly.
    var recentGaps: [Int] {
        let dates = records.suffix(4).map(\.date)
        guard dates.count >= 2 else { return [] }
        return zip(dates, dates.dropFirst()).map { Self.trainingDays(from: $0, to: $1) }
    }

    /// Spec §23.2 (owner decisions 16.08.2026): a break is the trainee's own
    /// rhythm when it lands within ±1 day of any of the last three gaps —
    /// with no upper cap, so any consistent ritual is respected. A real
    /// one-off break falls outside the window and is treated as before.
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
