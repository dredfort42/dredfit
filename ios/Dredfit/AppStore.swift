//
//  Single source of truth: engine state + workout journal.
//  Persistence — one JSON file in Application Support.
//

import Foundation
import Observation
import os
import DredfitCore

struct AppData: Codable {
    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings?
    var pendingWorkout: WorkoutSnapshot?
    // How many journal entries failed to decode (not encoded) — the caller
    // keeps the original file aside when this is nonzero.
    var droppedRecordCount = 0

    init(engineState: EngineState, records: [WorkoutRecord],
         settings: AppSettings?, pendingWorkout: WorkoutSnapshot? = nil) {
        self.engineState = engineState
        self.records = records
        self.settings = settings
        self.pendingWorkout = pendingWorkout
    }

    private enum CodingKeys: String, CodingKey {
        case engineState, records, settings, pendingWorkout
    }

    /// True when the engine state on disk was neither v3 nor v2 (§41.7
    /// migrates v2) and the engine started clean; the loader copies the
    /// original aside, and an import refuses the file.
    var engineStateReset = false

    /// True when a settings block was present but not an object this build
    /// can read. On launch it costs the settings their defaults; an import
    /// refuses the file instead.
    var settingsUnreadable = false

    /// True when a state written before v3 was read and carried over (§41.7).
    /// A property of THIS decode, not of the file: the loader turns it into
    /// `settings.migrationNoticePending`, which is what the file carries and
    /// what the card on Today is spent against.
    var engineStateMigrated = false

    /// The journal decodes record-by-record — one unreadable entry (e.g.
    /// written by a newer version) must not throw away the whole file.
    ///
    /// And the ENGINE STATE decodes leniently for the same reason, since v3:
    /// a state written by an older build carries `levels` instead of positions.
    /// It is now READ and carried over (§41.7); the lenient shape stays because
    /// a state from some future build still must not take the journal and the
    /// settings down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let state = try? c.decode(EngineState.self, forKey: .engineState) {
            engineState = state
        } else if let migrated = try? c.decode(V2EngineState.self, forKey: .engineState),
                  let carried = Engine.migrateFromV2(migrated.asEngineInput) {
            // §41.7: a state written before v3 is READ and carried over, not
            // thrown away. §40.8 used to hand the engine `initState` here; the
            // decision was reversed on 26.08.2026 because the way back it
            // counted on — entering facts — is explained by exactly one line in
            // the app, and that line shows only when the journal is empty.
            // An upgrading trainee's journal is intact, so they never saw it.
            engineState = carried
            engineStateMigrated = true
        } else {
            engineState = .initial
            engineStateReset = true
        }
        // try?, and every field inside it too: one setting of a shape this
        // build does not know must cost that setting, never the journal.
        settings = try? c.decodeIfPresent(AppSettings.self, forKey: .settings)
        settingsUnreadable = settings == nil && c.contains(.settings)
            && !((try? c.decodeNil(forKey: .settings)) ?? false)
        // try?, not try: a snapshot written by a newer version must degrade
        // to "nothing to resume", never to a quarantined journal.
        pendingWorkout = try? c.decodeIfPresent(WorkoutSnapshot.self, forKey: .pendingWorkout)
        var decoded: [WorkoutRecord] = []
        var uc = try c.nestedUnkeyedContainer(forKey: .records)
        while !uc.isAtEnd {
            let index = uc.currentIndex
            if let record = try? uc.decode(WorkoutRecord.self) {
                decoded.append(record)
            } else {
                // Discard's empty init always succeeds, consuming the element.
                _ = try? uc.decode(Discard.self)
                droppedRecordCount += 1
            }
            if uc.currentIndex == index { break }   // safety: never spin in place
        }
        records = decoded
    }

    private struct Discard: Decodable { init(from decoder: Decoder) {} }
}

/// The four things the store persists, as one value a change is made to —
/// see `AppStore.update`.
struct PersistedState {
    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings
    var pendingWorkout: WorkoutSnapshot?

    /// Legacy high-water mark → per-record flags. The mark keeps being
    /// written so a downgraded build still sees a sane value. Runs only on a
    /// journal that carries no flags at all — a pre-flag legacy file. Once
    /// any record is flagged, the flags are the source of truth, and
    /// re-applying the mark could stamp workouts it was never about: a
    /// foreign import's records, or a post-reset session 1 sitting under an
    /// old high mark (issue #103).
    mutating func migrateHealthMarkToFlags() {
        guard settings.healthExportedThrough > 0,
              !records.contains(where: { $0.healthExported != nil }) else { return }
        for i in records.indices
        where records[i].sessionNumber <= settings.healthExportedThrough {
            records[i].healthExported = true
        }
    }
}

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
    /// nobody is holding (self-review 06.09.2026).
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
    /// first unlock, transient I/O). While set, persist() is a no-op: the
    /// file on disk is the only copy of the journal and must never be
    /// overwritten from the empty in-memory state. Everything that publishes
    /// state outward — widget snapshot, backup export — checks this too.
    private(set) var journalFrozen = false
    /// A reload would replace the user's changes with the file's state
    /// silently, and mid-workout it moves the engine counter under a running
    /// session — so a store that has been used stays frozen until relaunch.
    private var mutatedWhileFrozen = false
    var backfillInFlight = false   // guards concurrent Health backfills
    /// Held so tests can await the fire-and-forget path instead of sleeping.
    private(set) var healthExportTask: Task<Void, Never>?
    private(set) var reminderAuthTask: Task<Void, Never>?
    private(set) var bodyMassTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "app.dredfit", category: "store")

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
            // Unlike a decode failure, the journal may be perfectly fine —
            // e.g. still protected before first unlock. Freeze rather than
            // quarantine; reloadIfNeeded() lifts it.
            journalFrozen = true
            Self.log.fault("state file exists but could not be read — persistence frozen")
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

    /// Second chance for a launch whose state file could not be read. Called
    /// when the scene becomes active — i.e. once the device is unlocked.
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

    /// Re-anchors only when the day actually rolled over — mutating `today`
    /// on every activation would re-render for nothing.
    func refreshDay(now: Date = .now) {
        reanchorToday(now: now)
        // The blind-zone decay rides the same pulse, so by the time Today
        // renders the plan is already corrected.
        applySilentDecayIfNeeded(now: now)
    }

    /// The date half of `refreshDay` and nothing else, for a midnight that
    /// passes inside a live scene (a workout's cover keeps it active, so no
    /// activation comes). Never the decay: this fires under a running workout
    /// too, and can land before `activate()`, whose order it must not break.
    func reanchorToday(now: Date = .now) {
        if !Calendar.current.isDate(today, inSameDayAs: now) { today = now }
    }

    /// Everything a scene becoming `.active` must run, in one seam — a cold
    /// launch renders already active without a phase transition, so `onAppear`
    /// has to run the same sequence or the blind-zone decay never fires.
    /// Order matters: the decay can only correct a journal that has loaded.
    func activate(now: Date = .now) {
        reloadIfNeeded()
        // BEFORE the day is re-anchored, never after: the settlement writes a
        // journal entry dated to the day it happened, and the silent decay and
        // the comeback both measure their gap from the last record. Settling
        // afterwards would decay a state that had just been trained.
        settleAbandonedWorkout(now: now)
        refreshDay(now: now)
        rescheduleReminders(now: now)
        // Off the sequence, because it is the only step that leaves the
        // device: a HealthKit query must not hold the plan's re-anchoring
        // behind it. The weight is the owner's, and the owner may have
        // weighed themselves since the last foreground.
        // A share taken back since the last foreground turns the switch off
        // here, before the read below would query Health for nothing.
        reconcileHealthAuthorization()
        if settings.healthEnabled {
            // Cancelled, not just replaced: two foregrounds in a row leave two
            // queries in flight, and HealthKit decides which returns first —
            // without this the older reading could land last and stick.
            bodyMassTask?.cancel()
            bodyMassTask = Task { await self.refreshBodyMassFromHealth() }
        }
    }

    // There is no default time budget, because there is no budget. The audit
    // measured what the rungs actually did: 10, 15 and 20 produced the SAME
    // plan, and the "20" rung missed its own target in 100 % of sessions. The
    // engine now announces how long a session takes and the person shortens it
    // with the handle. What stood here was `defaultTimeBudgetMin` and the
    // argument for it (#136): a length nobody chose was 45 minutes rather than
    // "no limit", because the budget shipped switched off and so protected
    // only the people who went looking for it.

    // MARK: - Derived

    /// IMPORTANT: right after a workout is completed the counter has
    /// advanced, so this is the NEXT workout. Never present it under today's
    /// date — only with nextTrainingDate.
    var nextSession: Session { Engine.generateSession(engineState) }

    /// Conservative on missing data: records without an exercise snapshot
    /// cannot vouch for what was done, so a pattern with no snapshotted
    /// history is never badged — better a missed badge than "new variation"
    /// on an exercise the user has done for weeks.
    var debutPatterns: Set<Pattern> {
        var maxPerformed: [Pattern: Int] = [:]
        for record in records {
            guard let exercises = record.exercises else { continue }
            // A painful exercise was not performed either. A record written by
            // an older build keeps its pain reports, and they were "not
            // performed" exactly as a skip was — so reading history has to
            // count both. Nothing writes `discomfort` any more.
            let skipped = (record.skipped ?? []).union(record.discomfort ?? [])
            for ex in exercises where !skipped.contains(ex.pattern) {
                maxPerformed[ex.pattern] = max(maxPerformed[ex.pattern] ?? 0, ex.variation)
            }
        }
        var debuts: Set<Pattern> = []
        for ex in nextSession.exercises {
            if let seen = maxPerformed[ex.pattern], ex.variation > seen {
                debuts.insert(ex.pattern)
            }
        }
        return debuts
    }

    // `restingPatterns` is gone with the freeze. Nothing rests any more — a
    // movement the person finds too hard stays in the plan and gets an easier
    // variation or fewer sets, which is the whole point of the wave: the
    // channel that removed movements removed them for weeks.

    /// How far along their ladders every movement stands, summed — the scale
    /// §40.2 puts in place of the total level. A clean start reads zero, just
    /// as the old total did.
    var totalProgress: Int { Engine.totalProgress(engineState) }

    /// The position of every movement right now, in the form the journal
    /// records it.
    var currentPositions: [Pattern: RecordedPosition] { Self.positions(of: engineState) }

    static func positions(of state: EngineState) -> [Pattern: RecordedPosition] {
        var out: [Pattern: RecordedPosition] = [:]
        for p in Pattern.allCases {
            let pos = state.position(p)
            out[p] = RecordedPosition(variation: pos.variation, sets: pos.sets, dose: pos.dose,
                                      sub: pos.sub > 0 ? pos.sub : nil,
                                      cut: pos.cut > 0 ? pos.cut : nil)
        }
        return out
    }

    /// Oldest first. `through` cuts it at a date: a milestone card must not
    /// draw a curve running past the event it celebrates. Records written
    /// before v3 carry no point on this scale and are left out rather than
    /// plotted on the wrong one.
    func progressCurve(through date: Date? = nil) -> [Int] {
        let run = recordsSinceReset
        let history = date.map { cut in run.filter { $0.date <= cut } } ?? run
        return history.compactMap(\.totalProgressAfter)
    }

    /// Where the journal starts describing the CURRENT plan. `resetProgress`
    /// restarts the session counter and leaves the journal standing — which is
    /// what `WorkoutRecord.id` already says out loud — so the first record
    /// whose number does not exceed its predecessor's opens the new run.
    ///
    /// The curve is cut here rather than at each caller because the milestone
    /// card and the share card drew the pre-reset PEAK above a plan that had
    /// just been wiped (UX review 05.09.2026, finding 36). Progress cut its own
    /// chart and nothing else did. The workout COUNT still spans the whole
    /// journal: the history really does stay, which is what the reset promises.
    var recordsSinceReset: [WorkoutRecord] {
        let resumed = records.indices.dropFirst().last {
            records[$0].sessionNumber <= records[$0 - 1].sessionNumber
        }
        // The falling pair finds a reset only from the NEXT workout on:
        // `resetProgress` writes no record of its own, it just returns the
        // engine to `.initial` and leaves the journal standing. In the window
        // between the reset and the first workout after it there is no pair to
        // find, so the whole journal came back while `totalProgress` was
        // already 0 — the chart drew the old peak under a headline saying zero
        // (self-review 05.09.2026). The counter moves at the reset itself.
        return records[(resumed ?? records.startIndex)...]
            .filter { $0.sessionNumber <= engineState.counter }
    }

    var lastRecord: WorkoutRecord? { records.last }

    var doneToday: Bool { isDone(on: today) }

    func isDone(on date: Date) -> Bool {
        guard let last = records.last else { return false }
        return Calendar.current.isDate(last.date, inSameDayAs: date)
    }

    func isRestDay(_ date: Date) -> Bool {
        settings.restWeekdays.contains(Calendar.current.component(.weekday, from: date))
    }

    /// The workout completed on the given day, if any (for calendar history).
    func record(on date: Date) -> WorkoutRecord? {
        let cal = Calendar.current
        return records.last { cal.isDate($0.date, inSameDayAs: date) }
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
                         /// What the PROBE set showed, per movement (§40.4).
                         /// Its own argument, never folded into `overrides`:
                         /// the probe is a different exercise, and averaging
                         /// two variations is exactly what §40 forbids.
                         probes: [Pattern: Int] = [:],
                         durationSec: Int? = nil,
                         /// Seconds the guided blocks actually ran; nil when
                         /// the flow did not measure them.
                         warmupSec: Int? = nil, cooldownSec: Int? = nil,
                         /// The movement left half-done, if any. Already
                         /// inside `skipped` for the engine; this names which,
                         /// so the history can tell "not finished" from
                         /// "skipped" (owner, 05.09.2026).
                         interrupted: Pattern? = nil,
                         /// Steps added "for next time" per movement
                         /// (§41.13). Landed by the engine AFTER the rating
                         /// and the skipped sets — the composed entry point
                         /// owns that order, which is why the app never
                         /// applies the raise itself.
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
        // Floored, a second workout on the same day reported a zero gap and
        // the weekly window stopped ageing for good. SEVEN arguments. Every
        // optional is passed explicitly — the wave's rule, kept because the
        // arity shift is exactly the defect that has now happened twice in the
        // harnesses.
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
        // once more without it, and the ordinals compared. On the grid's
        // ceiling the engine parks a raise (§41.13), so the taps and the
        // rise can differ, and the journal names the rise: the taps stay in
        // `raisedSteps` because a changed rating replays them.
        var landed: [Pattern: Int] = [:]
        if !raised.isEmpty {
            let unraised = Engine.applyFeedback(state: before, session: session,
                                                result: result, overrides: overrides,
                                                skipped: skipped,
                                                setsSkipped: setsSkipped,
                                                gapDays: gapFraction(now: date),
                                                probes: probes)
            landed = Self.landed(raised, from: unraised, to: engineState)
        }
        // What it takes to change this rating afterwards, and which movements
        // it actually eased. Both are facts of THIS moment and of no other:
        // the state before the rating cannot be reconstructed from the journal
        // — the silent decay and an accepted comeback move it between entries
        // — and neither can the list the descent landed on (UX review
        // 05.09.2026, findings 25 and 27).
        settings.lastRatingUndo = RatingUndo(state: before, session: session)
        noteRatingLanded(session: session, before: before)
        records.append(WorkoutRecord(
            sessionNumber: session.sessionNumber,
            date: date,
            result: result,
            totalProgressAfter: totalProgress,
            exercises: session.exercises,
            // §41.3: the journal of workouts keeps INTEGERS. The fraction is a
            // judge for the engine, not a fact for a person to read, and the
            // record is persisted — changing its wire type would break every
            // saved file for the sake of a decimal nobody wants to see.
            actuals: overrides.isEmpty ? nil : overrides.mapValues { Int($0.rounded()) },
            setActuals: setActuals.isEmpty ? nil : setActuals,
            // The same argument the engine was already given. It used to stop
            // here: the number reached `applyFeedback` and nothing wrote it
            // down, so what a probe showed was unrecoverable the moment the
            // rating landed.
            probes: probes.isEmpty ? nil : probes,
            setsSkipped: setsSkipped.isEmpty ? nil : setsSkipped,
            skipped: skipped.isEmpty ? nil : skipped,
            positionsAfter: currentPositions,
            durationSec: durationSec,
            warmupSec: warmupSec, cooldownSec: cooldownSec,
            interrupted: interrupted,
            raisedSteps: raised.isEmpty ? nil : raised,
            raisedLanded: raised.isEmpty ? nil : landed))
        persist()
        // A morning workout takes tonight's reminder down with it.
        // NOT `now: date`: the record's date is about the JOURNAL, and
        // `settleAbandonedWorkout` dates a record to the day it happened —
        // yesterday. Reminders look forward, and scheduling them from a
        // past `now` re-opens the very hole the `fire > now` guard exists
        // to close: today's slot, already gone, passes the check against
        // yesterday and sits in the pending list where it can never fire
        // (self-review 05.09.2026).
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
        // this session moves with the rating into the slot History reads. It
        // used to stay in the ONE shared slot, stamped one session below what
        // `noteEasedByHand` asks for: the next tap on "easier" found no match,
        // started a fresh record and erased both lists — the named promise the
        // athlete had just been shown fell back to the generic wording, for
        // good and in silence (review 06.09.2026). `ratingMoves` first so a
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
    /// cannot be credited to this one. What that start-over used to take with
    /// it was the last rating's list, sharing the slot; it has its own now
    /// (`ratingMoves`), so this writes about the plan ahead and nothing else.
    private func noteEasedByHand(_ pattern: Pattern) {
        let session = engineState.counter + 1
        var moves = planMoves(for: session) ?? PlanMoves(session: session)
        if !moves.byHand.contains(pattern) { moves.byHand.append(pattern) }
        settings.planMoves = moves
    }

    // MARK: - The shown plan

    /// The plan is on screen — the engine gets to remember it. Until this call
    /// the "a descent never adds load" guarantee held only BETWEEN COMPLETED
    /// SESSIONS: a plan a person saw and did not train could be beaten by the
    /// next one by up to ×1.47, in 16–22 % of the "showed, skipped a week,
    /// opened again" episodes on budgets of 30–35. That was the last accepted
    /// gap of the wave and this call is the whole of its fix — `recordShown`
    /// has been exported since the port, waiting for a caller.
    ///
    /// ONE WRITE PER SHOWING, not one per render. The guard is the memory
    /// itself: writing down a plan that is already written down changes
    /// nothing, so every render after the first returns without a state
    /// write, a file write or a widget reload. That it settles at all is by
    /// construction — the memory keeps the work of the plan AFTER the
    /// postcondition repair, and the repair only ever trims work STRICTLY
    /// above what was shown, so the second pass has nothing left to trim.
    ///
    /// The one showing deliberately NOT written down is the illness lens.
    /// Its plan is a VIEW: the base has to stay the last ordinary showing, or
    /// coming off the lens reads as a rise and the repair takes sets off
    /// someone who has only just recovered.
    func recordPlanShown(_ session: Session) {
        // A frozen journal is a launch that could not READ the state file —
        // before first unlock, usually. The plan on screen was drawn from an
        // empty state and is worth remembering least of all, and writing it
        // would pin the freeze (`mutatedWhileFrozen`) and cost the trainee
        // their journal for the rest of the launch.
        guard !journalFrozen else { return }
        let recorded = Engine.recordShown(state: engineState, session: session)
        guard recorded != engineState else { return }
        engineState = recorded
        persist()
    }

    // MARK: - Settings

    /// Refuses to turn the last training day into rest: at least one training
    /// day must remain, nextTrainingDate relies on it.
    func toggleRestDay(_ weekday: Int) {
        var days = settings.restWeekdays
        if days.contains(weekday) {
            days.remove(weekday)
        } else {
            days.insert(weekday)
            guard days.count < 7 else { return }
        }
        settings.restWeekdays = days
        persist()
        rescheduleReminders()
    }

    func setSounds(_ on: Bool) {
        settings.soundsEnabled = on
        persist()
    }

    /// Turning it off freezes the vertical branch; its level is kept.
    func setHasBar(_ on: Bool) {
        engineState.hasBar = on
        persist()
    }

    func setReminderEnabled(_ on: Bool) {
        settings.reminderEnabled = on
        persist()
        guard on else { return rescheduleReminders() }
        reminderAuthTask = Task { [weak self] in
            guard let self else { return }
            if await self.reminderScheduler.requestAuthorization() {
                self.rescheduleReminders()
            } else {
                // the system said no — reflect reality in the toggle
                self.settings.reminderEnabled = false
                self.persist()
            }
        }
    }

    func setReminderTime(hour: Int, minute: Int) {
        settings.reminderHour = hour
        settings.reminderMinute = minute
        persist()
        rescheduleReminders()
    }

    // MARK: - Onboarding

    /// Genuinely new installs only.
    var shouldShowOnboarding: Bool {
        // A frozen launch knows nothing about the user — never mistake it
        // for a fresh install.
        !journalFrozen && records.isEmpty && engineState.counter == 0
            && !settings.onboardingCompleted
    }

    /// Deliberately not called when the pager merely appears: an app killed
    /// mid-pager shows it again. Since #101 the only path here is the care
    /// card's explicit button — Skip jumps to that card instead of past it —
    /// so completing also records the acknowledgement.
    func completeOnboarding() {
        settings.onboardingCompleted = true
        settings.careAcknowledgedAt = .now
        persist()
    }

    // MARK: - Comeback after a break

    // gapDays and the training-day anchor live in AppStore+Cadence.

    /// Asked once per break: the answer is stamped against the last workout's
    /// date, so it goes stale by itself instead of needing to be cleared. A
    /// break inside the trainee's own rhythm is not a break at all (#134) — no
    /// card, and so no comeback either.
    func shouldOfferComeback(now: Date? = nil) -> Bool {
        guard let last = records.last, let gap = gapDays(now: now) else { return false }
        guard gap >= EngineConfig.comebackMinGapDays, !isRhythmBreak(gap) else { return false }
        guard let decided = settings.comebackDecidedFor,
              Calendar.current.isDate(decided, inSameDayAs: last.date) else { return true }
        // Once per break — unless the break has since grown a door the answer
        // could not have been about. "Start from scratch" appears only from
        // `comebackFreshStartDays`, so someone who declined on day 20 of a
        // break that ran to three months never saw the one offer meant for
        // exactly them: the threshold was unreachable by anyone who answered
        // early (UX review 05.09.2026, finding 8). At most ONE extra ask —
        // closing the question again stamps the gap it was answered at.
        guard let answeredAt = settings.comebackDecidedAtGap else { return false }
        return answeredAt < Self.comebackFreshStartDays && gap >= Self.comebackFreshStartDays
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

    /// Drives both the once-per-break guard and the comeback's
    /// `alreadyDecayed`: the two drops must not stack. Internal so the
    /// read-only preview in AppStore+Comeback sees the same weakening.
    var silentDecayAppliedForCurrentBreak: Bool {
        guard let applied = settings.silentDecayAppliedFor,
              let last = records.last?.date else { return false }
        return Calendar.current.isDate(applied, inSameDayAs: last)
    }

    func offersFreshStart(now: Date? = nil) -> Bool {
        (gapDays(now: now) ?? 0) >= Self.comebackFreshStartDays
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
    /// the postcondition repair reads — the bypass of `applyFeedback` the audit
    /// counts as a finding. What the handle may do is asked in
    /// AppStore+Handles; what it does is here.
    ///
    /// One handle, singular: the two that moved VOLUME are gone from the
    /// plan, and the volume is decided inside the workout instead.
    /// The `cut` axis they wrote is untouched — `completeWorkout` carries the
    /// sets skipped along the way, and the engine writes them there.

    func makeEasier(_ pattern: Pattern) {
        guard canMakeEasier(pattern) else { return }
        engineState = Engine.easierVariation(state: engineState, pattern: pattern)
        // A step down taken by hand looks exactly like one the engine took,
        // and history explained neither (finding 64). This is the only moment
        // that knows which it was.
        noteEasedByHand(pattern)
        persist()
    }

    func declineComeback(now: Date? = nil) {
        closeComebackQuestion(now: now)
    }

    // `setTimeBudget`, the "what's new" notice about its default, and
    // `markIllness` are all gone. The budget trimmed the WORKOUT to fit a
    // number the person picked once and forgot; the lens made the plan heavier
    // than it was. What answers "how long will this take" now is the announced
    // range, and what shortens a session is the skip on the work screen, taken
    // one set at a time while the workout is running.

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

    private func closeComebackQuestion(now: Date? = nil) {
        settings.comebackDecidedFor = records.last?.date
        // How long the break was when it was answered, so a break that keeps
        // growing can ask once more (see shouldOfferComeback).
        settings.comebackDecidedAtGap = gapDays(now: now)
        // persist() already mirrors to the widget — accepting a comeback moves
        // the levels the plan is drawn from, and it reaches the snapshot on
        // that one write. A second call here is a second reloadAllTimelines()
        // for the same content.
        persist()
    }

    /// From 90 days — a quarter away is long enough that "as it was" can be
    /// blind and "from scratch" must be reachable. Was 180.
    static let comebackFreshStartDays = 90

    // MARK: - App Store review

    /// Pure and injectable so the gate is unit-testable without StoreKit.
    /// A `.less` rating disqualifies the session outright.
    func shouldRequestReview(lastResult: FeedbackResult?, now: Date = .now) -> Bool {
        guard engineState.counter >= Self.reviewMinWorkouts else { return false }
        guard let lastResult, lastResult != .less else { return false }
        guard let previous = settings.lastReviewRequestAt else { return true }
        let days = Calendar.current.dateComponents([.day], from: previous, to: now).day ?? 0
        return days >= Self.reviewMinDaysBetween
    }

    func recordReviewRequest(at date: Date = .now) {
        settings.lastReviewRequestAt = date
        persist()
    }

    static let reviewMinWorkouts = 5
    static let reviewMinDaysBetween = 60

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
        } catch {
            // The next mutation retries the full write, but this is the only
            // durability path — a failure must leave a trace.
            Self.log.fault("persist failed: \(error.localizedDescription)")
        }
        // Except the changes that provably cannot alter what it shows.
        if refreshWidget { refreshWidgetSnapshot() }
    }
}

// MARK: - The weak-link prompt (#135)

/// The mutating half of the prompt lives here: `settings` and `persist` are
/// the store's own, and an extension in another file cannot reach them. The
/// read-only half — who the suspect is, whether to ask — is in
/// `AppStore+Signals`.
extension AppStore {

    /// Records the answer: yes, it is this movement. The engine's contract
    /// keeps pain reports inside a session, so the answer is held and spent on
    /// the next session the movement appears in — exactly what the mid-workout
    /// "Something hurt" button would have done, answered early. The answer
    /// used to be "it hurts", and it queued a pain report for the movement's
    /// next appearance. There is no pain channel, and the honest replacement
    /// is not another diagnosis but the control the person would have wanted
    /// either way: drop this movement to an easier variation, now, and keep it
    /// in the plan.
    ///
    /// It goes through the ENGINE (`easierVariation`), never by writing the
    /// state here: a level written by hand skips the gate that guarantees the
    /// landing is not heavier.
    func makeSuspectEasier(_ pattern: Pattern) {
        settings.weakLinkPromptAnsweredFor = records.last?.sessionNumber
        engineState = Engine.easierVariation(state: engineState, pattern: pattern)
        // The second door of the same event, and it must be attributed the
        // same way (finding 64).
        noteEasedByHand(pattern)
        persist()
    }

    /// The third answer — "it is just hard" — is gone. It armed a hold, and
    /// the hold is cancelled: the case it served (the plan ran ahead of what
    /// the trainee can do) is what the sub-step fixes, and fixes without
    /// asking. The prompt is down to the diagnosis and a dismissal.
    ///
    /// Dismisses the prompt for this session without changing the plan.
    func dismissSuspectPrompt() {
        settings.weakLinkPromptAnsweredFor = records.last?.sessionNumber
        persist()
    }

    /// The one line on Today that says a plan row is a door (R30). It is the
    /// whole price the plan pays for the handle that left it: the variation one
    /// step below now lives behind the technique sheet, and a control nobody
    /// knows about is a control nobody has.
    ///
    /// Gated on having been through the door, never on `records.isEmpty`: the
    /// person carried over from v2 has a full journal and is exactly the person
    /// the sentence is for — every one of their movements sits above the first
    /// variation, so every one of them has a step below it.
    var showsTechniqueHint: Bool { !settings.hasOpenedTechnique }

    /// Spent by the first technique sheet opened from ANY of its three doors —
    /// the plan row, the work screen and the rest screen. `persist` only on the
    /// transition: the sheet is opened many times over a life of the app and
    /// this is a one-way flag.
    func markTechniqueOpened() {
        guard !settings.hasOpenedTechnique else { return }
        settings.hasOpenedTechnique = true
        persist()
    }

    /// The one-shot card on Today explaining what an upgrade did (§41.7).
    var showsMigrationNotice: Bool { settings.migrationNoticePending == true }

    func dismissMigrationNotice() {
        settings.migrationNoticePending = false
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

// The pending pain report is gone. It existed to carry a "yes, it hurts"
// answered on Today into the movement's next appearance; the answer is now
// applied immediately, because an easier variation needs no appearance to wait
// for.

// `--uitest-weak-link` and the journal it seeded are gone. The prompt itself
// stays — `shouldAskAboutSuspect`, `unnamedLessSuspect` and the two buttons on
// Today are all live. What went is the hook: no test ever passed the flag, and
// the flag did not even raise the screen it seeded, so it read as coverage
// while covering nothing.
