//
//  The lifecycle of a workout in progress, as the store keeps it: the
//  snapshot the flow writes on every phase transition, and what becomes of it.
//  What counts as still the same occasion, and what a settlement records, is
//  WorkoutSessionStore's.
//

import Foundation
import DredfitCore

extension AppStore {

    private func validPendingWorkout() -> (snapshot: WorkoutSnapshot, session: Session)? {
        let session = nextSession
        guard let snap = WorkoutSessionStore.valid(pendingWorkout, plan: session,
                                                   counter: engineState.counter)
        else { return nil }
        return (snap, session)
    }

    /// Fresh enough to be the same occasion, and nothing completed today.
    func resumableWorkout(now: Date = .now) -> WorkoutSnapshot? {
        guard let snap = validPendingWorkout()?.snapshot, !doneToday,
              now.timeIntervalSince(snap.savedAt) < WorkoutSessionStore.resumeWindow
        else { return nil }
        return snap
    }

    /// Past the occasion but not yet forgotten — the band where the athlete is
    /// ASKED rather than answered for (owner, 06.09.2026): ready to carry on,
    /// or keep what is already done?
    ///
    /// Recording it unasked after three hours was the previous rule and it was
    /// wrong in the ordinary case: three hours is a long lunch, not a lost
    /// session, and the plan came back rated by nobody.
    ///
    /// The store has no "keep it" of its own on purpose. Answering the card
    /// opens the flow on its RATING screen, so the athlete says how it went
    /// themselves — the only thing recorded on anyone's behalf is a workout
    /// nobody came back to for half a day (owner, 06.09.2026).
    func unfinishedWorkoutAwaitingAnswer(now: Date = .now) -> WorkoutSnapshot? {
        guard let snap = validPendingWorkout()?.snapshot, !doneToday else { return nil }
        let age = now.timeIntervalSince(snap.savedAt)
        guard age >= WorkoutSessionStore.resumeWindow,
              age < WorkoutSessionStore.forgottenAfter else { return nil }
        return snap
    }

    /// The automatic path, and the ONLY one that decides for the athlete: a
    /// workout nobody came back to for twelve hours.
    ///
    /// A workout that was trained and never rated used to vanish altogether —
    /// the journal is written by `completeWorkout` alone and its only caller
    /// is the tap on a rating card, so putting the phone down on "How did it
    /// go?" and letting iOS unload the process erased the whole session, for
    /// exactly the people who train late (UX review 05.09.2026, 🔴 01).
    @discardableResult
    func settleAbandonedWorkout(now: Date = .now) -> Bool {
        // A flow on screen OWNS this snapshot: it will finish the workout
        // itself. Settling underneath it advanced the engine's counter, and
        // the rating the athlete then gave failed `completeWorkout`'s replay
        // guard and was dropped in silence — the session stood recorded as
        // "on plan" and the honest answer never reached the engine. Reachable
        // because `activate()` runs on every foreground and the flow is a
        // cover presented from a screen that stays alive under it
        // (self-review 06.09.2026).
        guard !workoutIsOnScreen,
              let snap = pendingWorkout,
              now.timeIntervalSince(snap.savedAt) >= WorkoutSessionStore.forgottenAfter
        else { return false }
        return settlePendingWorkout(now: now)
    }

    /// Writes what was done and clears the snapshot either way: a snapshot
    /// that can no longer be recorded honestly must not linger to be asked
    /// about again tomorrow.
    @discardableResult
    private func settlePendingWorkout(now: Date) -> Bool {
        guard pendingWorkout != nil else { return false }
        guard let (snap, session) = validPendingWorkout() else {
            pendingWorkout = nil
            persist()
            return false
        }
        pendingWorkout = nil
        let settled = WorkoutSessionStore.settlement(of: snap, in: session)
        completeWorkout(
            session: session,
            result: .plan,
            overrides: settled.overrides,
            setActuals: settled.setActuals,
            skipped: settled.skipped,
            setsSkipped: settled.setsSkipped,
            probes: settled.probes,
            durationSec: settled.durationSec,
            warmupSec: settled.warmupSec, cooldownSec: settled.cooldownSec,
            interrupted: settled.interrupted,
            raised: settled.raised,
            date: settled.date)
        return true
    }

    /// Called on every phase transition — some 35 times a session.
    /// `refreshWidget: false` is not an optimization but the truth: none of
    /// the widget's states can change while a workout is in progress, and
    /// poking WidgetKit per set would spend the day's reload budget on
    /// identical content.
    func saveWorkoutSnapshot(_ snapshot: WorkoutSnapshot) {
        pendingWorkout = snapshot
        persist(refreshWidget: false)
    }

    /// Widget untouched for the same reason as saveWorkoutSnapshot.
    func clearWorkoutSnapshot() {
        guard pendingWorkout != nil else { return }
        pendingWorkout = nil
        persist(refreshWidget: false)
    }
}
