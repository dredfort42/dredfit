//
//  Single source of truth: engine state + workout journal.
//  Persistence — one JSON file in Application Support.
//

import Foundation
import Observation
import os
import DredfitCore

@Observable
final class AppStore {

    // Set only in this file: from anywhere else a change goes through
    // `update`, which writes it in the same call — or, in DEBUG, through the
    // UI-test `seed`, which does not write.
    private(set) var engineState: EngineState = .initial
    private(set) var records: [WorkoutRecord] = []
    private(set) var settings = AppSettings()
    /// Read through `resumableWorkout`, which applies the validity checks.
    private(set) var pendingWorkout: WorkoutSnapshot?

    /// Whether the workout flow is on screen RIGHT NOW, in this process.
    ///
    /// Not persisted and deliberately so: after a process death nothing owns
    /// the snapshot any more, which is exactly when the settlement should run.
    /// Its only reader is `settleAbandonedWorkout` — `activate()` fires on
    /// every foreground, including one that lands straight back INTO a running
    /// workout, and the store cannot otherwise tell that case from a session
    /// nobody is holding.
    private(set) var workoutIsOnScreen = false

    func workoutFlowAppeared() { workoutIsOnScreen = true }
    func workoutFlowDisappeared() { workoutIsOnScreen = false }

    /// Views derive "today" from this rather than `Date.now`, so crossing
    /// midnight while suspended invalidates them: mutating it is what
    /// re-renders every date-derived view.
    private(set) var today: Date = .now

    private let stateFile: StateFile
    let health: WorkoutHealthWriting
    let notifications: NotificationScheduling
    let widgetSnapshotURL: URL?
    /// The state file existed but could not be read (data protection before
    /// first unlock, transient I/O), or was read and could not be put aside
    /// before a write would replace it. While set, persist() is a no-op: the
    /// file on disk is the only copy of the journal and must never be
    /// overwritten from the empty in-memory state. Everything that publishes
    /// state outward — widget snapshot, backup export — checks this too.
    private(set) var journalFrozen = false
    /// A reload would replace the user's changes with the file's state
    /// silently, and mid-workout it moves the engine counter under a running
    /// session — so a store that has been used stays frozen until relaunch.
    private var mutatedWhileFrozen = false
    /// Why the last write failed, until a write succeeds. The change itself
    /// stays in memory and the last file stays as it was, so this is the only
    /// sign that changes since the last save are at risk. (A frozen launch
    /// keeps its changes in memory too, with this nil: it has its own card.)
    /// The banner reads it and `activate()` retries on it.
    private(set) var lastPersistError: (any Error)?
    var backfillInFlight = false   // guards concurrent Health backfills
    /// Held so tests can await the fire-and-forget path instead of sleeping.
    private(set) var healthExportTask: Task<Void, Never>?
    /// Internal setters: they are set by `setReminderEnabled` and `activate`,
    /// which live in AppStore+SettingsWrites and AppStore+Activation.
    var reminderAuthTask: Task<Void, Never>?
    var bodyMassTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "app.dredfit", category: "store")

    /// Nonisolated for the reason `WorkoutSession`'s deinit gives: the store
    /// is the class whose isolated deinit crashed on the iOS 26.2 simulator.
    /// The app keeps one store for its whole life, but every unit test frees
    /// one. Nothing here needs the main actor to be torn down.
    nonisolated deinit {}

    init(storageURL: URL = StateFile.defaultURL,
         health: WorkoutHealthWriting = HealthKitWorkoutWriter(),
         notifications: NotificationScheduling = UserNotificationScheduler(),
         widgetSnapshotURL: URL? = SharedStorage.snapshotURL) {
        stateFile = StateFile(url: storageURL)
        self.health = health
        self.notifications = notifications
        self.widgetSnapshotURL = widgetSnapshotURL
        #if DEBUG
        // DEBUG-only: a release binary launched with --uitest-reset must
        // never be able to wipe a user's journal.
        if CommandLine.arguments.contains("--uitest-reset") {
            try? FileManager.default.removeItem(at: storageURL)
        }
        #endif
        switch stateFile.read(reload: false) {
        case .absent, .undecodable:
            adopt(nil)
        case .unreadable:
            // The journal may be perfectly fine — still protected before the
            // first unlock — or damaged with nowhere to put a copy. Either
            // way the file is the only copy: freeze rather than start over on
            // top of it; reloadIfNeeded() lifts it.
            journalFrozen = true
            Self.log.fault("state file could not be read or put aside — persistence frozen")
            adopt(nil)
        case .loaded(let data):
            adopt(data)
            if data.engineStateMigrated {
                Self.log.notice("engine state migrated from v2 — journal, bar and counter carried over")
            }
        }
        #if DEBUG
        applyUITestHooks()
        #endif
        refreshWidgetSnapshot()   // the widget mirrors state from launch
    }

    /// Second chance for a launch whose state file could not be read or put
    /// aside. Called when the scene becomes active — i.e. once the device is
    /// unlocked.
    func reloadIfNeeded() {
        // Reloading over work already done would erase it silently, and
        // mid-workout would move the engine counter out from under a running
        // session. Such a launch stays frozen; the file is untouched.
        guard journalFrozen, !mutatedWhileFrozen else { return }
        switch stateFile.read(reload: true) {
        case .absent, .unreadable:
            return
        case .undecodable:
            break
        case .loaded(let data):
            adopt(data)
        }
        journalFrozen = false
        refreshWidgetSnapshot()
        // Left alone while frozen — rebuild now that the real settings and
        // journal are here.
        rescheduleReminders()
    }

    /// What a read hands the store, at launch and on a reload alike — one
    /// path, so the two cannot drift apart.
    private func adopt(_ data: AppData?) {
        var state = PersistedState(engineState: data?.engineState ?? .initial,
                                   records: data?.records ?? [],
                                   settings: data?.settings ?? AppSettings(),
                                   pendingWorkout: data?.pendingWorkout)
        // Stamped after the settings are in hand, because that is what carries
        // it: the card must survive a launch that ends before anyone reads it,
        // and a frozen launch is exactly the one that must not swallow it.
        if data?.engineStateMigrated == true { state.settings.migrationNoticePending = true }
        state.migrateHealthMarkToFlags()
        assign(state)
    }

    /// The date half of `refreshDay` and nothing else, for a midnight that
    /// passes inside a live scene (a workout's cover keeps it active, so no
    /// activation comes). Never the decay: this fires under a running workout
    /// too, and can land before `activate()`, whose order it must not break.
    func reanchorToday(now: Date = .now) {
        if !Calendar.current.isDate(today, inSameDayAs: now) { today = now }
    }

    // MARK: - The only mutation

    /// - Returns: the milestones this workout earned — derived here because
    ///   this is the only place still holding the pre-feedback state.
    @discardableResult
    func completeWorkout(session: Session,
                         result: FeedbackResult,
                         overrides: [Pattern: Double] = [:],
                         /// The sets behind each override, for the journal.
                         /// The engine never sees them — `overrides` already
                         /// is their mean (`SetFacts.override`).
                         setActuals: SetFacts.PerSet = [:],
                         skipped: Set<Pattern> = [],
                         /// Sets skipped DURING the session, per movement.
                         /// Handed over as what happened — the engine settles
                         /// when it lands, and it lands AFTER the rating.
                         setsSkipped: SetFacts.Skips = [:],
                         /// The ones among those the person skipped, for the
                         /// journal: the fold in `overrides` already left them
                         /// out.
                         skippedSets: SetFacts.SkippedSets = [:],
                         /// The ones among those that keep the number the
                         /// person entered for them, for the journal.
                         skippedWithNumber: SetFacts.SkippedSets = [:],
                         /// What the PROBE set showed, per movement. Its own
                         /// argument, never folded into `overrides`: the probe
                         /// is a different exercise, and an average of two
                         /// variations measures neither of them.
                         probes: [Pattern: Int] = [:],
                         durationSec: Int? = nil,
                         /// Seconds the guided blocks actually ran; nil when
                         /// the flow did not measure them.
                         warmupSec: Int? = nil, cooldownSec: Int? = nil,
                         /// The movement left half-done, if any. Already
                         /// inside `skipped` for the engine; this names which,
                         /// so the history can tell "not finished" from
                         /// "skipped".
                         interrupted: Pattern? = nil,
                         /// Steps added "for next time" per movement. Landed
                         /// by the engine AFTER the rating and the skipped
                         /// sets — the composed entry point owns that order,
                         /// which is why the app never applies the raise
                         /// itself.
                         raised: [Pattern: Int] = [:],
                         date: Date = .now) -> [Milestone] {
        // Mirror of the engine's replay guard: a session that does not belong
        // to this state must not append a duplicate journal entry either.
        guard session.sessionNumber == engineState.counter + 1 else { return [] }
        pendingWorkout = nil   // the workout is over — nothing to resume
        let before = engineState
        // The app hands the engine the one aggregate it needs to stop daily
        // training from multiplying its way around the per-session growth caps
        // — the gap since the last workout. Nil on the first workout: there is
        // nothing to measure from. The FRACTION of a day, not whole days.
        // Floored, a second workout on the same day would report a zero gap
        // and the weekly window would stop ageing for good. Every optional is
        // passed explicitly, so none can fall back to its default unnoticed.
        //
        // The overload that takes the skipped sets is the ONE that settles
        // their order against the rating: the app cannot write them itself,
        // before or after, and this call is why. A cut written before the
        // feedback is eaten by `riseBy` handing a set back, and the skip
        // disappears in silence.
        engineState = Engine.applyFeedback(state: engineState, session: session,
                                           result: result, overrides: overrides,
                                           skipped: skipped,
                                           setsSkipped: setsSkipped,
                                           gapDays: gapFraction(now: date),
                                           probes: probes,
                                           raised: raised)
        // The share of the raise that MOVED the position — the same call
        // once more without it, and the raise replayed over that state one
        // step at a time (`landed`). On the grid's ceiling the engine parks a
        // raise, so the taps and the rise can differ, and the journal names
        // the rise: the taps stay in `raisedSteps` because a changed rating
        // replays them.
        var landed: [Pattern: Int] = [:]
        if !raised.isEmpty {
            let unraised = Engine.applyFeedback(state: before, session: session,
                                                result: result, overrides: overrides,
                                                skipped: skipped,
                                                setsSkipped: setsSkipped,
                                                gapDays: gapFraction(now: date),
                                                probes: probes)
            landed = Self.landed(raised, from: unraised)
        }
        // What it takes to change this rating afterwards, and which movements
        // it actually eased. Both are facts of THIS moment and of no other:
        // the state before the rating cannot be reconstructed from the journal
        // — the silent decay and an accepted comeback move it between entries
        // — and neither can the list the descent landed on.
        settings.lastRatingUndo = RatingUndo(state: before, session: session)
        noteRatingLanded(session: session, before: before)
        records.append(WorkoutRecord(
            sessionNumber: session.sessionNumber,
            date: date,
            result: result,
            totalProgressAfter: totalProgress,
            exercises: session.exercises,
            // The journal of workouts keeps INTEGERS. The fraction is a
            // judge for the engine, not a fact for a person to read, and the
            // record is persisted — changing its wire type would break every
            // saved file for the sake of a decimal nobody wants to see.
            actuals: overrides.isEmpty ? nil : overrides.mapValues { Int($0.rounded()) },
            setActuals: setActuals.isEmpty ? nil : setActuals,
            // The same argument the engine was given. Written down here, or
            // what a probe showed is unrecoverable the moment the rating
            // lands.
            probes: probes.isEmpty ? nil : probes,
            setsSkipped: setsSkipped.isEmpty ? nil : setsSkipped,
            skippedSetIndices: SetFacts.stored(skippedSets),
            skippedWithNumberIndices: SetFacts.stored(skippedWithNumber),
            skipped: skipped.isEmpty ? nil : skipped,
            positionsAfter: currentPositions,
            durationSec: durationSec,
            warmupSec: warmupSec, cooldownSec: cooldownSec,
            interrupted: interrupted,
            raisedSteps: raised.isEmpty ? nil : raised,
            raisedLanded: raised.isEmpty ? nil : landed))
        // Which push cards the pulls held back, read off `before`: only this
        // moment still holds the position each card was cut from.
        records[records.count - 1].heldBack = Self.pushesHeldBack(in: session, builtFrom: before)
        persist()
        // A morning workout takes tonight's reminder down with it.
        // NOT `now: date`: the record's date is about the JOURNAL, and
        // `settleAbandonedWorkout` dates a record to the day it happened —
        // yesterday. Reminders look forward, and scheduling them from a
        // past `now` re-opens the very hole the `fire > now` guard exists
        // to close: today's slot, already gone, passes the check against
        // yesterday and sits in the pending list where it can never fire.
        rescheduleReminders()
        if settings.healthEnabled {
            // Same contiguous path as the manual backfill: an older failed
            // export retries first, so a success cannot leapfrog a hole.
            healthExportTask = Task { await self.backfillHealth() }
        }
        return MilestoneDetector.detect(before: before, after: engineState,
                                        session: session,
                                        skipped: skipped)
    }

    /// Which movements of the session the rating actually made easier, by the
    /// engine's own ordinal before and after — never by re-deriving the rule
    /// here. It answers "who was that for?" on the screen that follows a
    /// "tough", where the plan is otherwise silent about where the tap landed.
    private func noteRatingLanded(session: Session, before: EngineState) {
        let eased = session.exercises.map(\.pattern).filter {
            Engine.progress(engineState, $0) < Engine.progress(before, $0)
        }
        // The plan ahead has become the plan behind, so the hand's list for
        // this session moves with the rating into the slot History reads: from
        // here on `planMoves` belongs to the next plan, and its next "easier"
        // starts that slot over (`noteEasedByHand`). `ratingMoves` first so a
        // rating changed by `changeLastRating` re-enters on its own record.
        var moves = ratingMoves(for: session.sessionNumber)
            ?? planMoves(for: session.sessionNumber)
            ?? PlanMoves(session: session.sessionNumber)
        moves.byRating = eased
        settings.ratingMoves = moves
        // Leave the handle's slot empty rather than stale: it names the plan
        // AHEAD, and that is now a session this record knows nothing about.
        if settings.planMoves?.session == session.sessionNumber { settings.planMoves = nil }
    }

    /// The plan a handle moves is the one AHEAD — `counter + 1` — and stays
    /// that until it is rated. A tap against an older stamp starts the list
    /// over rather than adding to it, so a movement eased two sessions ago
    /// cannot be credited to this one. The last rating's list has a slot of
    /// its own (`ratingMoves`), so the start-over takes nothing else with it:
    /// this writes about the plan ahead and nothing else.
    private func noteEasedByHand(_ pattern: Pattern) {
        let session = engineState.counter + 1
        var moves = planMoves(for: session) ?? PlanMoves(session: session)
        if !moves.byHand.contains(pattern) { moves.byHand.append(pattern) }
        settings.planMoves = moves
    }

    // MARK: - The shown plan

    /// The plan is on screen — the engine gets to remember it. Without this
    /// call the "a descent never adds load" guarantee would hold only BETWEEN
    /// COMPLETED SESSIONS: a plan a person saw and did not train could be
    /// beaten by the next one.
    ///
    /// ONE WRITE PER SHOWING, not one per render. The guard is the memory
    /// itself: writing down a plan that is already written down changes
    /// nothing, so every render after the first returns without a state
    /// write, a file write or a widget reload. That it settles at all is by
    /// construction — the memory keeps the work of the plan AFTER the
    /// postcondition repair, and the repair only ever trims work STRICTLY
    /// above what was shown, so the second pass has nothing left to trim; the
    /// same write remembers a push's pull cap, so it has no rise of the cap to
    /// hand back either.
    ///
    /// Besides a frozen journal's, the one showing deliberately NOT written
    /// down is a plan held for a workout in progress across an update
    /// (`session(for:)`), so only the plan drawn now is: the build before wrote
    /// the held one down, and writing it again would spend the release a push
    /// without the cap memory is owed.
    func recordPlanShown(_ session: Session) {
        // A frozen journal is a launch that could not READ the state file —
        // before first unlock, usually. The plan on screen was drawn from an
        // empty state and is worth remembering least of all, and writing it
        // would pin the freeze (`mutatedWhileFrozen`) and cost the trainee
        // their journal for the rest of the launch.
        guard !journalFrozen, session == Engine.generateSession(engineState) else { return }
        let recorded = Engine.recordShown(state: engineState, session: session)
        guard recorded != engineState else { return }
        engineState = recorded
        persist()
    }

    // MARK: - Settings

    /// Turning it off freezes the vertical branch; its level is kept.
    func setHasBar(_ on: Bool) {
        engineState.hasBar = on
        persist()
    }

    // MARK: - Silent decay for the 7–13 day blind zone (issue #37)

    /// Quiet −1 to every pattern in the 7–13 day gap the comeback does not
    /// reach. Applied at most once per break — the stamp is keyed to the last
    /// workout's date and goes stale by itself, like the comeback answer. A
    /// rhythm break leaves no stamp on purpose: the decision is re-evaluated
    /// on every open, so the same break can still decay later if its gap
    /// outgrows the rhythm — and non-stacking stays exact.
    func applySilentDecayIfNeeded(now: Date? = nil) {
        guard let last = records.last, let gap = gapDays(now: now) else { return }
        guard gap >= EngineConfig.silentDecayGapDays,
              gap < EngineConfig.comebackMinGapDays, !isRhythmBreak(gap) else { return }
        guard !silentDecayAppliedForCurrentBreak else { return }
        engineState = Engine.applySilentDecay(state: engineState, gapDays: gap)
        settings.silentDecayAppliedFor = last.date
        persist()
    }

    /// Nothing is written to the journal — the next record's levelsAfter
    /// snapshot shows the step down on its own.
    ///
    /// Guarded (#128): `Engine.applyComeback` is documented "at most once per
    /// break", and deepens repeated returns via `returnRun` — so card
    /// visibility must not be the only gate. A double tap re-enters with the
    /// question already closed and leaves silently, mirroring the silent-decay
    /// guard.
    func acceptComeback(now: Date? = nil) {
        guard shouldOfferComeback(now: now) else { return }
        guard let gap = gapDays(now: now) else { return }
        engineState = Engine.applyComeback(state: engineState, gapDays: gap,
                                           alreadyDecayed: silentDecayAppliedForCurrentBreak)
        closeComebackQuestion(now: now)
    }

    // MARK: - The handles

    /// The handle goes through the ENGINE. Writing a level or a cut into the
    /// state here would skip the floor, the sanitizer and the position measure
    /// the postcondition repair reads. What the handle may do is asked in
    /// AppStore+Handles; what it does is here.
    ///
    /// One handle, singular: the volume is decided inside the workout, not on
    /// the plan — `completeWorkout` carries the sets skipped along the way,
    /// and the engine writes them into the `cut` axis there.

    func makeEasier(_ pattern: Pattern) {
        guard canMakeEasier(pattern) else { return }
        engineState = Engine.easierVariation(state: engineState, pattern: pattern)
        // A step down taken by hand looks exactly like one the engine took,
        // and this is the only moment that knows which it was — so it is
        // noted here, for History to tell the two apart.
        noteEasedByHand(pattern)
        persist()
    }

    /// Only the engine resets; the journal and settings survive. `hasBar` is
    /// kept — the bar did not disappear from the doorway. The fields of the
    /// sets handle — the cut, the hold and the shown-plan pair — are exactly
    /// what a reset is FOR, and `.initial` zeroes all of them with no line of
    /// their own.
    func resetProgress() {
        let hadBar = engineState.hasBar
        engineState = .initial
        engineState.hasBar = hadBar
        // Session numbers restart: a pre-reset snapshot would collide with
        // the new counter and resume into the wrong workout. The rating undo
        // goes for a stronger reason — it holds a whole PRE-RESET state, and
        // taking a rating back would quietly restore the plan that was wiped.
        pendingWorkout = nil
        settings.lastRatingUndo = nil
        settings.planMoves = nil
        settings.ratingMoves = nil
        closeComebackQuestion()
    }

    // MARK: - Persistence

    /// The way into the persisted state from outside this file: the change
    /// and its write are one call, so no caller can make the one without the
    /// other. (`seed` below is the DEBUG-only exception.)
    func update(refreshWidget: Bool = true, _ change: (inout PersistedState) -> Void) {
        var state = persisted
        change(&state)
        assign(state)
        persist(refreshWidget: refreshWidget)
    }

    #if DEBUG
    /// The UI-test seeds: state set up in memory, as a launch would have read
    /// it, and written with the first real change.
    func seed(_ change: (inout PersistedState) -> Void) {
        var state = persisted
        change(&state)
        assign(state)
    }
    #endif

    private var persisted: PersistedState {
        PersistedState(engineState: engineState, records: records,
                       settings: settings, pendingWorkout: pendingWorkout)
    }

    private func assign(_ state: PersistedState) {
        engineState = state.engineState
        records = state.records
        settings = state.settings
        pendingWorkout = state.pendingWorkout
    }

    private func persist(refreshWidget: Bool = true) {
        // A journal that could not be read must never be overwritten by the
        // empty state that replaced it. The change stays in memory for this
        // launch and pins the freeze, so a later reload cannot swap it out.
        guard !journalFrozen else {
            if !mutatedWhileFrozen {
                mutatedWhileFrozen = true
                Self.log.error("state changed while the journal is frozen — kept in memory only")
            }
            return
        }
        let data = AppData(engineState: engineState, records: records,
                           settings: settings, pendingWorkout: pendingWorkout)
        do {
            try stateFile.write(data)
            lastPersistError = nil
        } catch {
            // The next mutation retries the full write, but this is the only
            // durability path — a failure must leave a trace.
            Self.log.fault("persist failed: \(error.localizedDescription)")
            lastPersistError = error
        }
        // Except the changes that provably cannot alter what it shows.
        if refreshWidget { refreshWidgetSnapshot() }
    }
}

// MARK: - The weak-link prompt (#135)

/// The half of the prompt that moves the engine lives here: `engineState` and
/// `persist` are the store's own, and an extension in another file cannot
/// reach them. The read-only half — who the suspect is, whether to ask — is in
/// `AppStore+Signals`; a dismissal writes only the settings and is in
/// `AppStore+SettingsWrites`.
extension AppStore {

    /// Records the answer — yes, it is this movement — and acts on it at once
    /// with the control the person would want either way: the movement drops
    /// to an easier variation and stays in the plan.
    ///
    /// It goes through the ENGINE (`easierVariation`), never by writing the
    /// state here: a level written by hand skips the gate that guarantees the
    /// landing is not heavier.
    func makeSuspectEasier(_ pattern: Pattern) {
        settings.weakLinkPromptAnsweredFor = records.last?.sessionNumber
        engineState = Engine.easierVariation(state: engineState, pattern: pattern)
        // The second door of the same event, and it must be attributed the
        // same way.
        noteEasedByHand(pattern)
        persist()
    }
}

// MARK: - Taking a rating back

// Whether it can be taken back is AppStore+Rating's.
extension AppStore {

    /// - Returns: the milestones the NEW rating earns, exactly as the first
    ///   tap would have. Empty when there is nothing to change.
    @discardableResult
    func changeLastRating(to result: FeedbackResult) -> [Milestone] {
        guard let redo = ratingRedo(), redo.record.result != result else { return [] }
        // A clean rollback, nothing carried across. The one thing the engine
        // wrote after the rating is the shown-plan memory of the NEXT plan
        // (`recordPlanShown` → `shownWork`/`shownOrd`, and a push's pull-cap
        // memory with them), and `applyFeedback` rewrites all of it for every
        // movement of the session it settles — so re-applying reproduces the
        // post-rating state exactly, and the next render of Today, which is the
        // screen this button is on, writes the new plan's memory back. Carrying
        // the later memory over instead would describe a plan that no longer
        // exists.
        engineState = redo.undo.state
        records.removeLast()
        let facts = redo.record.setActuals ?? [:]
        let milestones = completeWorkout(
            session: redo.undo.session,
            result: result,
            overrides: SetFacts.overrides(facts, skipping: redo.record.leftOutSets,
                                          in: redo.undo.session.exercises),
            setActuals: facts,
            skipped: redo.record.skipped ?? [],
            setsSkipped: redo.record.setsSkipped ?? [:],
            skippedSets: redo.record.skippedSets,
            skippedWithNumber: redo.record.skippedWithNumber,
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
