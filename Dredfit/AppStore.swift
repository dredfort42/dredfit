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

/// A completed workout record (feeds the calendar, history and progress chart).
struct WorkoutRecord: Codable, Identifiable, Equatable {
    // sessionNumber alone is NOT unique: resetProgress restarts the counter
    // while the journal survives, so identity needs the date too.
    var id: String { "\(sessionNumber)-\(date.timeIntervalSince1970)" }
    let sessionNumber: Int
    let date: Date
    let result: FeedbackResult
    let totalLevelAfter: Int          // level sum after the session — a chart point
    // Fields below were added over time and are optional so older records
    // still decode (history shows a placeholder for nil snapshots).
    var exercises: [SessionExercise]? = nil   // workout snapshot for history
    var actuals: [Pattern: Int]? = nil
    var skipped: Set<Pattern>? = nil          // exercises skipped during the workout
    var levelsAfter: [Pattern: Int]? = nil    // per-pattern level snapshot
    var durationSec: Int? = nil               // actual wall-clock duration (feeds Apple Health)
    // Per-record Health export state. Only `true` is ever written; nil means
    // "not exported yet" (or an old record, migrated on load).
    var healthExported: Bool? = nil
}

/// User preferences, stored in the same JSON file. Decoding is field-by-field
/// tolerant — every key is optional with a default, so files written by any
/// older version keep loading losslessly.
struct AppSettings: Codable, Equatable {
    var restWeekdays: Set<Int> = [1]   // Calendar weekday numbers: 1 = Sunday
    var soundsEnabled = true
    var reminderEnabled = false
    var reminderHour = 9
    var reminderMinute = 0
    var healthEnabled = false
    var healthExportedThrough = 0      // high-water sessionNumber already in Health
    var onboardingCompleted = false
    var lastReviewRequestAt: Date? = nil
    // The last workout's date at the time the comeback question was answered.
    // A date rather than a bool so it expires by itself: after the next
    // workout it is stale and a future break asks again, while the current
    // break never asks twice.
    var comebackDecidedFor: Date? = nil

    init() {}

    private enum CodingKeys: String, CodingKey {
        case restWeekdays, soundsEnabled, reminderEnabled, reminderHour, reminderMinute
        case healthEnabled, healthExportedThrough
        case onboardingCompleted, lastReviewRequestAt, comebackDecidedFor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
    }
}

/// A mid-workout progress snapshot, written on every phase transition of the
/// flow, so that iOS evicting the process during a rest does not lose the
/// session — on the next launch Today offers to continue from this position.
struct WorkoutSnapshot: Codable, Equatable {
    /// The session this snapshot belongs to. The engine state has not moved
    /// (feedback was never given), so the same session regenerates from it —
    /// this number is the guard that proves it still does.
    var sessionNumber: Int
    /// The position exactly as the live flow held it. During rest that is
    /// still the set the rest FOLLOWS (the flow advances after rest) — the
    /// restore path replays that same advance when the countdown has expired.
    var exIndex: Int
    var setIndex: Int
    /// Set while resting. Still in the future → resume inside the countdown;
    /// already past → resume at the set the rest was leading into.
    var restEndDate: Date? = nil
    var restTotalSec: Int? = nil
    var actuals: [Pattern: Int] = [:]
    var skipped: Set<Pattern> = []
    var workoutStart: Date
    var savedAt: Date
    /// Deterministic print of the generated exercise list. The session
    /// number alone is not identity: the bar toggle and an accepted comeback
    /// both regenerate a *different* session under the *same* number, and a
    /// snapshot must never resume into exercises it was not taken from.
    /// Optional (with the others below) so an older snapshot decodes — and
    /// then fails the fingerprint check instead of the whole-file decode.
    var fingerprint: String? = nil
    /// True once the flow reached the rating screen: restore lands there,
    /// not back on the last set the position fields still describe.
    var atFeedback: Bool? = nil
    /// The exercise "Finish now" cut mid-way — the rating screen labels it
    /// "not finished" instead of "skipped".
    var interrupted: Pattern? = nil

    static func fingerprint(of session: Session) -> String {
        session.exercises
            .map { "\($0.pattern.rawValue):\($0.tier):\($0.load):\($0.sets)" }
            .joined(separator: "|")
    }
}

private struct AppData: Codable {
    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings? = nil
    var pendingWorkout: WorkoutSnapshot? = nil
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
    /// The last persisted mid-workout snapshot, if any. Read through
    /// `resumableWorkout`, which applies the freshness and validity checks.
    private(set) var pendingWorkout: WorkoutSnapshot?

    /// The day the UI is anchored to. Views derive "today" from this rather
    /// than from `Date.now` so that crossing midnight while the app sits
    /// suspended invalidates them: RootView calls `refreshDay()` whenever the
    /// scene becomes active, and mutating this property is what re-renders
    /// every date-derived view.
    private(set) var today: Date = .now

    private let storageURL: URL
    private let health: WorkoutHealthWriting
    private let notifications: NotificationScheduling
    let widgetSnapshotURL: URL?
    /// Set when the state file existed but could not be read (data protection
    /// before the first unlock in a prewarmed launch, a transient I/O
    /// failure). While set, persist() is a no-op: the file on disk is the
    /// only copy of the journal and must never be overwritten from the empty
    /// in-memory state. Cleared by reloadIfNeeded(). Read by everything that
    /// publishes state outward — the widget snapshot and the backup export —
    /// because an empty in-memory state must not leave this process either.
    private(set) var journalFrozen = false
    /// Whether the user changed anything since the freeze. A reload would
    /// replace those changes with the file's state without a word, and doing
    /// that mid-workout leaves a session that can never be recorded (the
    /// engine counter moves under it), so a store that has been used stays
    /// frozen until the next launch.
    private var mutatedWhileFrozen = false
    private var backfillInFlight = false   // guards concurrent Health backfills
    /// The in-flight Health export spawned by completeWorkout. Held so tests
    /// can await the fire-and-forget path instead of sleeping.
    private(set) var healthExportTask: Task<Void, Never>?
    /// Same, for the notification-authorization request in setReminderEnabled.
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
        // UI-test hooks are DEBUG-only: a release binary launched with
        // --uitest-reset must never be able to wipe a user's journal.
        if CommandLine.arguments.contains("--uitest-reset") {
            try? FileManager.default.removeItem(at: storageURL)
        }
        #endif
        var loaded: AppData?
        if let data = try? Data(contentsOf: storageURL) {
            do {
                loaded = try JSONDecoder().decode(AppData.self, from: data)
            } catch {
                // The unreadable file is moved aside, not left in place: the
                // next persist() would overwrite the only copy of the journal.
                // Starting clean is the fallback; the data stays recoverable.
                Self.quarantineStateFile(at: storageURL, keepOriginal: false)
                Self.log.fault("state file failed to decode, moved aside: \(error.localizedDescription)")
            }
        } else if FileManager.default.fileExists(atPath: storageURL.path) {
            // The file is there but unreadable. Unlike the decode failure
            // above, the journal itself may be perfectly fine — e.g. still
            // protected before the first unlock. Freeze persistence instead
            // of quarantining; reloadIfNeeded() lifts the freeze.
            journalFrozen = true
            Self.log.fault("state file exists but could not be read — persistence frozen")
        }
        engineState = loaded?.engineState ?? .initial
        records = loaded?.records ?? []
        settings = loaded?.settings ?? AppSettings()
        pendingWorkout = loaded?.pendingWorkout
        if let dropped = loaded?.droppedRecordCount, dropped > 0 {
            // Partial corruption: keep the full original aside before the next
            // persist() rewrites the file without the unreadable entries.
            Self.quarantineStateFile(at: storageURL, keepOriginal: true)
            Self.log.error("dropped \(dropped) unreadable record(s), original kept aside")
        }
        migrateHealthMarkToFlags()
        #if DEBUG
        applyUITestHooks()
        #endif
        refreshWidgetSnapshot()   // the widget mirrors state from launch
    }

    /// Second chance for a launch whose state file could not be read (see
    /// journalFrozen): called when the scene becomes active — i.e. once the
    /// device is certainly unlocked. On success the real state replaces the
    /// empty one, persistence unfreezes and everything derived from state is
    /// rebuilt; while the file stays unreadable the store keeps running
    /// without writing anything.
    func reloadIfNeeded() {
        // Reloading over work the user has already done would erase it
        // silently — mid-workout it would also move the engine counter out
        // from under the running session, leaving a workout that completes
        // into nothing. Such a launch stays frozen; the file is untouched.
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
        // The window was left alone while frozen (see rescheduleReminders):
        // now that the real settings and journal are here, rebuild it.
        rescheduleReminders()
    }

    /// If the day rolled over while the process was alive (an overnight
    /// suspension), re-anchor and thereby invalidate every date-derived view.
    /// Mutating `today` on every activation would re-render for nothing.
    func refreshDay(now: Date = .now) {
        if !Calendar.current.isDate(today, inSameDayAs: now) { today = now }
    }

    /// Moves the state file to `<name>.corrupt.json` (or copies, when the
    /// readable part is being kept) so decode failures never cost the journal.
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

    /// Converts the legacy high-water sessionNumber mark into per-record
    /// flags. The mark itself keeps being written so a downgraded build
    /// still sees a sane value.
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
        // Reset means "clean state", not "first run": the onboarding is
        // marked seen so it stays out of every existing test — unless a test
        // explicitly asks to exercise it.
        if CommandLine.arguments.contains("--uitest-reset"),
           !CommandLine.arguments.contains("--uitest-onboarding") {
            settings.onboardingCompleted = true
        }
        // The suite must not depend on the weekday it runs on (the default
        // Sunday rest day would change what Today shows). Tests that need a
        // rest day ask via --uitest-restday, applied last so it wins.
        if CommandLine.arguments.contains("--uitest-reset")
            || CommandLine.arguments.contains("--uitest-session2")
            || CommandLine.arguments.contains("--uitest-milestone") {
            settings.restWeekdays = []
        }
        // Session 1 completed yesterday → today offers session 2 (the only
        // deterministic way for UI tests to reach hold exercises).
        if CommandLine.arguments.contains("--uitest-session2") {
            engineState = .initial
            records = []
            completeWorkout(session: Engine.generateSession(engineState),
                            result: .plan,
                            date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        }
        // One workout away from several milestones at once. Seeds state only;
        // the milestones are still derived by the real path on completion.
        if CommandLine.arguments.contains("--uitest-milestone") {
            records = []
            var seeded = EngineState.initial
            seeded.counter = 9
            for ex in Engine.generateSession(seeded).exercises.prefix(2) {
                seeded.levels[ex.pattern] = 7
            }
            engineState = seeded
        }
        // A journal whose only workout was 20 days ago, so today opens on
        // the comeback card.
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
    #endif

    // MARK: - Derived

    /// The next session in sequence — a pure function of state.
    /// IMPORTANT: right after a workout is completed the counter has advanced,
    /// so this is the NEXT workout. Never present it under today's date —
    /// only with nextTrainingDate (see NextWorkoutSheet).
    var nextSession: Session { Engine.generateSession(engineState) }

    var totalLevel: Int { engineState.levels.values.reduce(0, +) }

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

    /// Next training date: `now` if not yet trained and not a rest day;
    /// otherwise the nearest future non-rest day.
    var nextTrainingDate: Date { nextTrainingDate(from: today) }

    func nextTrainingDate(from now: Date) -> Date {
        let cal = Calendar.current
        var d = now
        if isDone(on: now) || isRestDay(d) {
            var hops = 0
            repeat {
                d = cal.date(byAdding: .day, value: 1, to: d)!
                hops += 1
            } while isRestDay(d) && hops < 7   // settings guarantee ≥ 1 training day
        }
        return d
    }

    /// Calendar-week summary for the progress screen: workouts and the
    /// total-level delta. The week is Monday–Sunday regardless of locale.
    struct WeekSummary: Equatable {
        let workouts: Int
        let levelsDelta: Int
    }

    /// Counts the records of the calendar week containing `date` and the
    /// total-level change over that week (against the last record before it).
    /// Deload weeks can be negative — that is honest, not an error.
    /// nil = the store's `today` anchor, so callers stay midnight-reactive.
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

    /// "today" / "tomorrow" / "on Saturday" (Russian uses inflected weekday prepositions).
    var nextTrainingDateLabel: String {
        let cal = Calendar.current
        let d = nextTrainingDate
        if cal.isDateInToday(d) { return String(localized: "today") }
        if cal.isDateInTomorrow(d) { return String(localized: "tomorrow") }
        let weekday = d.formatted(.dateTime.weekday(.wide))
        if Locale.current.language.languageCode == .russian {
            // Russian preposition: "во" before Tuesday, otherwise "в"
            let w = weekday.lowercased()
            return (w.hasPrefix("вт") ? "во " : "в ") + w
        }
        return String(localized: "on \(weekday)")
    }

    // MARK: - The only mutation

    /// - Returns: the milestones this workout earned. Derived here because
    ///   this is the only place that still holds the pre-feedback state;
    ///   nothing about them is persisted.
    @discardableResult
    func completeWorkout(session: Session,
                         result: FeedbackResult,
                         overrides: [Pattern: Int] = [:],
                         skipped: Set<Pattern> = [],
                         durationSec: Int? = nil,
                         date: Date = .now) -> [Milestone] {
        // Mirror of the engine's replay guard: a session that does not belong
        // to this state (replayed feedback, a stale snapshot) must not append
        // a duplicate journal entry either.
        guard session.sessionNumber == engineState.counter + 1 else { return [] }
        pendingWorkout = nil   // the workout is over — nothing to resume
        let before = engineState
        engineState = Engine.applyFeedback(state: engineState, session: session,
                                           result: result, overrides: overrides,
                                           skipped: skipped)
        records.append(WorkoutRecord(
            sessionNumber: session.sessionNumber,
            date: date,
            result: result,
            totalLevelAfter: totalLevel,
            exercises: session.exercises,
            actuals: overrides.isEmpty ? nil : overrides,
            skipped: skipped.isEmpty ? nil : skipped,
            levelsAfter: engineState.levels,
            durationSec: durationSec))
        persist()
        // A morning workout takes tonight's reminder down with it: the
        // rebuilt window skips the day that is now done.
        rescheduleReminders(now: date)
        if settings.healthEnabled {
            // The just-finished workout goes through the same contiguous
            // export path as the manual backfill — an older failed export gets
            // retried first, so a success can never leapfrog an earlier hole.
            healthExportTask = Task { await self.backfillHealth() }
        }
        return MilestoneDetector.detect(before: before, after: engineState,
                                        session: session, skipped: skipped)
    }

    // MARK: - Workout in progress

    /// A snapshot older than this is a different training occasion, not an
    /// interrupted one — offering to "continue" a workout from this morning
    /// at 9 pm would be dishonest about what the session was.
    static let workoutResumeWindow: TimeInterval = 3 * 60 * 60

    /// The snapshot Today may offer to continue, or nil. Valid only while it
    /// still matches the engine (no feedback was applied since), regenerates
    /// the very same exercises, holds actual progress, nothing was completed
    /// today, and it is fresh enough to be the same occasion.
    func resumableWorkout(now: Date = .now) -> WorkoutSnapshot? {
        guard let snap = pendingWorkout,
              snap.sessionNumber == engineState.counter + 1,
              // The same number can be a different session: the bar toggle
              // and an accepted comeback regenerate the exercise list
              // without moving the counter, and the snapshot's indices,
              // actuals and skips belong to the OLD list.
              snap.fingerprint == WorkoutSnapshot.fingerprint(of: nextSession),
              !doneToday,
              now.timeIntervalSince(snap.savedAt) < Self.workoutResumeWindow,
              // Mirror of the flow's hasProgress: a snapshot from the moment
              // the warm-up ended (first set untouched, nothing recorded)
              // has nothing to offer — the honest card for that launch is
              // the plain Start, warm-up included.
              snap.atFeedback == true || snap.restEndDate != nil
                  || snap.exIndex > 0 || snap.setIndex > 0
                  || !snap.actuals.isEmpty || !snap.skipped.isEmpty
        else { return nil }
        return snap
    }

    /// Called by the workout flow on every phase transition — some 35 times
    /// in a full session. `refreshWidget: false` is not an optimization but
    /// the truth: none of the widget's three states (workout / done / rest)
    /// can change while a workout is in progress, and poking WidgetKit on
    /// every set would spend the day's reload budget on identical content.
    func saveWorkoutSnapshot(_ snapshot: WorkoutSnapshot) {
        pendingWorkout = snapshot
        persist(refreshWidget: false)
    }

    /// The workout ended in any deliberate way — completed, discarded via
    /// Exit, or restarted from scratch. Nothing is left to resume. Widget
    /// untouched for the same reason as in saveWorkoutSnapshot.
    func clearWorkoutSnapshot() {
        guard pendingWorkout != nil else { return }
        pendingWorkout = nil
        persist(refreshWidget: false)
    }

    // MARK: - Settings

    /// Toggles a rest day. Refuses to turn the last training day into rest —
    /// at least one training day always remains (nextTrainingDate relies on it).
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

    /// The "pull-up bar" toggle writes straight into engine state —
    /// alternation is derived from it and the session counter. Turning it
    /// off freezes the vertical branch; its level is kept.
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

    /// The first-run explainer is for genuinely new installs only: an empty
    /// journal, an untouched engine, and no earlier run that finished it.
    /// Anyone with history has already learned the app by using it.
    var shouldShowOnboarding: Bool {
        // A frozen launch (unreadable journal) knows nothing about the user —
        // never mistake it for a fresh install.
        !journalFrozen && records.isEmpty && engineState.counter == 0
            && !settings.onboardingCompleted
    }

    /// Called when the onboarding is finished **or skipped** — both count as
    /// "seen". Deliberately not called when it merely appears: an app killed
    /// mid-pager shows it again rather than silently swallowing the one
    /// explanation of how the thermostat works.
    func completeOnboarding() {
        settings.onboardingCompleted = true
        persist()
    }

    // MARK: - Comeback after a break

    /// Whole calendar days between the last workout and now, measured at local
    /// midnights so a late-evening workout and an early-morning launch are one
    /// day apart, not zero. nil `now` = the store's midnight-reactive anchor.
    func gapDays(now: Date? = nil) -> Int? {
        guard let last = records.last else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: last.date),
                                  to: cal.startOfDay(for: now ?? today)).day
    }

    /// Whether to offer the comeback card. Asked once per break: the answer is
    /// stamped against the last workout's date, so it goes stale by itself
    /// after the next workout instead of needing to be cleared.
    func shouldOfferComeback(now: Date? = nil) -> Bool {
        guard let last = records.last, let gap = gapDays(now: now) else { return false }
        guard gap >= EngineConfig.comebackMinGapDays else { return false }
        guard let decided = settings.comebackDecidedFor else { return true }
        return !Calendar.current.isDate(decided, inSameDayAs: last.date)
    }

    /// How far the levels would drop — used by the card to say it plainly.
    func comebackDrop(now: Date? = nil) -> Int {
        guard let gap = gapDays(now: now) else { return 0 }
        let before = engineState
        let after = Engine.applyComeback(state: before, gapDays: gap)
        return (before.levels[.pull] ?? 0) - (after.levels[.pull] ?? 0)
    }

    /// A gap this long makes the old levels meaningless rather than merely
    /// optimistic, so starting over becomes an option worth offering.
    func offersFreshStart(now: Date? = nil) -> Bool {
        (gapDays(now: now) ?? 0) >= Self.comebackFreshStartDays
    }

    /// "Start easier": lower the levels and close the question for this break.
    /// Nothing is written to the journal — the next record's levelsAfter
    /// snapshot shows the step down on its own.
    func acceptComeback(now: Date? = nil) {
        guard let gap = gapDays(now: now) else { return }
        engineState = Engine.applyComeback(state: engineState, gapDays: gap)
        closeComebackQuestion()
    }

    /// "Leave it as it was": no state change, but the question is answered.
    func declineComeback() {
        closeComebackQuestion()
    }

    /// Clean slate after a very long break. The journal and settings survive —
    /// only the engine resets — and `hasBar` is deliberately kept: the pull-up
    /// bar did not disappear from the doorway while the user was away.
    func resetProgress() {
        let hadBar = engineState.hasBar
        engineState = .initial
        engineState.hasBar = hadBar
        // Session numbers restart — a pre-reset snapshot could otherwise
        // collide with the new counter and resume into the wrong workout.
        pendingWorkout = nil
        closeComebackQuestion()
    }

    private func closeComebackQuestion() {
        settings.comebackDecidedFor = records.last?.date
        persist()
        refreshWidgetSnapshot()
    }

    static let comebackFreshStartDays = 180

    // MARK: - App Store review

    /// Whether to ask for a review right now. Pure and injectable so the gate
    /// is unit-testable without StoreKit: every condition must hold.
    /// Asking after a workout the user found too hard would be tone-deaf, so
    /// a `.less` rating disqualifies the session outright.
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

    /// Turning the toggle on: ask for write-only authorization. On denial
    /// the toggle stays off — reality over wishful state, no nagging.
    func enableHealth() async -> Bool {
        guard health.isAvailable else { return false }
        let granted = await health.requestWriteAuthorization()
        if granted {
            settings.healthEnabled = true
            persist()
        }
        return granted
    }

    /// Turning it off keeps the exported high-water mark — re-enabling
    /// later never duplicates workouts already in Health.
    func disableHealth() {
        settings.healthEnabled = false
        persist()
    }

    /// How many past workouts a backfill would add to Health.
    var healthBackfillCount: Int {
        records.filter { $0.healthExported != true }.count
    }

    /// Exports every unexported record in journal order, flagging one record
    /// at a time and only on a confirmed save. Stops at the first failure so
    /// the unexported tail can be retried later — a failed save is never
    /// declared exported, and a later success can never leapfrog it. The
    /// in-flight guard forbids a second concurrent run; the while-loop
    /// re-reads the journal so a workout completed mid-run is picked up by
    /// the run already in flight, and re-checks the Health toggle so
    /// switching it off stops the run at the next record boundary.
    func backfillHealth() async {
        guard !backfillInFlight else { return }
        backfillInFlight = true
        defer { backfillInFlight = false }
        while settings.healthEnabled,
              let index = records.firstIndex(where: { $0.healthExported != true }) {
            let record = records[index]
            // Clamped: a wall clock moved backwards mid-workout can leave a
            // negative stored duration, and an interval that does not move
            // forward fails the save forever — blocking the whole tail.
            let duration = max(60, TimeInterval(record.durationSec ?? estimatedDurationSec(for: record)))
            let ok = await health.saveWorkout(start: record.date.addingTimeInterval(-duration),
                                              end: record.date)
            guard ok else { break }   // the tail stays pending for a later retry
            // The await may have replaced the whole journal (importBackup) —
            // flag the record by identity, never by the pre-await index.
            guard let i = records.firstIndex(where: { $0.id == record.id }) else { continue }
            records[i].healthExported = true
            settings.healthExportedThrough = max(settings.healthExportedThrough,
                                                 record.sessionNumber)
            persist()
        }
    }

    /// "Only new ones": past workouts are declared already-handled so they
    /// never export later, even after toggling off and on.
    func skipHealthBackfill() {
        for i in records.indices { records[i].healthExported = true }
        settings.healthExportedThrough = max(settings.healthExportedThrough,
                                             records.last?.sessionNumber ?? 0)
        persist()
    }

    /// Fallback for records that predate duration capture: mirrors the
    /// engine's duration formula over the stored snapshot, skipping skipped
    /// exercises. Records without a snapshot get a flat 35 min.
    private func estimatedDurationSec(for record: WorkoutRecord) -> Int {
        guard let exercises = record.exercises, !exercises.isEmpty else { return 35 * 60 }
        let skipped = record.skipped ?? []
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

    /// How far ahead the one-shot reminder window reaches. 28 daily slots
    /// stay well under the iOS cap of 64 pending notifications per app; the
    /// accepted price is that reminders run dry if the app is not opened at
    /// all for four weeks (BACKLOG №8) — every activation refills the window.
    static let reminderWindowDays = 28

    /// The older weekly repeating series stays in the removal list so the
    /// first reschedule after an update clears it.
    private static let reminderIDs = (1...7).map { "reminder-wd-\($0)" }
        + (0..<reminderWindowDays).map { "reminder-day-\($0)" }

    /// One one-shot notification per upcoming training date at the chosen
    /// time. Repeating weekly triggers cannot skip a single firing, and
    /// "trained this morning" needs exactly that — with one-shots, a
    /// completed workout simply rebuilds the window without today in it.
    /// Rebuilt from scratch on every settings change, scene activation and
    /// workout completion — no drift, and the window slides forward.
    func rescheduleReminders(now: Date = .now) {
        // A frozen launch knows neither the settings nor the journal: leave
        // whatever iOS already holds rather than clearing a window the user
        // still expects. reloadIfNeeded() rebuilds it once the file is read.
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
            // A slot whose time already passed (only ever today's) would
            // never fire but would sit in the pending list — skip it.
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
        /// The journal could not be read on this launch, so there is nothing
        /// honest to export (see journalFrozen).
        case journalUnavailable
    }

    /// A dated copy of the state file for the share sheet.
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

    /// Replaces the whole state with the contents of a backup file.
    /// Throws when the file is not a Dredfit backup — the caller shows an alert.
    func importBackup(from url: URL) throws {
        // Restoring into a frozen store would look like it worked and be gone
        // at the next launch — the write cannot reach the file either.
        guard !journalFrozen else { throw BackupError.journalUnavailable }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AppData.self, from: data)
        // The Health high-water mark tracks an external, device-local side
        // effect (HKWorkouts already written). It must never move backwards on
        // import — an older backup would otherwise re-export samples already
        // in Health, which the write-only design cannot detect.
        let priorHealthMark = settings.healthExportedThrough
        engineState = decoded.engineState
        records = decoded.records
        settings = decoded.settings ?? AppSettings()
        // A half-finished workout is tied to the device and moment it was
        // interrupted on — it does not travel with a restored history.
        pendingWorkout = nil
        settings.healthExportedThrough = max(priorHealthMark, settings.healthExportedThrough)
        // New backups carry per-record flags; old ones carry only the mark —
        // the migration turns whichever mark won above into flags.
        migrateHealthMarkToFlags()
        persist()
        if settings.reminderEnabled {
            // Notification authorization is per-device: a backup restored onto
            // a new phone must actually ask, and a denial must flip the toggle
            // off instead of promising reminders that will never fire.
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
        // empty state that replaced it (see journalFrozen). The change stays
        // in memory for this launch only — and it pins the freeze, so a
        // later reload cannot swap it out from under the user.
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
            // The in-memory state is still correct and the next mutation
            // retries the full write — but this is the app's only durability
            // path, so a failure must at least leave a trace.
            Self.log.fault("persist failed: \(error.localizedDescription)")
        }
        // Every persisted change reaches the widget — except the ones that
        // provably cannot change what it shows (see saveWorkoutSnapshot).
        if refreshWidget { refreshWidgetSnapshot() }
    }
}

// MARK: - Notification seam

/// Injectable seam mirroring the Health one: AppStore schedules reminders
/// through this protocol, unit tests substitute a spy.
protocol NotificationScheduling {
    /// Asks for alert+sound authorization. Returns true only when granted.
    func requestAuthorization() async -> Bool
    func removePendingRequests(withIdentifiers ids: [String])
    /// One one-shot calendar-trigger notification for a concrete date.
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
