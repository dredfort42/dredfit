//
//  AppStore+Signals.swift
//  Dredfit
//
//  Quiet safety signals derived from the journal (issues #100, #98): a
//  per-movement pain trend and a run of training days. Nothing here is
//  persisted — the same journal always produces the same lines, backups
//  included — and nothing blocks, colors, or counts toward an achievement.
//

import Foundation
import DredfitCore

extension AppStore {

    /// The pain line appears from this many painful appearances in a row…
    static let painTrendThreshold = 2
    /// …and starts mentioning a specialist from this many. A repeat report
    /// means the movement hurt, rested its three appearances, and hurt
    /// again — that is the "pain persists" trend the monitoring literature
    /// reacts to, not a one-off.
    static let painSpecialistThreshold = 3
    /// The rest offer appears when today's workout would be at least the
    /// (threshold + 1)-th consecutive training day.
    static let longRunThreshold = 3

    /// How many consecutive APPEARANCES of the pattern ended with a pain
    /// report, counting back from the latest. Sessions the pattern was not
    /// part of do not break the run — the engine's freeze counts in
    /// appearances the same way. A record too old to know its exercises
    /// (pre-1.4) ends the walk: honesty over reach.
    func discomfortStreak(_ pattern: Pattern) -> Int {
        var streak = 0
        for record in records.reversed() {
            guard let exercises = record.exercises else { break }
            guard exercises.contains(where: { $0.pattern == pattern }) else { continue }
            guard record.discomfort?.contains(pattern) == true else { break }
            streak += 1
        }
        return streak
    }

    /// Consecutive calendar days with a completed workout, counting back
    /// from (and including) the given day. Local-midnight day math, like
    /// `gapDays`; two workouts on one day count once.
    func consecutiveTrainingDays(endingOn day: Date) -> Int {
        let cal = Calendar.current
        let trained = Set(records.map { cal.startOfDay(for: $0.date) })
        var probe = cal.startOfDay(for: day)
        var run = 0
        while trained.contains(probe) {
            run += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: probe) else { break }
            probe = previous
        }
        return run
    }

    /// The day number today's workout would get: yesterday's run plus one.
    var wouldBeConsecutiveDay: Int {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)
        else { return 1 }
        return consecutiveTrainingDays(endingOn: yesterday) + 1
    }

    /// True when starting today's workout would make it at least the fourth
    /// training day in a row — the moment a rest offer is worth one quiet
    /// sentence. Never true once today's workout is done: the line is an
    /// offer before the fact, not a remark after it.
    var todayWouldExtendALongRun: Bool {
        !doneToday && wouldBeConsecutiveDay > Self.longRunThreshold
    }
}
