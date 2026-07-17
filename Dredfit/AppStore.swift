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
import DredfitCore

/// A completed workout record (feeds the calendar, history and progress chart).
struct WorkoutRecord: Codable, Identifiable, Equatable {
    var id: Int { sessionNumber }
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

    init() {}

    private enum CodingKeys: String, CodingKey {
        case restWeekdays, soundsEnabled, reminderEnabled, reminderHour, reminderMinute
        case healthEnabled, healthExportedThrough
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
    }
}

private struct AppData: Codable {
    var engineState: EngineState
    var records: [WorkoutRecord]
    var settings: AppSettings? = nil   // v1.1
}

@Observable
final class AppStore {

    private(set) var engineState: EngineState
    private(set) var records: [WorkoutRecord]
    private(set) var settings: AppSettings

    private let storageURL: URL
    private let health: WorkoutHealthWriting

    init(storageURL: URL = AppStore.defaultFileURL,
         health: WorkoutHealthWriting = HealthKitWorkoutWriter()) {
        self.storageURL = storageURL
        self.health = health
        if CommandLine.arguments.contains("--uitest-reset") {
            try? FileManager.default.removeItem(at: storageURL)
        }
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: data) {
            engineState = decoded.engineState
            records = decoded.records
            settings = decoded.settings ?? AppSettings()
        } else {
            engineState = .initial
            records = []
            settings = AppSettings()
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
    }

    // MARK: - Derived

    /// The next session in sequence — a pure function of state.
    /// IMPORTANT: right after a workout is completed the counter has advanced,
    /// so this is the NEXT workout. Never present it under today's date —
    /// only with nextTrainingDate (see NextWorkoutSheet).
    var nextSession: Session { Engine.generateSession(engineState) }

    var totalLevel: Int { engineState.levels.values.reduce(0, +) }

    var lastRecord: WorkoutRecord? { records.last }

    /// Has today's workout already been completed?
    var doneToday: Bool { isDone(on: .now) }

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
    var nextTrainingDate: Date { nextTrainingDate(from: .now) }

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
    func weekSummary(for date: Date = .now) -> WeekSummary {
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

    func completeWorkout(session: Session,
                         result: FeedbackResult,
                         overrides: [Pattern: Int] = [:],
                         skipped: Set<Pattern> = [],
                         durationSec: Int? = nil,
                         date: Date = .now) {
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
        if settings.healthEnabled, let record = records.last {
            settings.healthExportedThrough = record.sessionNumber
            saveToHealth(record)
        }
        persist()
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
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        self.rescheduleReminders()
                    } else {
                        // the system said no — reflect reality in the toggle
                        self.settings.reminderEnabled = false
                        self.persist()
                    }
                }
            }
    }

    func setReminderTime(hour: Int, minute: Int) {
        settings.reminderHour = hour
        settings.reminderMinute = minute
        persist()
        rescheduleReminders()
    }

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
        records.filter { $0.sessionNumber > settings.healthExportedThrough }.count
    }

    /// Exports every record above the high-water mark, then advances it.
    func backfillHealth() async {
        let candidates = records.filter { $0.sessionNumber > settings.healthExportedThrough }
        for record in candidates {
            let duration = TimeInterval(record.durationSec ?? estimatedDurationSec(for: record))
            _ = await health.saveWorkout(start: record.date.addingTimeInterval(-duration),
                                         end: record.date)
        }
        settings.healthExportedThrough = records.last?.sessionNumber ?? settings.healthExportedThrough
        persist()
    }

    /// "Only new ones": past workouts are declared already-handled so they
    /// never export later, even after toggling off and on.
    func skipHealthBackfill() {
        settings.healthExportedThrough = records.last?.sessionNumber ?? 0
        persist()
    }

    private func saveToHealth(_ record: WorkoutRecord) {
        let duration = TimeInterval(record.durationSec ?? estimatedDurationSec(for: record))
        let end = record.date
        Task { _ = await health.saveWorkout(start: end.addingTimeInterval(-duration), end: end) }
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
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.reminderIDs)
        guard settings.reminderEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Dredfit"
        content.body = String(localized: "Today's workout is ready")
        content.sound = .default

        for weekday in 1...7 where !settings.restWeekdays.contains(weekday) {
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = settings.reminderHour
            comps.minute = settings.reminderMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "reminder-wd-\(weekday)",
                                             content: content, trigger: trigger))
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
        engineState = decoded.engineState
        records = decoded.records
        settings = decoded.settings ?? AppSettings()
        persist()
        rescheduleReminders()
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
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: storageURL, options: .atomic)
        }
    }
}
