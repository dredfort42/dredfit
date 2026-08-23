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
    /// …and starts mentioning a specialist from this many REPORTS — the
    /// engine's `painSeen`, its memory of how many times this movement has
    /// hurt over the whole history (v2.25, spec §36.5).
    ///
    /// It used to hang on the RUN of reports, and the run is exactly what the
    /// 3 / 6 / 12 rest is built to break: the movement hurts, rests its
    /// appearances, comes back healthy — and the count it needed to reach
    /// three was back at zero. Nobody the line was written for ever saw it.
    /// The memory does not reset; it only fades, by one, after a break of
    /// ninety days (§36.5), because a break is precisely what a person in
    /// pain takes.
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

    /// What the resting line has to say about a movement beyond "it is not
    /// getting harder" (#100). Two rungs, and the upper one is the engine's,
    /// not the journal's — see `painSpecialistThreshold`.
    enum PainNote {
        /// It hurt on both of its last two appearances: a report, a rest, and
        /// a report again.
        case hurtAgain
        /// It has hurt `painSpecialistThreshold` times over its history,
        /// however far apart those times were.
        case seeSpecialist
    }

    /// The escalation wins wherever both could fire: a history of three
    /// reports is the stronger fact, and only one sentence is ever shown.
    func painNote(_ pattern: Pattern) -> PainNote? {
        if (engineState.painSeen[pattern] ?? 0) >= Self.painSpecialistThreshold {
            return .seeSpecialist
        }
        if discomfortStreak(pattern) >= Self.painTrendThreshold { return .hurtAgain }
        return nil
    }

    /// True when starting today's workout would make it at least the fourth
    /// training day in a row — the moment a rest offer is worth one quiet
    /// sentence. Never true once today's workout is done: the line is an
    /// offer before the fact, not a remark after it.
    var todayWouldExtendALongRun: Bool {
        !doneToday && wouldBeConsecutiveDay > Self.longRunThreshold
    }
}

// MARK: - Why the card shows the number it does (v2.25, spec §36.2)

extension AppStore {

    /// What an exercise card has to explain about its own set count. The
    /// handle of v2.25 moves sets, not levels, so `1×4 /side` can appear
    /// under a name that used to carry `4×4 /side` with nothing on screen
    /// having changed — and a plan that quietly got easier reads as a bug
    /// exactly the way a plan that quietly got harder does.
    enum SetsNote {
        /// The pain channel is holding the volume down while the episode runs.
        case painCut
        /// A set has just come back.
        case setBack
    }

    /// One line per card at most, and only while it is true — no notification,
    /// no card of its own, nothing to dismiss.
    func setsNote(for exercise: SessionExercise) -> SetsNote? {
        let pattern = exercise.pattern
        // The STORED cut, never the shown one: the illness lens takes sets off
        // as a view (§36.6) and has its own sentence on Today already, and the
        // §20.2 gate takes them off for a reason that has nothing to do with
        // pain. A live episode plus a cut is the pain channel and only it.
        if engineState.sore[pattern] != nil, engineState.cutOf(pattern) > 0 {
            return .painCut
        }
        // The hold is armed by the very transition that handed a set back and
        // spends a tick on each appearance after it, so "full" means the
        // returned set is in THIS plan (§36.3). That alone is not enough to
        // say so out loud: the gate, the budget and the postcondition repair
        // all cut AFTER the handle, and a line about a set the card does not
        // show would simply be false. So the journal has the last word — what
        // the card carried the last time this movement came round.
        if engineState.setsHold[pattern] == EngineConfig.setsBackHold,
           let before = lastShownSets(pattern), exercise.sets > before {
            return .setBack
        }
        return nil
    }

    /// The set count this movement's card carried at its last appearance.
    /// Read from the journal rather than the state because it is what the
    /// person actually saw. A record too old to know its exercises (pre-1.4)
    /// ends the walk, the same way the pain streak's does.
    private func lastShownSets(_ pattern: Pattern) -> Int? {
        for record in records.reversed() {
            guard let exercises = record.exercises else { return nil }
            if let was = exercises.first(where: { $0.pattern == pattern }) { return was.sets }
        }
        return nil
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
