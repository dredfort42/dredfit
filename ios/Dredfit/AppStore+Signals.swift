//
//  Quiet safety signals derived from the journal (issues #100, #98): a run of
//  training days, and the movement the journal keeps finding under an unnamed
//  "tough". Nothing here is persisted — the same journal always produces the
//  same lines, backups included — and nothing blocks, colors, or counts toward
//  an achievement.
//
//  The per-movement PAIN TREND is gone with the channel it read. Both of its
//  rungs — "it hurt again" and "time to see a specialist" — counted pain
//  reports, and there are none to count.
//

import Foundation
import DredfitCore

extension AppStore {

    /// The rest offer appears when today's workout would be at least the
    /// (threshold + 1)-th consecutive training day.
    static let longRunThreshold = 3

    /// Consecutive calendar days with a completed workout, counting back from
    /// (and including) the given day. Local-midnight day math — the SAME day
    /// math `gapDays` uses. This sentence used to end "deliberately unlike
    /// `gapDays`, which counts whole elapsed 24h periods", and it outlived the
    /// change it described: #172 (v2.24) moved `gapDays` onto `startOfDay` too,
    /// because Monday 23:00 → Tuesday 01:00 was a zero-day gap to the decay and
    /// the comeback card. Nothing here is "unlike" anything any more, and a
    /// reader who trusted the old note would seed a test in elapsed seconds.
    /// Two workouts on one day still count once.
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

// MARK: - Why the card shows the number it does

extension AppStore {

    /// The one thing an exercise card has to explain about its own set count.
    /// Sets move without levels — a movement half of whose sets were skipped
    /// last time comes back as `2×4 /side` under a name that carried
    /// `4×4 /side` — and a plan that quietly got easier reads as a bug exactly
    /// the way a plan that quietly got harder does.
    ///
    /// A fact, not a line: this says WHETHER there is something to explain,
    /// and `ExerciseRow` owns the words for it. The "pain is holding the
    /// volume down" rung is gone with the episode, which is what took the type
    /// here down from an enum to a Bool — and what is left matters more now,
    /// not less: sets come off because the person skipped them, so the card
    /// has to say when the engine gives one back on its own.
    ///
    /// The hold is armed by the very transition that handed a set back and
    /// spends a tick on each appearance after it, so "full" means the returned
    /// set is in THIS plan. That alone is not enough to say so out loud: the
    /// gate and the postcondition repair both cut AFTER the handle, and a line
    /// about a set the card does not show would simply be false. So the
    /// journal has the last word — what the card carried the last time this
    /// movement came round.
    func aSetJustCameBack(in exercise: SessionExercise) -> Bool {
        let pattern = exercise.pattern
        guard engineState.setsHold[pattern] == EngineConfig.setsBackHold,
              let before = lastShownSets(pattern) else { return false }
        return exercise.sets > before
    }

    /// True when this movement stands on an EASIER variation than the one the
    /// last workout left it on — the plan quietly changed under a name the
    /// person recognises, and a row that got easier by itself reads as a bug
    /// exactly the way one that got harder does (UX review 05.09.2026,
    /// finding 3). A fact, not a line: `ExerciseRow` owns the words.
    ///
    /// Measured against the last record's `positionsAfter`, which is the state
    /// the journal vouches for. Everything the rating itself did is already
    /// inside that snapshot, so what is left for this to catch is exactly what
    /// moved the plan AFTERWARDS and without a word: the handle, the
    /// blind-zone decay, an accepted comeback. A pattern the snapshot does not
    /// carry (a record written before v3) claims nothing.
    func aVariationJustDropped(in exercise: SessionExercise) -> Bool {
        guard let before = records.last?.positionsAfter?[exercise.pattern] else { return false }
        return exercise.variation < before.variation
    }

    /// The set count this movement's card carried at its last appearance.
    /// Read from the journal rather than the state because it is what the
    /// person actually saw. A record too old to know its exercises ends the
    /// walk rather than being skipped over: a gap in the journal is not
    /// evidence of anything, and reading past it would compare two sessions
    /// with an unknown number in between.
    private func lastShownSets(_ pattern: Pattern) -> Int? {
        for record in records.reversed() {
            guard let exercises = record.exercises else { return nil }
            if let was = exercises.first(where: { $0.pattern == pattern }) { return was.sets }
        }
        return nil
    }
}

// MARK: - The weak link the trainee never names (#135)

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
    /// while the movement that is actually the problem is still in every plan.
    ///
    /// The prompt used to route to "Something hurt", and that button no longer
    /// exists. It routes to the easier VARIATION instead, which is the better
    /// destination anyway: the pain report took the movement's volume away and
    /// gave nothing back for weeks, while a lighter variation changes exactly
    /// the thing the person is complaining about, immediately, and keeps the
    /// movement in the plan.
    func unnamedLessSuspect() -> Pattern? {
        var best: Pattern?
        var bestHits = 0
        for pattern in Pattern.allCases {
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
        // Nothing to suggest when the one handle the prompt offers would do
        // nothing: the movement is already in its easiest variation, so the
        // question would route into a dead control. The sets half of this
        // guard went with the handle it named — volume is answered inside the
        // workout now, and a prompt on the plan cannot offer it.
        guard let best else { return nil }
        guard Engine.easierPosition(pattern: best, position: engineState.position(best),
                                    shown: engineState.shown) != nil else { return nil }
        return best
    }

    /// A session where the trainee said "tough" and pointed at nothing. Two
    /// earlier waves cancelled the hold request and then the pain report — so
    /// "naming something" is down to ONE signal, exact numbers, and the check
    /// says so rather than listing an empty set.
    private static func namesNothing(_ record: WorkoutRecord) -> Bool {
        (record.actuals ?? [:]).isEmpty
    }

    /// At most one prompt per session: it is a question, not a campaign.
    func shouldAskAboutSuspect() -> Bool {
        guard settings.weakLinkPromptAnsweredFor != records.last?.sessionNumber else { return false }
        return unnamedLessSuspect() != nil
    }
}

// MARK: - Who moved the plan (UX review 05.09.2026, findings 27 and 64)

/// The read side of `PlanMoves`. Everything here is stamped at the moment the
/// plan moves — see the type — because the journal cannot be asked afterwards:
/// between two entries the state is also moved by the silent decay and by an
/// accepted comeback, so a difference of two records credits the workout with
/// a descent that was not its doing.
extension AppStore {

    /// The stamped facts, and only while they still describe the session being
    /// asked about. A stale stamp says nothing rather than something about
    /// another week.
    func planMoves(for session: Int) -> PlanMoves? {
        guard let moves = settings.planMoves, moves.session == session else { return nil }
        return moves
    }

    /// The same question of the slot the rating owns. Separate from the one
    /// above because the two are stamped one session apart: while a single
    /// slot held both, a handle pulled on the next plan overwrote what the
    /// last rating had named (review 06.09.2026).
    func ratingMoves(for session: Int) -> PlanMoves? {
        guard let moves = settings.ratingMoves, moves.session == session else { return nil }
        return moves
    }

    /// Movements the athlete lowered by hand for the plan STILL AHEAD — the
    /// one Today is showing. Spent by the workout that follows, which is when
    /// the same facts become the last record's.
    var easedByHandAhead: [Pattern] { planMoves(for: engineState.counter + 1)?.byHand ?? [] }

    /// Which movements a finished workout's rating actually eased, and which
    /// ones the athlete eased by hand around it.
    ///
    /// THE LAST WORKOUT ONLY. Nothing is written into the journal itself, so
    /// an earlier record has no attribution to give and this returns empty
    /// rather than guessing — and the identity check is by `id`, because
    /// `sessionNumber` restarts at a reset and would otherwise let a stamp
    /// belong to two different workouts.
    func easedByRating(in record: WorkoutRecord) -> [Pattern] { moves(of: record)?.byRating ?? [] }

    func easedByHand(in record: WorkoutRecord) -> [Pattern] { moves(of: record)?.byHand ?? [] }

    /// From `ratingMoves`, never from `planMoves`: the finished session's facts
    /// move into the rating's slot as the rating lands, and the plan-ahead slot
    /// belongs to the handle from that moment on.
    private func moves(of record: WorkoutRecord) -> PlanMoves? {
        guard records.last?.id == record.id else { return nil }
        return ratingMoves(for: record.sessionNumber)
    }
}
