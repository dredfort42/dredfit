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
    // Workout snapshot for history. Optional — records created before
    // UPDATE-3 decode as nil and show a graceful placeholder.
    var exercises: [SessionExercise]? = nil
    var actuals: [Pattern: Int]? = nil
    // v1.1 additions, optional for the same migration reason:
    var skipped: Set<Pattern>? = nil        // exercises skipped during the workout
    var levelsAfter: [Pattern: Int]? = nil  // per-pattern level snapshot (feeds future charts)
    // v1.3: the actual wall-clock workout duration (feeds Apple Health)
    var durationSec: Int? = nil
    // v1.6: per-record Health export state. Only `true` is ever written;
    // nil means "not exported yet" (or a pre-1.6 record, migrated on load).
    // Replaces the high-water sessionNumber mark, which broke down once
    // resetProgress made session numbers non-unique.
    var healthExported: Bool? = nil
}

/// User preferences (v1.1). Stored in the same JSON file; optional on
/// decode, so files written by v1.0 load with the defaults.
/// v1.3: decoding is field-by-field tolerant — every key is optional with a
/// default, so files written by any older version keep loading losslessly.
struct AppSettings: Codable, Equatable {
    var restWeekdays: Set<Int> = [1]   // Calendar weekday numbers: 1 = Sunday
    var soundsEnabled = true
    var reminderEnabled = false
    var reminderHour = 9
    var reminderMinute = 0
    // v1.3 — Apple Health (both default off/zero for pre-1.3 files)
    var healthEnabled = false
    var healthExportedThrough = 0      // high-water sessionNumber already in Health
    // v1.4 — first-run onboarding and the App Store review gate.
    // Both default to "never happened", so pre-1.4 files behave as if the user
    // has neither seen the onboarding nor been asked for a review. Users with
    // history are kept out of the onboarding by the journal check, not by this.
    var onboardingCompleted = false
    var lastReviewRequestAt: Date? = nil
    // v1.5: the date of the last workout for which the comeback question was
    // already answered. Keyed on that date rather than a bool so it expires by
    // itself: after the next workout the stored date is stale and a future
    // break asks again, while the current break never asks twice.
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

private struct AppData: Codable {
    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings? = nil   // v1.1
    // v1.6: how many journal entries failed to decode (not encoded) — the
    // caller keeps the original file aside when this is nonzero.
    var droppedRecordCount = 0

    init(engineState: EngineState, records: [WorkoutRecord], settings: AppSettings?) {
        self.engineState = engineState
        self.records = records
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case engineState, records, settings }

    /// v1.6: the journal decodes record-by-record — one unreadable entry
    /// (e.g. written by a newer version) must not throw away the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engineState = try c.decode(EngineState.self, forKey: .engineState)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings)
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
    private var backfillInFlight = false   // v1.3: guards concurrent Health backfills
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
        }
        engineState = loaded?.engineState ?? .initial
        records = loaded?.records ?? []
        settings = loaded?.settings ?? AppSettings()
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
        refreshWidgetSnapshot()   // v1.3: the widget mirrors state from launch
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

    /// v1.6: converts the pre-1.6 high-water sessionNumber mark into
    /// per-record flags. The mark itself keeps being written so a downgraded
    /// build still sees a sane value.
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
        // UI-test hook: a reset install would otherwise open on the v1.4
        // onboarding and hide the app from every existing test. Reset means
        // "clean state", not "first run", so the explainer is marked seen —
        // unless a test explicitly asks to exercise it.
        if CommandLine.arguments.contains("--uitest-reset"),
           !CommandLine.arguments.contains("--uitest-onboarding") {
            settings.onboardingCompleted = true
        }
        // The suite must not depend on the weekday it runs on: a clean
        // state's default Sunday rest day used to fail most of the suite
        // every Sunday (Today opens on "Rest day", not "Workout N"). Tests
        // that need a rest day ask for one via --uitest-restday, applied
        // last so it wins over this.
        if CommandLine.arguments.contains("--uitest-reset")
            || CommandLine.arguments.contains("--uitest-session2")
            || CommandLine.arguments.contains("--uitest-milestone") {
            settings.restWeekdays = []
        }
        // UI-test hook: session 1 completed yesterday → today offers session 2
        // (the only way for UI tests to reach hold exercises deterministically).
        if CommandLine.arguments.contains("--uitest-session2") {
            engineState = .initial
            records = []
            completeWorkout(session: Engine.generateSession(engineState),
                            result: .plan,
                            date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        }
        // UI-test hook: one workout away from several milestones at once —
        // two patterns at the top of tier 1, counter on the eve of the tenth
        // workout. Seeds state only; the milestones are still derived by the
        // real path when the workout completes.
        if CommandLine.arguments.contains("--uitest-milestone") {
            records = []
            var seeded = EngineState.initial
            seeded.counter = 9
            for ex in Engine.generateSession(seeded).exercises.prefix(2) {
                seeded.levels[ex.pattern] = 7
            }
            engineState = seeded
        }
        // UI-test hook: a journal whose only workout was 20 days ago, so
        // today opens on the comeback card.
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
        // UI-test hook: make today a rest day, whichever weekday that is.
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

    /// Has today's workout already been completed?
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

    /// Calendar-week summary for the progress screen (v1.3): workouts and the
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

    /// - Returns: the milestones this workout earned (v1.4). Derived here
    ///   because this is the only place that still holds the pre-feedback
    ///   state; nothing about them is persisted.
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
        if settings.healthEnabled {
            // v1.6: the just-finished workout goes through the same contiguous
            // export path as the manual backfill — an older failed export gets
            // retried first, so a success can never leapfrog an earlier hole.
            healthExportTask = Task { await self.backfillHealth() }
        }
        return MilestoneDetector.detect(before: before, after: engineState,
                                        session: session, skipped: skipped)
    }

    // MARK: - Settings (v1.1)

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

    /// v2.2: the "pull-up bar" toggle writes straight into engine state —
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

    // MARK: - Onboarding (v1.4)

    /// The first-run explainer is for genuinely new installs only: an empty
    /// journal, an untouched engine, and no earlier run that finished it.
    /// Anyone with history has already learned the app by using it.
    var shouldShowOnboarding: Bool {
        records.isEmpty && engineState.counter == 0 && !settings.onboardingCompleted
    }

    /// Called when the onboarding is finished **or skipped** — both count as
    /// "seen". Deliberately not called when it merely appears: an app killed
    /// mid-pager shows it again rather than silently swallowing the one
    /// explanation of how the thermostat works.
    func completeOnboarding() {
        settings.onboardingCompleted = true
        persist()
    }

    // MARK: - Comeback after a break (v1.5)

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
        closeComebackQuestion()
    }

    private func closeComebackQuestion() {
        settings.comebackDecidedFor = records.last?.date
        persist()
        refreshWidgetSnapshot()
    }

    static let comebackFreshStartDays = 180

    // MARK: - App Store review (v1.4)

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

    // MARK: - Apple Health (v1.3)

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
    /// at a time and only on a confirmed save. It stops at the first failure
    /// so the unexported tail can be retried later — a failed save is never
    /// declared exported, and a later success can never leapfrog it (the old
    /// max()-mark design silently lost exactly that workout). The in-flight
    /// guard forbids a second concurrent run (double-export window); the
    /// while-loop re-reads the journal so a workout completed mid-run is
    /// picked up by the run already in flight.
    func backfillHealth() async {
        guard !backfillInFlight else { return }
        backfillInFlight = true
        defer { backfillInFlight = false }
        while let index = records.firstIndex(where: { $0.healthExported != true }) {
            let record = records[index]
            let duration = TimeInterval(record.durationSec ?? estimatedDurationSec(for: record))
            let ok = await health.saveWorkout(start: record.date.addingTimeInterval(-duration),
                                              end: record.date)
            guard ok else { break }   // the tail stays pending for a later retry
            records[index].healthExported = true
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

    /// Session-estimate fallback for records that predate duration capture:
    /// mirrors the engine's duration formula over the stored snapshot,
    /// skipping skipped exercises. Snapshot-less v1.0 records get a flat 35 min.
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

    // MARK: - Local reminders (v1.1)

    private static let reminderIDs = (1...7).map { "reminder-wd-\($0)" }

    /// One weekly repeating notification per training weekday at the chosen
    /// time. Rebuilt from scratch on every settings change — no drift.
    func rescheduleReminders() {
        notifications.removePendingRequests(withIdentifiers: Self.reminderIDs)
        guard settings.reminderEnabled else { return }
        for weekday in 1...7 where !settings.restWeekdays.contains(weekday) {
            notifications.addWeeklyReminder(
                id: "reminder-wd-\(weekday)",
                title: "Dredfit",
                body: String(localized: "Today's workout is ready"),
                weekday: weekday,
                hour: settings.reminderHour,
                minute: settings.reminderMinute)
        }
    }

    // MARK: - Backup (v1.1)

    /// A dated copy of the state file for the share sheet.
    func exportURL() throws -> URL {
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
        settings.healthExportedThrough = max(priorHealthMark, settings.healthExportedThrough)
        // v1.6: new backups carry per-record flags; old ones carry only the
        // mark — the migration turns whichever mark won above into flags.
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

    private func persist() {
        let data = AppData(engineState: engineState, records: records, settings: settings)
        do {
            try JSONEncoder().encode(data).write(to: storageURL, options: .atomic)
        } catch {
            // The in-memory state is still correct and the next mutation
            // retries the full write — but a silent failure here is the app's
            // only durability path, so it must at least leave a trace.
            Self.log.fault("persist failed: \(error.localizedDescription)")
        }
        refreshWidgetSnapshot()   // v1.3: every persisted change reaches the widget
    }
}

// MARK: - Notification seam (v1.6)

/// Injectable seam mirroring the Health one: AppStore schedules reminders
/// through this protocol, unit tests substitute a spy.
protocol NotificationScheduling {
    /// Asks for alert+sound authorization. Returns true only when granted.
    func requestAuthorization() async -> Bool
    func removePendingRequests(withIdentifiers ids: [String])
    /// One weekly repeating calendar-trigger notification.
    func addWeeklyReminder(id: String, title: String, body: String,
                           weekday: Int, hour: Int, minute: Int)
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

    func addWeeklyReminder(id: String, title: String, body: String,
                           weekday: Int, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
