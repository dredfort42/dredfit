//
//  AppStore.swift
//  Dredfit
//
//  Single source of truth: engine state + workout journal.
//  Persistence — one JSON file in Application Support.
//

import Foundation
import Observation
import UserNotifications
import os
import DredfitCore

struct WorkoutRecord: Codable, Identifiable, Equatable {
    // sessionNumber alone is NOT unique: resetProgress restarts the counter
    // while the journal survives, so identity needs the date too.
    var id: String { "\(sessionNumber)-\(date.timeIntervalSince1970)" }
    let sessionNumber: Int
    let date: Date
    let result: FeedbackResult
    let totalLevelAfter: Int
    // Optional so older records still decode.
    var exercises: [SessionExercise]?
    var actuals: [Pattern: Int]?
    var skipped: Set<Pattern>?
    /// Reported as painful mid-workout: to the engine a skip, to the journal
    /// a different fact — and the reason the pattern is resting afterwards.
    var discomfort: Set<Pattern>?
    /// Asked to hold its level (#78): performed, rated one-directionally,
    /// and not climbing afterwards. Never written when empty, like the rest.
    var pinned: Set<Pattern>?
    var levelsAfter: [Pattern: Int]?
    var durationSec: Int?
    /// Only `true` is ever written; nil means "not exported yet".
    var healthExported: Bool?
}

/// Decoding is field-by-field tolerant — every key optional with a default,
/// so files written by any older version keep loading losslessly.
struct AppSettings: Codable, Equatable {
    /// Calendar weekday numbers: 1 = Sunday, 4 = Wednesday. Fresh installs
    /// only — the decode below keeps the old single-Sunday value.
    var restWeekdays: Set<Int> = [1, 4]
    var soundsEnabled = true
    var reminderEnabled = false
    var reminderHour = 9
    var reminderMinute = 0
    var healthEnabled = false
    var healthExportedThrough = 0      // high-water sessionNumber already in Health
    var onboardingCompleted = false
    var lastReviewRequestAt: Date?
    // A date rather than a bool so it expires by itself: after the next
    // workout it is stale and a future break asks again, while the current
    // break never asks twice. Same mechanism for the silent decay below.
    var comebackDecidedFor: Date?
    var silentDecayAppliedFor: Date?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case restWeekdays, soundsEnabled, reminderEnabled, reminderHour, reminderMinute
        case healthEnabled, healthExportedThrough
        case onboardingCompleted, lastReviewRequestAt, comebackDecidedFor
        case silentDecayAppliedFor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // [1], not the fresh-install default: an upgrade must not add a rest
        // day the person never chose (issue #36).
        restWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .restWeekdays) ?? [1]
        soundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 9
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        healthEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthEnabled) ?? false
        healthExportedThrough = try c.decodeIfPresent(Int.self, forKey: .healthExportedThrough) ?? 0
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        lastReviewRequestAt = try c.decodeIfPresent(Date.self, forKey: .lastReviewRequestAt)
        comebackDecidedFor = try c.decodeIfPresent(Date.self, forKey: .comebackDecidedFor)
        silentDecayAppliedFor = try c.decodeIfPresent(Date.self, forKey: .silentDecayAppliedFor)
    }
}

/// Written on every phase transition, so iOS evicting the process mid-session
/// does not lose it.
struct WorkoutSnapshot: Codable, Equatable {
    var sessionNumber: Int
    /// During rest this is still the set the rest FOLLOWS (the flow advances
    /// after rest) — restore replays that advance when the countdown expired.
    var exIndex: Int
    var setIndex: Int
    var restEndDate: Date?
    var restTotalSec: Int?
    /// What this transition PLANNED, which `restTotalSec` stops being as soon
    /// as the rest is extended — and the extension cap is twice the planned
    /// one. Optional like the fields below: a snapshot from an older build
    /// decodes and falls back to the total it does carry.
    var restPlannedSec: Int?
    var actuals: [Pattern: Int] = [:]
    var skipped: Set<Pattern> = []
    /// Optional, like the fields below: a snapshot written by an older build
    /// must still decode rather than take the whole file down with it.
    var discomfort: Set<Pattern>?
    /// Hold-this-level marks (#78) — a lone pin is progress worth resuming.
    var pinned: Set<Pattern>?
    var workoutStart: Date
    var savedAt: Date
    /// The session number alone is not identity: the bar toggle and an
    /// accepted comeback both regenerate a *different* session under the
    /// *same* number, and a snapshot must never resume into exercises it was
    /// not taken from. Optional (with the fields below) so an older snapshot
    /// decodes and then fails this check, rather than failing the whole file.
    var fingerprint: String?
    /// Restore lands on the rating, not on the set the fields still describe.
    var atFeedback: Bool?
    var interrupted: Pattern?
    /// Deliberately not part of the fingerprint — the session is the same
    /// either way; this is which slice of it was under way.
    var shortPlan: [Pattern]?

    static func fingerprint(of session: Session) -> String {
        session.exercises
            .map { "\($0.pattern.rawValue):\($0.tier):\($0.load):\($0.sets)" }
            .joined(separator: "|")
    }
}

private struct AppData: Codable {
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

    private(set) var engineState: EngineState
    private(set) var records: [WorkoutRecord]
    private(set) var settings: AppSettings
    /// Read through `resumableWorkout`, which applies the validity checks.
    private(set) var pendingWorkout: WorkoutSnapshot?

    /// Views derive "today" from this rather than `Date.now`, so crossing
    /// midnight while suspended invalidates them: mutating it is what
    /// re-renders every date-derived view.
    private(set) var today: Date = .now

    private let storageURL: URL
    private let health: WorkoutHealthWriting
    private let notifications: NotificationScheduling
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
    private var backfillInFlight = false   // guards concurrent Health backfills
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

    /// Legacy high-water mark → per-record flags. The mark keeps being
    /// written so a downgraded build still sees a sane value.
    private func migrateHealthMarkToFlags() {
        guard settings.healthExportedThrough > 0 else { return }
        for i in records.indices
        where records[i].healthExported == nil
            && records[i].sessionNumber <= settings.healthExportedThrough {
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
        // The suite must not depend on the weekday it runs on;
        // --uitest-restday is applied last so it wins.
        let seedFlags = ["--uitest-reset", "--uitest-session2", "--uitest-milestone",
                         "--uitest-discomfort", "--uitest-pinned"]
        if seedFlags.contains(where: CommandLine.arguments.contains) {
            settings.restWeekdays = []
        }
        // A pull reported as painful — or held — yesterday: today's plan
        // still has it, and Today carries the same horizon line either way.
        if CommandLine.arguments.contains("--uitest-discomfort") {
            seedFrozenPull(pinned: false)
        }
        if CommandLine.arguments.contains("--uitest-pinned") {
            seedFrozenPull(pinned: true)
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
            var seeded = EngineState.initial
            seeded.counter = 11
            for p in Pattern.allCases { seeded.levels[p] = 20 }
            engineState = seeded
            records = [WorkoutRecord(
                sessionNumber: 11,
                date: Calendar.current.date(byAdding: .day, value: -20, to: .now)!,
                result: .plan,
                totalLevelAfter: 180)]
            settings.comebackDecidedFor = nil
            settings.restWeekdays = []
        }
        // Make today a rest day, whichever weekday that is.
        if CommandLine.arguments.contains("--uitest-restday") {
            settings.restWeekdays = [Calendar.current.component(.weekday, from: .now)]
        }
    }

    /// Yesterday's workout with one frozen pull — the seed the two freeze
    /// hooks share; the app cannot tell the entrances apart, so only the
    /// journal mark differs.
    private func seedFrozenPull(pinned: Bool) {
        var seeded = EngineState.initial
        seeded.counter = 4
        for p in Pattern.allCases { seeded.levels[p] = 6 }
        seeded.frozen[.pull] = EngineConfig.freezeAppearances
        engineState = seeded
        records = [WorkoutRecord(
            sessionNumber: 4,
            date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
            result: .plan,
            totalLevelAfter: 60,
            discomfort: pinned ? nil : [.pull],
            pinned: pinned ? [.pull] : nil,
            levelsAfter: seeded.levels)]
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
            // A painful exercise was not performed either.
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

    /// Patterns in the upcoming plan whose growth is frozen — after a
    /// discomfort report or a hold-this-level request; the state cannot tell
    /// the two apart, and must not (#75). Still there, still at their level,
    /// not climbing. Scoped to the plan on purpose — a line about a movement
    /// today's workout does not contain would explain nothing.
    ///
    /// Takes the session so a caller that already holds one does not make the
    /// engine generate another: nextSession builds a fresh session on every
    /// access.
    func restingPatterns(in session: Session) -> [Pattern] {
        session.exercises.map(\.pattern)
            .filter { engineState.freezeRemaining($0) > 0 }
    }

    var restingPatterns: [Pattern] { restingPatterns(in: nextSession) }

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

    var nextTrainingDate: Date { nextTrainingDate(from: today) }

    func nextTrainingDate(from now: Date) -> Date {
        let cal = Calendar.current
        var d = now
        if isDone(on: now) || isRestDay(d) {
            var hops = 0
            repeat {
                d = cal.date(byAdding: .day, value: 1, to: d)!
                hops += 1
            } while isRestDay(d) && hops < 7   // toggleRestDay guarantees ≥ 1 training day
        }
        return d
    }

    /// The week is Monday–Sunday regardless of locale.
    struct WeekSummary: Equatable {
        let workouts: Int
        let levelsDelta: Int
    }

    /// Deload weeks can be negative — that is honest, not an error.
    /// nil `date` = the store's anchor, so callers stay midnight-reactive.
    func weekSummary(for date: Date? = nil) -> WeekSummary {
        let date = date ?? today
        var cal = Calendar(identifier: .iso8601)   // Monday-first weeks
        cal.timeZone = Calendar.current.timeZone
        guard let week = cal.dateInterval(of: .weekOfYear, for: date) else {
            return WeekSummary(workouts: 0, levelsDelta: 0)
        }
        let inWeek = records.filter { $0.date >= week.start && $0.date < week.end }
        guard let last = inWeek.last else { return WeekSummary(workouts: 0, levelsDelta: 0) }
        let baseline = records.last { $0.date < week.start }?.totalLevelAfter ?? 0
        return WeekSummary(workouts: inWeek.count,
                           levelsDelta: last.totalLevelAfter - baseline)
    }

    var nextTrainingDateLabel: String { nextTrainingDateLabel(from: today) }

    /// From an arbitrary day: the widget carries one per day, because a
    /// timeline entry rendered days after the write must still say the right
    /// relative word.
    func nextTrainingDateLabel(from day: Date) -> String {
        let cal = Calendar.current
        let d = nextTrainingDate(from: day)
        if cal.isDate(d, inSameDayAs: day) { return String(localized: "today") }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: day),
           cal.isDate(d, inSameDayAs: tomorrow) { return String(localized: "tomorrow") }
        let weekday = d.formatted(.dateTime.weekday(.wide))
        let index = cal.component(.weekday, from: d)   // 1 = Sunday … 7 = Saturday
        switch Locale.current.language.languageCode {
        case .russian:
            return russianOnWeekday(index)
        case .portuguese:
            // Weekday gender: o sábado / o domingo, a segunda…sexta-feira.
            return (index == 1 || index == 7 ? "no " : "na ") + weekday
        default:
            return String(localized: "on \(weekday)")
        }
    }

    /// The formatter only gives the nominative; this needs the accusative.
    private func russianOnWeekday(_ index: Int) -> String {
        switch index {
        case 1: return "в воскресенье"
        case 2: return "в понедельник"
        case 3: return "во вторник"
        case 4: return "в среду"
        case 5: return "в четверг"
        case 6: return "в пятницу"
        default: return "в субботу"
        }
    }

    // MARK: - The only mutation

    /// - Returns: the milestones this workout earned — derived here because
    ///   this is the only place still holding the pre-feedback state.
    @discardableResult
    func completeWorkout(session: Session,
                         result: FeedbackResult,
                         overrides: [Pattern: Int] = [:],
                         skipped: Set<Pattern> = [],
                         discomfort: Set<Pattern> = [],
                         pinned: Set<Pattern> = [],
                         durationSec: Int? = nil,
                         date: Date = .now) -> [Milestone] {
        // Mirror of the engine's replay guard: a session that does not belong
        // to this state must not append a duplicate journal entry either.
        guard session.sessionNumber == engineState.counter + 1 else { return [] }
        pendingWorkout = nil   // the workout is over — nothing to resume
        let before = engineState
        engineState = Engine.applyFeedback(state: engineState, session: session,
                                           result: result, overrides: overrides,
                                           skipped: skipped, discomfort: discomfort,
                                           pinned: pinned)
        records.append(WorkoutRecord(
            sessionNumber: session.sessionNumber,
            date: date,
            result: result,
            totalLevelAfter: totalLevel,
            exercises: session.exercises,
            actuals: overrides.isEmpty ? nil : overrides,
            skipped: skipped.isEmpty ? nil : skipped,
            discomfort: discomfort.isEmpty ? nil : discomfort,
            pinned: pinned.isEmpty ? nil : pinned,
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
                                        skipped: skipped.union(discomfort))
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
                  || !snap.actuals.isEmpty || !snap.skipped.isEmpty
                  || !(snap.discomfort ?? []).isEmpty
                  || !(snap.pinned ?? []).isEmpty
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

    /// Finished **or** skipped. Deliberately not called when it merely
    /// appears: an app killed mid-pager shows it again.
    func completeOnboarding() {
        settings.onboardingCompleted = true
        persist()
    }

    // MARK: - Comeback after a break

    /// Measured at local midnights, so a late-evening workout and an
    /// early-morning launch are one day apart, not zero.
    func gapDays(now: Date? = nil) -> Int? {
        guard let last = records.last else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: last.date),
                                  to: cal.startOfDay(for: now ?? today)).day
    }

    /// Asked once per break: the answer is stamped against the last workout's
    /// date, so it goes stale by itself instead of needing to be cleared.
    func shouldOfferComeback(now: Date? = nil) -> Bool {
        guard let last = records.last, let gap = gapDays(now: now) else { return false }
        guard gap >= EngineConfig.comebackMinGapDays else { return false }
        guard let decided = settings.comebackDecidedFor else { return true }
        return !Calendar.current.isDate(decided, inSameDayAs: last.date)
    }

    /// After a silent decay for the same break this is the weakened
    /// remainder — what accepting would actually subtract now.
    func comebackDrop(now: Date? = nil) -> Int {
        guard let gap = gapDays(now: now) else { return 0 }
        let before = engineState
        let after = Engine.applyComeback(state: before, gapDays: gap,
                                         alreadyDecayed: silentDecayAppliedForCurrentBreak)
        return (before.levels[.pull] ?? 0) - (after.levels[.pull] ?? 0)
    }

    // MARK: - Silent decay for the 7–13 day blind zone (issue #37)

    /// Quiet −1 to every pattern in the 7–13 day gap the comeback does not
    /// reach. Applied at most once per break — the stamp is keyed to the last
    /// workout's date and goes stale by itself, like the comeback answer.
    func applySilentDecayIfNeeded(now: Date? = nil) {
        guard let last = records.last, let gap = gapDays(now: now) else { return }
        guard gap >= EngineConfig.silentDecayGapDays,
              gap < EngineConfig.comebackMinGapDays else { return }
        guard !silentDecayAppliedForCurrentBreak else { return }
        engineState = Engine.applySilentDecay(state: engineState, gapDays: gap)
        settings.silentDecayAppliedFor = last.date
        persist()
    }

    /// Drives both the once-per-break guard and the comeback's
    /// `alreadyDecayed`: the two drops must not stack (spec §14.2).
    private var silentDecayAppliedForCurrentBreak: Bool {
        guard let applied = settings.silentDecayAppliedFor,
              let last = records.last?.date else { return false }
        return Calendar.current.isDate(applied, inSameDayAs: last)
    }

    func offersFreshStart(now: Date? = nil) -> Bool {
        (gapDays(now: now) ?? 0) >= Self.comebackFreshStartDays
    }

    /// Nothing is written to the journal — the next record's levelsAfter
    /// snapshot shows the step down on its own.
    func acceptComeback(now: Date? = nil) {
        guard let gap = gapDays(now: now) else { return }
        engineState = Engine.applyComeback(state: engineState, gapDays: gap,
                                           alreadyDecayed: silentDecayAppliedForCurrentBreak)
        closeComebackQuestion()
    }

    func declineComeback() {
        closeComebackQuestion()
    }

    /// Only the engine resets; the journal and settings survive. `hasBar` is
    /// kept — the bar did not disappear from the doorway.
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

    static let comebackFreshStartDays = 180

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

    // MARK: - Apple Health

    /// On denial the toggle stays off — reality over wishful state.
    func enableHealth() async -> Bool {
        guard health.isAvailable else { return false }
        let granted = await health.requestWriteAuthorization()
        if granted {
            settings.healthEnabled = true
            persist()
        }
        return granted
    }

    /// Keeps the high-water mark: re-enabling later must not duplicate
    /// workouts already in Health.
    func disableHealth() {
        settings.healthEnabled = false
        persist()
    }

    var healthBackfillCount: Int {
        records.filter { $0.healthExported != true }.count
    }

    /// Journal order, one flag at a time, only on a confirmed save. Stops at
    /// the first failure so the tail stays retriable — a failed save is never
    /// declared exported, and a later success cannot leapfrog it. The
    /// in-flight guard forbids a second concurrent run; the while-loop
    /// re-reads the journal (a workout finished mid-run is picked up) and
    /// re-checks the toggle (switching it off stops at the next boundary).
    func backfillHealth() async {
        guard !backfillInFlight else { return }
        backfillInFlight = true
        defer { backfillInFlight = false }
        while settings.healthEnabled,
              let index = records.firstIndex(where: { $0.healthExported != true }) {
            let record = records[index]
            // Clamped: a wall clock moved backwards mid-workout leaves a
            // negative duration, and an interval that does not move forward
            // fails the save forever — blocking the whole tail.
            let duration = max(60, TimeInterval(record.durationSec ?? estimatedDurationSec(for: record)))
            let ok = await health.saveWorkout(start: record.date.addingTimeInterval(-duration),
                                              end: record.date)
            guard ok else { break }   // the tail stays pending for a later retry
            // The await may have replaced the whole journal (importBackup):
            // flag by identity, never by the pre-await index.
            guard let i = records.firstIndex(where: { $0.id == record.id }) else { continue }
            records[i].healthExported = true
            settings.healthExportedThrough = max(settings.healthExportedThrough,
                                                 record.sessionNumber)
            // Durability per record, yes. Poking WidgetKit per record, no:
            // the export flags reach nothing the widget shows, so a full
            // backfill would spend the day's reload budget on identical
            // content (same reason as saveWorkoutSnapshot).
            persist(refreshWidget: false)
        }
    }

    /// Past workouts are declared handled so they never export later, even
    /// after toggling off and on.
    func skipHealthBackfill() {
        for i in records.indices { records[i].healthExported = true }
        settings.healthExportedThrough = max(settings.healthExportedThrough,
                                             records.last?.sessionNumber ?? 0)
        persist()
    }

    /// For records that predate duration capture. Mirrors the engine's
    /// formula; records without a snapshot get a flat 35 min.
    private func estimatedDurationSec(for record: WorkoutRecord) -> Int {
        guard let exercises = record.exercises, !exercises.isEmpty else { return 35 * 60 }
        let skipped = (record.skipped ?? []).union(record.discomfort ?? [])
        var workSec = 0.0
        for ex in exercises where !skipped.contains(ex.pattern) {
            let sides = ex.perSide ? 2 : 1
            let perSet = ex.unit == .reps
                ? Double(ex.load * sides) * 2.5
                : Double(ex.load * sides)
            workSec += Double(ex.sets) * perSet
                + Double((ex.sets - 1) * ex.restSetSec + ex.restExerciseSec)
        }
        return Int(workSec) + (5 + 3) * 60   // warm-up + cool-down
    }

    // MARK: - Local reminders

    /// 28 daily slots stay well under the iOS cap of 64 pending
    /// notifications per app. The accepted price: reminders run dry if the
    /// app is not opened for four weeks (BACKLOG №8).
    static let reminderWindowDays = 28

    /// The older weekly series stays in the removal list so the first
    /// reschedule after an update clears it.
    private static let reminderIDs = (1...7).map { "reminder-wd-\($0)" }
        + (0..<reminderWindowDays).map { "reminder-day-\($0)" }

    /// One one-shot per upcoming training date. Repeating weekly triggers
    /// cannot skip a single firing, and "trained this morning" needs exactly
    /// that. Rebuilt from scratch on every settings change, activation and
    /// completion.
    func rescheduleReminders(now: Date = .now) {
        // A frozen launch knows neither the settings nor the journal: leave
        // what iOS holds rather than clearing a window the user expects.
        guard !journalFrozen else { return }
        notifications.removePendingRequests(withIdentifiers: Self.reminderIDs)
        guard settings.reminderEnabled else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        for offset in 0..<Self.reminderWindowDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  !isRestDay(day), !isDone(on: day) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = settings.reminderHour
            comps.minute = settings.reminderMinute
            // A slot whose time already passed would never fire but would
            // sit in the pending list.
            guard let fire = cal.date(from: comps), fire > now else { continue }
            notifications.addReminder(
                id: "reminder-day-\(offset)",
                title: "Dredfit",
                body: String(localized: "Today's workout is ready"),
                fireDate: comps)
        }
    }

    // MARK: - Backup

    enum BackupError: Error {
        /// The journal could not be read on this launch (see journalFrozen).
        case journalUnavailable
    }

    func exportURL() throws -> URL {
        // Exporting the empty in-memory state would hand the user a file that
        // looks like a backup and destroys their history when imported.
        guard !journalFrozen else { throw BackupError.journalUnavailable }
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dredfit-backup-\(stamp).json")
        let data = try JSONEncoder().encode(
            AppData(engineState: engineState, records: records, settings: settings))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Throws when the file is not a Dredfit backup — the caller alerts.
    func importBackup(from url: URL) throws {
        // Restoring into a frozen store would look like it worked and be gone
        // at the next launch.
        guard !journalFrozen else { throw BackupError.journalUnavailable }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AppData.self, from: data)
        // The Health mark tracks an external side effect (HKWorkouts already
        // written) and must never move backwards on import: an older backup
        // would re-export samples the write-only design cannot detect.
        let priorHealthMark = settings.healthExportedThrough
        engineState = decoded.engineState
        records = decoded.records
        settings = decoded.settings ?? AppSettings()
        // A half-finished workout does not travel with a restored history.
        pendingWorkout = nil
        settings.healthExportedThrough = max(priorHealthMark, settings.healthExportedThrough)
        // Old backups carry only the mark — turn whichever won into flags.
        migrateHealthMarkToFlags()
        persist()
        if settings.reminderEnabled {
            // Authorization is per-device: a backup restored onto a new phone
            // must actually ask, and a denial must flip the toggle off.
            setReminderEnabled(true)
        } else {
            rescheduleReminders()   // clears anything left behind
        }
    }

    // MARK: - Persistence

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dredfit-state.json")
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

// MARK: - Notification seam

/// Injectable seam: unit tests substitute a spy.
protocol NotificationScheduling {
    /// True only when granted.
    func requestAuthorization() async -> Bool
    func removePendingRequests(withIdentifiers ids: [String])
    func addReminder(id: String, title: String, body: String,
                     fireDate: DateComponents)
}

struct UserNotificationScheduler: NotificationScheduling {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func removePendingRequests(withIdentifiers ids: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }

    func addReminder(id: String, title: String, body: String,
                     fireDate: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: fireDate, repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
