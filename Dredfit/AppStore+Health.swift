//
//  Lifted out of AppStore.swift, which sits against the linter's class-body
//  ceiling — a CI error, not a style opinion. The rule the move must not cost:
//  a record is flagged exported only after Health confirms the save, so a hole
//  in the export is always still retriable.
//

import Foundation
import DredfitCore

/// Read once per backfill run, not once per record: the profile does not
/// change mid-run, and the foreign-workout sweep is ONE query over the whole
/// journal rather than one per workout.
private struct EnergyContext {
    var bodyMassKg: Double?
    var profile = BodyProfile.unknown
    var foreign: [DateInterval] = []
}

extension AppStore {

    // MARK: - Apple Health

    /// On denial the toggle stays off — reality over wishful state.
    func enableHealth() async -> Bool {
        guard health.isAvailable else { return false }
        let granted = await health.requestAuthorization()
        if granted {
            settings.healthEnabled = true
            persist()
            // The weight follows Health from here on, this reading included.
            await refreshBodyMassFromHealth()
        }
        return granted
    }

    /// Keeps the high-water mark: re-enabling later must not duplicate
    /// workouts already in Health.
    func disableHealth() {
        settings.healthEnabled = false
        persist()
    }

    /// Kilograms in, kilograms out — the pounds a US field displays are
    /// converted before they get here. `nil` clears it, and clearing is a real
    /// answer: no weight means no calories, not calories from a default.
    func setBodyMass(_ kg: Double?) {
        settings.bodyMassKg = kg.flatMap(Self.sanitizedBodyMass)
        // Typed, so it is not Health's — until the next activation finds a
        // reading, which takes the row back. This flag is what the settings
        // row reads to decide whether it may be edited at all.
        settings.bodyMassFromHealth = false
        persist()
    }

    /// Health is the owner's weight and the phone has one owner, so the number
    /// the app shows — and multiplies every calorie by — follows Health rather
    /// than being a copy taken once when the toggle went on. Called on every
    /// activation and at the head of every export run.
    ///
    /// A `nil` reading NEVER clears anything: an empty Health and a refused
    /// read are the same nil (HealthKit does not distinguish them), and
    /// erasing on it would silently switch a person's calories off. It only
    /// hands the field back, so the weight stays typeable.
    ///
    /// Writes only on a real change: this runs on every foreground, and an
    /// unconditional `persist()` would rewrite the journal file for a number
    /// that did not move.
    func refreshBodyMassFromHealth() async {
        guard settings.healthEnabled, health.isAvailable else { return }
        let reading = await health.latestBodyMassKg().flatMap(Self.sanitizedBodyMass)
        // Both re-checks are about that await, not about the guard above. The
        // toggle can go down while the query hangs — the backfill loop below
        // re-reads it at every boundary for exactly this reason — and a newer
        // activation may have cancelled this run, in which case its reading is
        // the older of the two and must not land on top of the newer one.
        guard settings.healthEnabled, !Task.isCancelled else { return }
        let mass = reading ?? settings.bodyMassKg
        let fromHealth = reading != nil
        guard settings.bodyMassKg != mass || settings.bodyMassFromHealth != fromHealth
        else { return }
        settings.bodyMassKg = mass
        settings.bodyMassFromHealth = fromHealth
        // The weight reaches nothing the widget shows (same argument as the
        // export flags below).
        persist(refreshWidget: false)
    }

    func setWatchRecordsWorkouts(_ on: Bool) {
        settings.watchRecordsWorkouts = on
        persist()
    }

    private static func sanitizedBodyMass(_ kg: Double) -> Double? {
        guard kg.isFinite, kg > 0 else { return nil }
        return min(kg, 500)
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
        let context = await energyContext()
        while settings.healthEnabled,
              let index = records.firstIndex(where: { $0.healthExported != true }) {
            let record = records[index]
            let span = Self.interval(for: record, estimate: estimatedDurationSec(for: record))
            let kcal = await activeKcal(for: record, span: span, context: context)
            let ok = await health.saveWorkout(start: span.start, end: span.end,
                                              activeKcal: kcal, journalID: record.id)
            guard ok else { break }   // the tail stays pending for a later retry
            // The await may have replaced the whole journal (importBackup):
            // flag by identity, never by the pre-await index.
            //
            // …and by identity AMONG THE UNEXPORTED, which is what makes the
            // loop terminate. The selection above asks for an unflagged
            // record and this asks only for a matching id, so two records
            // sharing an `id` — one journal, `sessionNumber` restarted by
            // `resetProgress`, the same `date` to the double — sent every
            // flag to the FIRST of the pair while the second stayed unflagged
            // and was picked again. The loop then wrote a duplicate HKWorkout
            // per turn, forever, into a store the app cannot clean up. Only a
            // hand-edited journal reaches it, which is exactly the input every
            // decoder in this project is written against.
            guard let i = records.firstIndex(where: {
                $0.id == record.id && $0.healthExported != true
            }) else { continue }
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

    // MARK: - The interval a record occupies

    /// Clamped: a wall clock moved backwards mid-workout leaves a negative
    /// duration, and an interval that does not move forward fails the save
    /// forever — blocking the whole tail.
    private static func interval(for record: WorkoutRecord,
                                 estimate: Int) -> DateInterval {
        let duration = max(60, TimeInterval(record.durationSec ?? estimate))
        return DateInterval(start: record.date.addingTimeInterval(-duration), end: record.date)
    }

    // MARK: - Calories

    /// Nothing is read from Health unless a weight makes the reading useful:
    /// without one there is no calorie to compute, and the queries would be
    /// two questions asked for no answer.
    private func energyContext() async -> EnergyContext {
        // Before the guard, not after: the weight the calories are multiplied
        // by has to be today's, and an export can run hours after the
        // activation that last refreshed it.
        await refreshBodyMassFromHealth()
        guard let kg = settings.bodyMassKg, !settings.watchRecordsWorkouts else {
            return EnergyContext()
        }
        var context = EnergyContext(bodyMassKg: kg)
        context.profile = await health.profile()
        let spans = records
            .filter { $0.healthExported != true }
            .map { Self.interval(for: $0, estimate: estimatedDurationSec(for: $0)) }
        // Up to now, not to the last pending record: the loop re-reads the
        // journal, so a workout finished seconds into the run is exported by
        // this same pass and has to be inside the swept window. One finished
        // AFTER the sweep is not, and its calories go out unchecked — the same
        // fail-open as a refused read, and the calories-off switch is the way
        // out of both.
        if let from = spans.map(\.start).min() {
            let to = max(spans.map(\.end).max() ?? .now, .now)
            if from < to {
                context.foreign = await health.foreignWorkoutIntervals(start: from, end: to)
            }
        }
        return context
    }

    /// `nil` whenever the number would be a guess rather than an estimate: no
    /// weight, no exercise snapshot to segment, or a session the person also
    /// recorded on a watch — that one already carries its own measured energy,
    /// and ours would be counted a second time.
    private func activeKcal(for record: WorkoutRecord,
                            span: DateInterval,
                            context: EnergyContext) async -> Double? {
        guard let kg = context.bodyMassKg,
              let exercises = record.exercises,
              let segments = EnergyEstimate.segments(exercises: exercises,
                                                     skipped: Self.notPerformed(in: record),
                                                     warmupSec: record.warmupSec,
                                                     cooldownSec: record.cooldownSec),
              !context.foreign.contains(where: { ($0.intersection(with: span)?.duration ?? 0) > 0 })
        else { return nil }
        // The rate is read over the interval the SUM covers, not over the plan:
        // a session that sat paused holds more basal energy than plan minutes.
        let basal = await health.restingKcal(start: span.start, end: span.end)
        let resting = EnergyEstimate.resting(basalKcal: basal,
                                             minutes: span.duration / 60,
                                             bodyMassKg: kg,
                                             profile: context.profile)
        guard let kcal = EnergyEstimate.activeKcal(segments, bodyMassKg: kg, resting: resting)
        else { return nil }
        return kcal * EnergyEstimate.actualityFactor(planSec: segments.totalSec,
                                                     actualSec: record.durationSec)
    }

    /// A record written by an older build keeps its pain reports, and they were
    /// "not performed" exactly as a skip was — so reading history has to count
    /// both. Nothing writes `discomfort` any more.
    private static func notPerformed(in record: WorkoutRecord) -> Set<Pattern> {
        (record.skipped ?? []).union(record.discomfort ?? [])
    }

    /// For records that predate duration capture. Reads the session's segments
    /// rather than spelling the sum out again: the two copies that used to
    /// exist disagreed about the cool-down by a minute. Records without a
    /// snapshot get a flat 35 min.
    ///
    /// The whole sum runs in Double because the exercise snapshot comes back
    /// out of the journal file: in Int the products would trap on a
    /// hand-edited load, and the final conversion traps on anything Int cannot
    /// hold.
    private func estimatedDurationSec(for record: WorkoutRecord) -> Int {
        guard let exercises = record.exercises,
              let segments = EnergyEstimate.segments(exercises: exercises,
                                                     skipped: Self.notPerformed(in: record),
                                                     warmupSec: record.warmupSec,
                                                     cooldownSec: record.cooldownSec)
        else { return 35 * 60 }
        let total = segments.totalSec
        guard total.isFinite else { return 35 * 60 }
        return Int(min(max(total, 0), Double(EngineConfig.countMax)))
    }
}
