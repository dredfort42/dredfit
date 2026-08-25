//
//  Lifted out of AppStore.swift, which sits against the linter's class-body
//  ceiling — a CI error, not a style opinion. The rule the move must not cost:
//  a record is flagged exported only after Health confirms the save, so a hole
//  in the export is always still retriable.
//

import Foundation
import DredfitCore

extension AppStore {

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
    ///
    /// The exercise snapshot comes back out of the journal file, so the whole
    /// sum runs in Double and lands through one clamp: in Int the products
    /// would trap on a hand-edited load, and the final conversion traps on
    /// anything Int cannot hold.
    private func estimatedDurationSec(for record: WorkoutRecord) -> Int {
        guard let exercises = record.exercises, !exercises.isEmpty else { return 35 * 60 }
        // A record written by an older build keeps its pain reports, and they
        // were "not performed" exactly as a skip was — so reading history has
        // to count both. Nothing writes `discomfort` any more.
        let skipped = (record.skipped ?? []).union(record.discomfort ?? [])
        var workSec = 0.0
        for ex in exercises where !skipped.contains(ex.pattern) {
            let sides: Double = ex.perSide ? 2 : 1
            let perSet = ex.unit == .reps
                ? Double(ex.load) * sides * 2.5
                : Double(ex.load) * sides
            workSec += Double(ex.sets) * perSet
                + (Double(ex.sets) - 1) * Double(ex.restSetSec) + Double(ex.restExerciseSec)
        }
        // Read from the engine rather than spelled out: the two were written
        // here as 5 and 3, and the cool-down has since grown to 4. A copy of a
        // config value drifts silently, and nothing pins this number.
        let total = workSec
            + Double((EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60)
        guard total.isFinite else { return 35 * 60 }
        return Int(min(max(total, 0), Double(EngineConfig.countMax)))
    }
}
