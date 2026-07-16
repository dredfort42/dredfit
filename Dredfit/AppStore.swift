//
//  AppStore.swift
//  Dredfit
//
//  Single source of truth: engine state + workout journal.
//  Persistence — one JSON file in Application Support.
//

import Foundation
import Observation
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
}

private struct AppData: Codable {
    var engineState: EngineState
    var records: [WorkoutRecord]
}

@Observable
final class AppStore {

    private(set) var engineState: EngineState
    private(set) var records: [WorkoutRecord]

    /// Rest day (Calendar.weekday: 1 = Sunday).
    let restWeekday = 1

    private let storageURL: URL

    init(storageURL: URL = AppStore.defaultFileURL) {
        self.storageURL = storageURL
        if CommandLine.arguments.contains("--uitest-reset") {
            try? FileManager.default.removeItem(at: storageURL)
        }
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: data) {
            engineState = decoded.engineState
            records = decoded.records
        } else {
            engineState = .initial
            records = []
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
        Calendar.current.component(.weekday, from: date) == restWeekday
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
            repeat {
                d = cal.date(byAdding: .day, value: 1, to: d)!
            } while isRestDay(d)
        }
        return d
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
                         date: Date = .now) {
        engineState = Engine.applyFeedback(state: engineState, session: session,
                                           result: result, overrides: overrides)
        records.append(WorkoutRecord(
            sessionNumber: session.sessionNumber,
            date: date,
            result: result,
            totalLevelAfter: totalLevel,
            exercises: session.exercises,
            actuals: overrides.isEmpty ? nil : overrides))
        persist()
    }

    // MARK: - Persistence

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dredfit-state.json")
    }

    private func persist() {
        let data = AppData(engineState: engineState, records: records)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: storageURL, options: .atomic)
        }
    }
}
