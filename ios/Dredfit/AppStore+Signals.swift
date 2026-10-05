//
//  Read-only signals behind the quiet lines on Today and in the history.
//  Two are safety signals derived from the journal: a run of training days
//  (#98), and the movement the journal keeps finding under an unnamed
//  "tough" (#135). Nothing here writes, and neither safety signal blocks the
//  workout or counts toward an achievement.
//

import Foundation
import DredfitCore

extension AppStore {

    /// The rest offer appears when today's workout would be at least the
    /// (threshold + 1)-th consecutive training day.
    static let longRunThreshold = 3

    /// Consecutive calendar days with a completed workout, counting back from
    /// (and including) the given day. Local-midnight day math — the SAME day
    /// math `gapDays` uses (`trainingDays`), so a test seeds both in calendar
    /// days, not elapsed seconds. Two workouts on one day count once.
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
    /// Sets can move while the name and the dose stand still — a movement
    /// half of whose sets were skipped last time comes back as `2×4 /side`
    /// under a name that carried `4×4 /side` — and a plan that quietly got
    /// easier reads as a bug exactly the way a plan that quietly got harder
    /// does.
    ///
    /// A fact, not a line: this says WHETHER there is something to explain,
    /// and `ExerciseRow` owns the words for it. Sets come off for several
    /// reasons — a skip, a descent on the dose floor, the deload, a break —
    /// so the card has to say when the engine gives one back on its own.
    ///
    /// The hold is armed by the very transition that handed a set back and
    /// spends a tick each time the movement is trained after it, so "full"
    /// means the returned set is in THIS plan. That alone is not enough to
    /// say so out loud: the session generator can still show fewer sets than
    /// the position holds, and a line about a set the card does not show
    /// would simply be false. So the journal has the last word — what the
    /// card carried the last time this movement came round.
    ///
    /// A push gets sets back a second way no hold ever sees: the pull slot's
    /// cap lifting, while the push's own position stands still. The record
    /// behind the last card says whether that card was held below the push's
    /// own sets (`WorkoutRecord.heldBack`); more sets after such a card are
    /// the held set returning. Only on the same variation — another one is
    /// another movement, and its own line says so — and only when the sets
    /// grew with a probe's slot counted: a probe leaving hands its slot to a
    /// working set and gives nothing back. A record without the stamp claims
    /// nothing.
    func aSetJustCameBack(in exercise: SessionExercise) -> Bool {
        let pattern = exercise.pattern
        guard let last = lastCard(pattern), exercise.sets > last.card.sets else { return false }
        if engineState.setsHold[pattern] == EngineConfig.setsBackHold { return true }
        return exercise.variation == last.card.variation
            && exercise.totalSets > last.card.totalSets
            && last.record.heldBack?.contains(pattern) == true
    }

    /// True when a push shows fewer sets than its last card because the pull
    /// slot's cap binds it right now: the weaker pull branch stands on fewer
    /// sets than the push's own position. A fact, not a line: `ExerciseRow`
    /// owns the words. With the bar on, the branch that caps is usually the
    /// one not in today's plan, so nothing else on screen accounts for it.
    ///
    /// A drop the push made itself — its own skipped set — leaves the cap at
    /// or above its own sets, and is not put down to the pulls. Nor is a
    /// working set a probe has taken: counted with the probe's slot, those
    /// sets did not drop, and the probe's own line says what the last set is.
    func setsJustHeldBackByThePulls(in exercise: SessionExercise) -> Bool {
        guard let gate = Engine.pullCap(on: exercise.pattern, in: engineState),
              gate.cap < gate.own,
              let last = lastCard(exercise.pattern) else { return false }
        return exercise.sets < last.card.sets && exercise.totalSets < last.card.totalSets
    }

    /// True when a push's next set waits for the pulls: it stands on its top
    /// variation below the top band, and the pull slot's cap — the weaker
    /// branch with the bar — does not reach the band above. The push enters
    /// that band only once the pulls show its sets, so a count of steps to it
    /// would promise a set the pulls decide. A fact, not a line:
    /// `PatternProgressRow` owns the words.
    func nextSetWaitsForThePulls(_ pattern: Pattern) -> Bool {
        let position = engineState.position(pattern)
        guard Library.isTop(pattern, position.variation), position.sets < EngineConfig.setsMax,
              let gate = Engine.pullCap(on: pattern, in: engineState) else { return false }
        return gate.cap <= position.sets
    }

    /// The push rows of a session that showed fewer sets than their own
    /// positions stood on — the stamp `completeWorkout` writes into the
    /// record. Read against the state the session was BUILT from: after the
    /// rating a push can stand on other sets than its card was cut from. Nil
    /// when nothing was held back, so such a record keeps its old shape.
    static func pushesHeldBack(in session: Session, builtFrom state: EngineState) -> Set<Pattern>? {
        let held = session.exercises.filter { ex in
            guard let gate = Engine.pullCap(on: ex.pattern, in: state) else { return false }
            return ex.totalSets < gate.own
        }
        return held.isEmpty ? nil : Set(held.map(\.pattern))
    }

    /// True when this movement stands on an EASIER variation than the one the
    /// last workout left it on — the plan quietly changed under a name the
    /// person recognises, and a row that got easier by itself reads as a bug
    /// exactly the way one that got harder does. A fact, not a line:
    /// `ExerciseRow` owns the words.
    ///
    /// Measured against the last record's `positionsAfter`, which is the state
    /// the journal vouches for. Everything the rating itself did is already
    /// inside that snapshot, so what is left for this to catch is what moved
    /// the plan AFTERWARDS and without a word — the handle, the blind-zone
    /// decay, an accepted comeback among them. A pattern the snapshot does not
    /// carry (a record written before v3) claims nothing.
    func aVariationJustDropped(in exercise: SessionExercise) -> Bool {
        guard let before = records.last?.positionsAfter?[exercise.pattern] else { return false }
        return exercise.variation < before.variation
    }

    /// The card this movement carried at its last appearance, and the record
    /// that carried it. Read from the journal rather than the state because
    /// it is what the person actually saw. A record too old to know its
    /// exercises ends the walk rather than being skipped over: a gap in the
    /// journal is not evidence of anything, and reading past it would compare
    /// two sessions with an unknown number in between.
    private func lastCard(_ pattern: Pattern) -> (card: SessionExercise, record: WorkoutRecord)? {
        for record in records.reversed() {
            guard let exercises = record.exercises else { return nil }
            if let was = exercises.first(where: { $0.pattern == pattern }) { return (was, record) }
        }
        return nil
    }
}

extension SessionExercise {
    /// Working sets plus the probe, when the plan carries one. The probe
    /// REPLACES a working set upstream — the engine hands back one set fewer —
    /// so the session's volume is unchanged and this count is what the person
    /// actually walks through. It is also what the pull slot's cap and a
    /// push's own sets are measured against.
    var totalSets: Int { sets + (probe == nil ? 0 : 1) }
}

// MARK: - The weak link the trainee never names (#135)

extension AppStore {

    /// A movement the journal keeps finding under an unnamed "tough" — the
    /// same threshold the engine's chronic signal uses (`chronicHits` of the
    /// last `chronicWindow` appearances: 3 of 4).
    ///
    /// The case it exists for: someone who only knows the one-tap gesture
    /// rates "tough" whenever the pushes come up. Because the pushes are in
    /// most sessions, that reads to the model as "the whole programme is too
    /// hard", while the movement that is actually the problem keeps its
    /// place in the rotation.
    ///
    /// The prompt routes to the easier VARIATION: a lighter variation changes
    /// exactly the thing the person is complaining about, immediately, and
    /// keeps the movement in the plan.
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
            // The movement that failed more often wins; a tie goes to the one
            // first in `Pattern.allCases`.
            if hits > bestHits { bestHits = hits; best = pattern }
        }
        // Nothing to suggest when the one handle the prompt offers would do
        // nothing: the movement is already in its easiest variation, so the
        // question would route into a dead control.
        guard let best else { return nil }
        guard Engine.easierPosition(pattern: best, position: engineState.position(best),
                                    shown: engineState.shown) != nil else { return nil }
        return best
    }

    /// A session where the trainee said "tough" and pointed at nothing — no
    /// number entered for any movement.
    private static func namesNothing(_ record: WorkoutRecord) -> Bool {
        (record.actuals ?? [:]).isEmpty
    }

    /// At most one prompt per session: it is a question, not a campaign.
    func shouldAskAboutSuspect() -> Bool {
        guard settings.weakLinkPromptAnsweredFor != records.last?.sessionNumber else { return false }
        return unnamedLessSuspect() != nil
    }
}

// MARK: - Who moved the plan

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
    /// above because the two are stamped one session apart: in a single slot,
    /// a handle pulled on the next plan would overwrite what the last rating
    /// had named.
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
