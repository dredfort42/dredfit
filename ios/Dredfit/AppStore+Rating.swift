//
//  Taking the last rating back. Its own file rather than a section of
//  AppStore.swift for the reason `AppStore+Backup`, `+Health` and
//  `+Reminders` have their own: that file stands against the linter's
//  1200-line ceiling, which is a CI error rather than a style opinion, and
//  the rule for it is to split rather than to grow.
//
//  It MUTATES, unlike +Cadence/Calendar/Comeback/Handles/Signals — the whole
//  decision is here, in one place, the way the store's other writing
//  extensions are.
//

import Foundation
import DredfitCore

// MARK: - Taking a rating back (UX review 05.09.2026, finding 25)

/// A rating is one tap and it is spent: it moves every movement of the session
/// and the journal keeps only the answer. Owner decision 1 (05.09.2026) makes
/// a way back mandatory rather than nice — a workout nobody rated is now
/// settled as "on plan" on the athlete's behalf, so the first rating a person
/// ever sees may be one they never gave.
///
/// Not an EDIT of the journal entry: the other rating is re-applied to the
/// state the first one was applied to, so the engine lands exactly where it
/// would have landed had the other card been tapped. A hand-patched record
/// would leave the state and the history disagreeing, and only the state is
/// what the next plan is built from.
extension AppStore {

    var canChangeLastRating: Bool { ratingRedo() != nil }

    /// The whole guard in one place: an undo that belongs to the last record,
    /// a state still standing exactly where that record left it, and no second
    /// workout since. Anything else — a comeback accepted, a handle pulled,
    /// the silent decay, another session — and the rating is history rather
    /// than a decision still open, because rolling back would take that other
    /// movement with it.
    private func ratingRedo() -> (undo: RatingUndo, record: WorkoutRecord)? {
        guard let undo = settings.lastRatingUndo, let record = records.last,
              record.sessionNumber == undo.session.sessionNumber,
              undo.state.counter + 1 == undo.session.sessionNumber,
              engineState.counter == record.sessionNumber,
              record.positionsAfter == currentPositions,
              // A workout already under way closes this door, and none of the
              // guards above can see one: starting a session moves neither the
              // counter nor the positions, so every one of them still passes.
              // `completeWorkout` opens with `pendingWorkout = nil` — the
              // re-applied rating would take a half-finished session down with
              // it, silently and unrecoverably, while the alert asked only
              // about the rating (self-review 05.09.2026).
              pendingWorkout?.hasProgress != true else { return nil }
        return (undo, record)
    }

    /// - Returns: the milestones the NEW rating earns, exactly as the first
    ///   tap would have. Empty when there is nothing to change.
    @discardableResult
    func changeLastRating(to result: FeedbackResult) -> [Milestone] {
        guard let redo = ratingRedo(), redo.record.result != result else { return [] }
        // A clean rollback, nothing carried across. The one thing the engine
        // wrote after the rating is the shown-plan memory of the NEXT plan
        // (`recordPlanShown` → `shownWork`/`shownOrd`), and `applyFeedback`
        // rewrites that pair for every movement of the session it settles —
        // so re-applying reproduces the post-rating state exactly, and the
        // next render of Today, which is the screen this button is on, writes
        // the new plan's memory back. Carrying the later pair over instead
        // would describe a plan that no longer exists.
        engineState = redo.undo.state
        records.removeLast()
        let facts = redo.record.setActuals ?? [:]
        let milestones = completeWorkout(
            session: redo.undo.session,
            result: result,
            overrides: SetFacts.overrides(facts, in: redo.undo.session.exercises),
            setActuals: facts,
            skipped: redo.record.skipped ?? [],
            setsSkipped: redo.record.setsSkipped ?? [:],
            probes: redo.record.probes ?? [:],
            durationSec: redo.record.durationSec,
            warmupSec: redo.record.warmupSec, cooldownSec: redo.record.cooldownSec,
            interrupted: redo.record.interrupted,
            // The addition was the person's decision about the movement, not
            // about the rating: a changed rating keeps it.
            raised: redo.record.raisedSteps ?? [:],
            date: redo.record.date)
        // Apple Health already holds this workout and nothing about it changed
        // — same day, same duration, same effort. Carrying the mark over is
        // what stops the backfill writing a second copy, and it lands in time:
        // the export task is created on this actor and cannot begin until this
        // call has returned.
        if let last = records.indices.last {
            records[last].healthExported = redo.record.healthExported
        }
        persist()
        return milestones
    }
}
