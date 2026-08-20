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
    /// from (and including) the given day. Local-midnight day math — a
    /// display place, deliberately unlike `gapDays`, which counts whole
    /// elapsed 24h periods (v2.13, spec §7); two workouts on one day count once.
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

// MARK: - The weak link the trainee never names (v2.15, spec §26.3, #135)

extension AppStore {

    /// A movement the journal keeps finding under an unnamed "tough" — the
    /// same threshold the engine's chronic signal uses (3 of the last 4 of its
    /// appearances), so the app and the model agree on what "keeps failing"
    /// means.
    ///
    /// The audit's shoulder persona is the case: someone who only knows the
    /// one-tap gesture rates "tough" whenever the pushes come up. Because the
    /// pushes are in most sessions, that reads to the model as "the whole
    /// programme is too hard", and nine weeks later the programme is gone —
    /// while the movement that actually hurts is still in every plan. The
    /// "Something hurt" button has existed since 1.10; the price of never
    /// discovering it was everything else.
    func unnamedLessSuspect() -> Pattern? {
        var best: Pattern?
        var bestHits = 0
        for pattern in Pattern.ordered + [.pullBar] {
            var hits = 0, seen = 0
            for record in records.reversed() {
                guard let exercises = record.exercises else { break }
                guard exercises.contains(where: { $0.pattern == pattern }) else { continue }
                seen += 1
                if record.result == .less && Self.namesNothing(record) { hits += 1 }
                if seen == EngineConfig.chronicWindow { break }
            }
            guard seen == EngineConfig.chronicWindow, hits >= EngineConfig.chronicHits else { continue }
            // A tie goes to the movement that failed more often, then to the
            // one the rotation shows first — the same order the engine walks.
            if hits > bestHits { bestHits = hits; best = pattern }
        }
        // Nothing to suggest while the movement is already resting or its pain
        // is already on record: the path this prompt routes into is taken.
        guard let best, engineState.freezeRemaining(best) == 0,
              engineState.sore[best] == nil else { return nil }
        return best
    }

    /// A session where the trainee said "tough" and pointed at nothing: no
    /// exact numbers and no pain report. v2.22 (spec §33): the third signal —
    /// a hold request — is cancelled, so the list is down to two.
    private static func namesNothing(_ record: WorkoutRecord) -> Bool {
        (record.actuals ?? [:]).isEmpty
            && (record.discomfort ?? []).isEmpty
    }

    /// At most one prompt per session (spec §26.3): it is a question, not a
    /// campaign.
    func shouldAskAboutSuspect() -> Bool {
        guard settings.weakLinkPromptAnsweredFor != records.last?.sessionNumber else { return false }
        return unnamedLessSuspect() != nil
    }
}
