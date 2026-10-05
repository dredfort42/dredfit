//
//  The lifecycle of a workout in progress, as the store keeps it: the
//  snapshot the flow writes on every phase transition, and what becomes of it.
//  WorkoutSessionStore holds the windows and decides what a settlement
//  records; the store measures against them and writes the result.
//

import Foundation
import DredfitCore

extension AppStore {

    /// The plan the store hands out for `state`: the one the engine draws —
    /// unless the workout in progress was started on the plan a build without
    /// the pull-cap memory drew, and the update came in the middle of it. That
    /// workout carries on as it was started: its snapshot is keyed on that
    /// plan, and the plan drawn now would hand a frozen push its sets back
    /// between two of them, so the card would vanish and the work done so far
    /// would never be recorded. Once the workout is settled, recorded or
    /// started over, the plan is drawn afresh.
    func session(for state: EngineState) -> Session {
        let drawn = Engine.generateSession(state)
        guard let snap = pendingWorkout,
              WorkoutSessionStore.valid(snap, plan: drawn, counter: state.counter) == nil
        else { return drawn }
        let started = Engine.sessionWithoutTheOneTimeRelease(state)
        return WorkoutSessionStore.valid(snap, plan: started, counter: state.counter) == nil ? drawn : started
    }

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
    /// ASKED rather than answered for: ready to carry on, or keep what is
    /// already done?
    ///
    /// Not recorded unasked when the resume window closes: three hours is a
    /// long lunch, not a lost session, and the plan would come back rated by
    /// nobody.
    ///
    /// The store has no "keep it" of its own on purpose. Answering the card
    /// opens the flow on its RATING screen, so the athlete says how it went
    /// themselves — the only thing recorded on anyone's behalf is a workout
    /// nobody came back to for half a day.
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
    /// Without it a workout that was trained and never rated would vanish
    /// altogether: the flow records a workout only from the tap on a rating
    /// card, so putting the phone down on "How did it go?" and letting iOS
    /// unload the process would erase the whole session, for exactly the
    /// people who train late.
    @discardableResult
    func settleAbandonedWorkout(now: Date = .now) -> Bool {
        // A flow on screen OWNS this snapshot: it will finish the workout
        // itself. Settling underneath it would advance the engine's counter,
        // and the rating the athlete then gave would fail `completeWorkout`'s
        // replay guard and be dropped in silence — the session recorded as
        // "on plan" and the honest answer never reaching the engine. Reachable
        // because `activate()` runs on every foreground and the flow is a
        // cover presented from a screen that stays alive under it.
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
            update { $0.pendingWorkout = nil }
            return false
        }
        // `completeWorkout` clears the snapshot in the same write that records
        // the workout: a write of its own first would leave a moment where
        // the file holds neither.
        let settled = WorkoutSessionStore.settlement(of: snap, in: session)
        completeWorkout(
            session: session,
            // It happened, and the regulator's neutral answer is the honest
            // stand-in for a rating nobody gave.
            result: .plan,
            overrides: settled.overrides,
            setActuals: settled.setActuals,
            skipped: settled.skipped,
            setsSkipped: settled.setsSkipped,
            skippedSets: settled.skippedSets,
            skippedWithNumber: settled.skippedWithNumber,
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
        update(refreshWidget: false) { $0.pendingWorkout = snapshot }
    }

    /// Widget untouched for the same reason as saveWorkoutSnapshot.
    func clearWorkoutSnapshot() {
        guard pendingWorkout != nil else { return }
        update(refreshWidget: false) { $0.pendingWorkout = nil }
    }
}
