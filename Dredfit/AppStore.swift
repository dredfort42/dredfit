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

    /// The journal decodes record-by-record — one unreadable entry (e.g.
    /// written by a newer version) must not throw away the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engineState = try c.decode(EngineState.self, forKey: .engineState)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings)
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

@Observable
final class AppStore {

    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings
    /// Read through `resumableWorkout`, which applies the validity checks.
    var pendingWorkout: WorkoutSnapshot?

    /// Views derive "today" from this rather than `Date.now`, so crossing
    /// midnight while suspended invalidates them: mutating it is what
    /// re-renders every date-derived view.
    private(set) var today: Date = .now

    private let storageURL: URL
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

    private static let log = Logger(subsystem: "app.dredfit", category: "store")

    init(storageURL: URL = AppStore.defaultFileURL,
         health: WorkoutHealthWriting = HealthKitWorkoutWriter(),
         notifications: NotificationScheduling = UserNotificationScheduler(),
         widgetSnapshotURL: URL? = SharedStorage.snapshotURL) {
        self.storageURL = storageURL
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
        var loaded: AppData?
        if let data = try? Data(contentsOf: storageURL) {
            do {
                loaded = try JSONDecoder().decode(AppData.self, from: data)
            } catch {
                // Moved aside, not left in place: the next persist() would
                // overwrite the only copy of the journal.
                Self.quarantineStateFile(at: storageURL, keepOriginal: false)
                Self.log.fault("state file failed to decode, moved aside: \(error.localizedDescription)")
            }
        } else if FileManager.default.fileExists(atPath: storageURL.path) {
            // Unlike a decode failure, the journal may be perfectly fine —
            // e.g. still protected before first unlock. Freeze rather than
            // quarantine; reloadIfNeeded() lifts it.
            journalFrozen = true
            Self.log.fault("state file exists but could not be read — persistence frozen")
        }
        engineState = loaded?.engineState ?? .initial
        records = loaded?.records ?? []
        settings = loaded?.settings ?? AppSettings()
        pendingWorkout = loaded?.pendingWorkout
        if let dropped = loaded?.droppedRecordCount, dropped > 0 {
            // Keep the full original before the next persist() rewrites the
            // file without the unreadable entries.
            Self.quarantineStateFile(at: storageURL, keepOriginal: true)
            Self.log.error("dropped \(dropped) unreadable record(s), original kept aside")
        }
        migrateHealthMarkToFlags()
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
        guard journalFrozen, !mutatedWhileFrozen,
              let data = try? Data(contentsOf: storageURL) else { return }
        journalFrozen = false
        do {
            let loaded = try JSONDecoder().decode(AppData.self, from: data)
            engineState = loaded.engineState
            records = loaded.records
            settings = loaded.settings ?? AppSettings()
            pendingWorkout = loaded.pendingWorkout
            if loaded.droppedRecordCount > 0 {
                Self.quarantineStateFile(at: storageURL, keepOriginal: true)
                Self.log.error("dropped \(loaded.droppedRecordCount) unreadable record(s) on reload, original kept aside")
            }
            migrateHealthMarkToFlags()
        } catch {
            Self.quarantineStateFile(at: storageURL, keepOriginal: false)
            Self.log.fault("state file failed to decode on reload, moved aside: \(error.localizedDescription)")
        }
        refreshWidgetSnapshot()
        // Left alone while frozen — rebuild now that the real settings and
        // journal are here.
        rescheduleReminders()
    }

    /// Re-anchors only when the day actually rolled over — mutating `today`
    /// on every activation would re-render for nothing.
    func refreshDay(now: Date = .now) {
        if !Calendar.current.isDate(today, inSameDayAs: now) { today = now }
        // The blind-zone decay rides the same pulse, so by the time Today
        // renders the plan is already corrected.
        applySilentDecayIfNeeded(now: now)
    }

    /// Everything a scene becoming `.active` must run, in one seam — a cold
    /// launch renders already active without a phase transition, so `onAppear`
    /// has to run the same sequence or the blind-zone decay never fires.
    /// Order matters: the decay can only correct a journal that has loaded.
    func activate(now: Date = .now) {
        reloadIfNeeded()
        refreshDay(now: now)
        rescheduleReminders(now: now)
    }

    /// Moves (or copies, when the readable part is kept) the state file to
    /// `<name>.corrupt.json` so decode failures never cost the journal.
    private static func quarantineStateFile(at url: URL, keepOriginal: Bool) {
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".corrupt.json")
        try? FileManager.default.removeItem(at: dest)
        if keepOriginal {
            try? FileManager.default.copyItem(at: url, to: dest)
        } else {
            try? FileManager.default.moveItem(at: url, to: dest)
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

    /// Legacy high-water mark → per-record flags. The mark keeps being
    /// written so a downgraded build still sees a sane value. Runs only on a
    /// journal that carries no flags at all — a pre-flag legacy file. Once
    /// any record is flagged, the flags are the source of truth, and
    /// re-applying the mark could stamp workouts it was never about: a
    /// foreign import's records, or a post-reset session 1 sitting under an
    /// old high mark (issue #103).
    func migrateHealthMarkToFlags() {
        guard settings.healthExportedThrough > 0,
              !records.contains(where: { $0.healthExported != nil }) else { return }
        for i in records.indices
        where records[i].sessionNumber <= settings.healthExportedThrough {
            records[i].healthExported = true
        }
    }

    #if DEBUG
    private func applyUITestHooks() {
        // Reset means "clean state", not "first run".
        if CommandLine.arguments.contains("--uitest-reset"),
           !CommandLine.arguments.contains("--uitest-onboarding") {
            settings.onboardingCompleted = true
        }
        // The suite must not depend on the weekday it runs on, so these flags
        // clear the rest days outright. --uitest-restday puts today back as a
        // rest day further down, but it does NOT have the last word:
        // --uitest-comeback-long runs after it and the seedLoneWorkout it
        // calls ends by clearing restWeekdays again, so the two flags together
        // leave no rest day at all. No test passes both today — the order is
        // written down here so the next one that wants to does not have to
        // find it out from a failure.
        let seedFlags = ["--uitest-reset", "--uitest-session2", "--uitest-milestone",
                         "--uitest-long-session"]
        if seedFlags.contains(where: CommandLine.arguments.contains) {
            settings.restWeekdays = []
        }
        // Session 1 completed yesterday → today offers session 2, the only
        // deterministic way to reach hold exercises.
        if CommandLine.arguments.contains("--uitest-session2") {
            engineState = .initial
            records = []
            completeWorkout(session: Engine.generateSession(engineState),
                            result: .plan,
                            date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        }
        seedStateIfRequested()
        // Make today a rest day, whichever weekday that is.
        if CommandLine.arguments.contains("--uitest-restday") {
            settings.restWeekdays = [Calendar.current.component(.weekday, from: .now)]
        }
        // Only workout 95 days ago → the comeback card with the paths it
        // still has: the numbered offers and "Start from scratch" (#127). The
        // sick row went with the illness lens.
        if CommandLine.arguments.contains("--uitest-comeback-long") {
            seedLoneWorkout(daysAgo: 95)
        }
        // `--uitest-illness` seeded a five-day gap so the quiet "I was sick"
        // offer would appear. The offer is gone, no test passed the flag any
        // more, and a hook nothing reaches is a branch that will be trusted by
        // the next reader.
    }

    /// The hooks that only build a STATE — no settings, no journal beyond the
    /// one record a break needs. Split off so the flag walk above stays inside
    /// the linter's complexity bound: it grows by one branch every wave, and
    /// the bound is a CI error rather than a style opinion.
    private func seedStateIfRequested() {
        // A trainee well up the scale: band 4, six movements, 55 minutes. The
        // state the mid-workout skip exists for — a plan of three sets can
        // only ever give one of them away and still count as trained, so the
        // escape that takes the REST of a movement has nothing to show at the
        // bottom of the scale.
        if CommandLine.arguments.contains("--uitest-long-session") {
            var seeded = EngineState.initial
            for p in Pattern.allCases { seeded.levels[p] = 34 }
            engineState = seeded
        }
        // One workout away from several milestones. Seeds state only — the
        // milestones and the retrospective still come from the real path.
        if CommandLine.arguments.contains("--uitest-milestone") {
            var seeded = EngineState.initial
            seeded.counter = 9
            for ex in Engine.generateSession(seeded).exercises.prefix(2) {
                seeded.levels[ex.pattern] = 7
            }
            engineState = seeded
            records = [WorkoutRecord(
                sessionNumber: 1,
                date: Calendar.current.date(byAdding: .day, value: -63, to: .now)!,
                result: .plan,
                totalLevelAfter: 0,
                levelsAfter: EngineState.initial.levels)]
        }
        // Only workout 20 days ago → today opens on the comeback card.
        if CommandLine.arguments.contains("--uitest-comeback") {
            seedLoneWorkout(daysAgo: 20)
        }
    }

    /// A single workout `daysAgo` at a uniform level 20 — the seed the three
    /// break-shaped UI-test states share; only the gap differs.
    private func seedLoneWorkout(daysAgo: Int) {
        var seeded = EngineState.initial
        seeded.counter = 11
        for p in Pattern.allCases { seeded.levels[p] = 20 }
        engineState = seeded
        records = [WorkoutRecord(
            sessionNumber: 11,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            result: .plan,
            totalLevelAfter: 180)]
        settings.comebackDecidedFor = nil
        settings.restWeekdays = []
    }
    #endif

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
                maxPerformed[ex.pattern] = max(maxPerformed[ex.pattern] ?? 0, ex.tier)
            }
        }
        var debuts: Set<Pattern> = []
        for ex in nextSession.exercises {
            if let seen = maxPerformed[ex.pattern], ex.tier > seen {
                debuts.insert(ex.pattern)
            }
        }
        return debuts
    }

    // `restingPatterns` is gone with the freeze. Nothing rests any more — a
    // movement the person finds too hard stays in the plan and gets an easier
    // variation or fewer sets, which is the whole point of the wave: the
    // channel that removed movements removed them for weeks.

    var totalLevel: Int { engineState.levels.values.reduce(0, +) }

    /// Oldest first. `through` cuts it at a date: a milestone card must not
    /// draw a curve running past the event it celebrates.
    func levelCurve(through date: Date? = nil) -> [Int] {
        let history = date.map { cut in records.filter { $0.date <= cut } } ?? records
        return history.map(\.totalLevelAfter)
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
                         overrides: [Pattern: Int] = [:],
                         /// The sets behind each override, for the journal.
                         /// The engine never sees them — `overrides` already
                         /// is their mean (`SetFacts.override`).
                         setActuals: SetFacts.PerSet = [:],
                         skipped: Set<Pattern> = [],
                         /// Sets skipped DURING the session, per movement.
                         /// Handed over as what happened — the engine settles
                         /// when it lands, and it lands AFTER the rating.
                         setsSkipped: SetFacts.Skips = [:],
                         durationSec: Int? = nil,
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
                                           gapDays: gapFraction(now: date))
        records.append(WorkoutRecord(
            sessionNumber: session.sessionNumber,
            date: date,
            result: result,
            totalLevelAfter: totalLevel,
            exercises: session.exercises,
            actuals: overrides.isEmpty ? nil : overrides,
            setActuals: setActuals.isEmpty ? nil : setActuals,
            setsSkipped: setsSkipped.isEmpty ? nil : setsSkipped,
            skipped: skipped.isEmpty ? nil : skipped,
            levelsAfter: engineState.levels,
            durationSec: durationSec))
        persist()
        // A morning workout takes tonight's reminder down with it.
        rescheduleReminders(now: date)
        if settings.healthEnabled {
            // Same contiguous path as the manual backfill: an older failed
            // export retries first, so a success cannot leapfrog a hole.
            healthExportTask = Task { await self.backfillHealth() }
        }
        return MilestoneDetector.detect(before: before, after: engineState,
                                        session: session,
                                        skipped: skipped)
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

    // MARK: - Workout in progress

    /// Older than this is a different training occasion, not an interrupted
    /// one.
    static let workoutResumeWindow: TimeInterval = 3 * 60 * 60

    /// Valid only while it still matches the engine, regenerates the very
    /// same exercises, holds actual progress, nothing was completed today,
    /// and is fresh enough to be the same occasion.
    func resumableWorkout(now: Date = .now) -> WorkoutSnapshot? {
        guard let snap = pendingWorkout,
              snap.sessionNumber == engineState.counter + 1,
              // The same number can be a different session: the bar toggle
              // and an accepted comeback regenerate the list without moving
              // the counter, and the snapshot's indices belong to the OLD one.
              snap.fingerprint == WorkoutSnapshot.fingerprint(of: nextSession),
              !doneToday,
              now.timeIntervalSince(snap.savedAt) < Self.workoutResumeWindow,
              // Mirror of the flow's hasProgress: a snapshot from the moment
              // the warm-up ended has nothing to offer.
              snap.atFeedback == true || snap.restEndDate != nil
                  || snap.exIndex > 0 || snap.setIndex > 0
                  || !snap.facts.isEmpty || !snap.skipped.isEmpty
                  || !(snap.discomfort ?? []).isEmpty
        else { return nil }
        return snap
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
            if await self.notifications.requestAuthorization() {
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
        guard let decided = settings.comebackDecidedFor else { return true }
        return !Calendar.current.isDate(decided, inSameDayAs: last.date)
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
        closeComebackQuestion()
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
        persist()
    }

    func declineComeback() {
        closeComebackQuestion()
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
        // the new counter and resume into the wrong workout.
        pendingWorkout = nil
        closeComebackQuestion()
    }

    private func closeComebackQuestion() {
        settings.comebackDecidedFor = records.last?.date
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

    // Apple Health, the local reminders and backup import/export moved to
    // AppStore+Health, +Reminders and +Backup when this class body reached
    // the linter's ceiling. What they still reach from here is why `persist`,
    // the property setters, `migrateHealthMarkToFlags` and the two
    // collaborators are no longer private.

    // MARK: - Persistence

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dredfit-state.json")
    }

    func persist(refreshWidget: Bool = true) {
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
            try JSONEncoder().encode(data).write(to: storageURL, options: .atomic)
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
