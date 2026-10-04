//
//  Taking the last rating back: whether it can be taken back. The change
//  itself, `changeLastRating`, is in AppStore.swift where the state is set,
//  because it rolls the state back without a write of its own — a write
//  between the rollback and the new rating would leave a journal without
//  the workout.
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
    func ratingRedo() -> (undo: RatingUndo, record: WorkoutRecord)? {
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
}
