//
//  The lifecycle of a workout in progress: the snapshot the flow writes on
//  every phase transition, whether it is still the same training occasion,
//  and what happens to it when it is not.
//
//  Split out of AppStore.swift when that file passed 1140 of the lint's hard
//  1200 (CLAUDE.md: split rather than grow). These four members mutate, so
//  they sit apart from the read-only extensions — the snapshot's whole
//  lifecycle is easier to check in one place than buried in the main file.
//

import Foundation
import DredfitCore

extension AppStore {

    /// Older than this is a different training occasion, not an interrupted
    /// one — but "not the same occasion" is not the same as "abandoned", and
    /// the two used to be one window (owner, 06.09.2026).
    static let workoutResumeWindow: TimeInterval = 3 * 60 * 60

    /// Past this the workout was not interrupted, it was FORGOTTEN, and only
    /// then is it recorded without being asked about (owner, 06.09.2026).
    ///
    /// Elapsed time, not the calendar day `trainingDays` counts. That rule is
    /// right about rhythm — midnights are what "yesterday" means to a person —
    /// and wrong here: a session left at 23:30 and opened at 00:30 is one
    /// midnight and one hour, and recording it unasked after an hour is the
    /// very thing this threshold exists to prevent.
    ///
    /// Twelve hours, so a session and the next opening of the app fall on
    /// opposite sides of a night or a working day: an evening workout left at
    /// 21:00 is still a question the next morning, and one left in the morning
    /// stops being one by the evening.
    static let workoutForgottenAfter: TimeInterval = 12 * 60 * 60

    /// The snapshot is only worth anything while it still describes the plan
    /// the engine would hand out: the bar toggle and an accepted comeback
    /// regenerate a different session under the same number, and then its
    /// indices and numbers belong to a plan nobody trained.
    private func validPendingWorkout() -> (snapshot: WorkoutSnapshot, session: Session)? {
        let session = nextSession
        guard let snap = pendingWorkout,
              snap.sessionNumber == engineState.counter + 1,
              snap.fingerprint == WorkoutSnapshot.fingerprint(of: session),
              snap.hasProgress
        else { return nil }
        return (snap, session)
    }

    /// Fresh enough to be the same occasion, and nothing completed today.
    func resumableWorkout(now: Date = .now) -> WorkoutSnapshot? {
        guard let snap = validPendingWorkout()?.snapshot, !doneToday,
              now.timeIntervalSince(snap.savedAt) < Self.workoutResumeWindow
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
        guard age >= Self.workoutResumeWindow, age < Self.workoutForgottenAfter else { return nil }
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
              now.timeIntervalSince(snap.savedAt) >= Self.workoutForgottenAfter
        else { return false }
        return settlePendingWorkout(now: now)
    }

    /// Writes what was done and clears the snapshot either way: a snapshot
    /// that can no longer be recorded honestly must not linger to be asked
    /// about again tomorrow.
    ///
    /// Recorded "on plan" — it happened, and the regulator's neutral answer is
    /// the honest stand-in for one nobody gave (owner, 05.09.2026). Dated from
    /// `workoutStart`, never `.now`: settling yesterday's session this morning
    /// would otherwise move it into today's calendar, today's Health export
    /// and today's gap arithmetic.
    @discardableResult
    private func settlePendingWorkout(now: Date) -> Bool {
        guard pendingWorkout != nil else { return false }
        guard let (snap, session) = validPendingWorkout() else {
            pendingWorkout = nil
            persist()
            return false
        }
        pendingWorkout = nil

        let settled = SetFacts.settlement(
            in: session.exercises,
            exIndex: snap.exIndex,
            // In rest the set that just ended is still `setIndex`.
            setsBehind: snap.restEndDate != nil ? snap.setIndex + 1 : snap.setIndex,
            currentIsDone: snap.atFeedback == true || snap.atExerciseSummary == true,
            alreadySkipped: snap.skips)
        let skipped = settled.skipped.union(snap.skipped)
        var facts = snap.facts
        var probes = snap.probeFacts
        // A skip wins over an actual, the same way it does in the flow.
        for pattern in skipped {
            facts.removeValue(forKey: pattern)
            probes.removeValue(forKey: pattern)
        }
        completeWorkout(
            session: session,
            result: .plan,
            overrides: SetFacts.overrides(facts, in: session.exercises),
            setActuals: facts,
            skipped: skipped,
            setsSkipped: settled.setsSkipped,
            probes: probes,
            // Minus the measured absence, exactly as the flow's own path does
            // it: without this the same break was charged to the workout or
            // not depending only on whether the process survived to the rating
            // tap — the very circumstance this wave removed.
            durationSec: max(0, Int(snap.savedAt.timeIntervalSince(snap.workoutStart))
                                - (snap.awaySec ?? 0)),
            warmupSec: snap.warmupSec, cooldownSec: snap.cooldownSec,
            interrupted: snap.interrupted ?? settled.interrupted,
            // Decided on the summaries of movements that are behind; a
            // movement the settlement skips cannot carry one — the summary
            // is the last set's screen, and a skipped movement never got
            // there.
            raised: snap.raises.filter { !skipped.contains($0.key) },
            date: snap.workoutStart)
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
