//
//  What the app reads from Apple Health and writes to it: one workout per
//  journal record, the calories it carries, and the weight they are priced from.
//  Health is best-effort — every answer may be "no" — and nothing here touches
//  the journal: the store flags a record exported only after the save this
//  reports has been confirmed, so a hole in the export is always retriable.
//  Each workout carries its record's id as sample metadata (`journalID`), which
//  is what keeps a re-export from duplicating it.
//

import Foundation
import DredfitCore

struct HealthExporter {
    let health: WorkoutHealthWriting

    /// Read once per backfill run, not once per record: the profile does not
    /// change mid-run, and the foreign-workout sweep is ONE query over the
    /// whole journal rather than one per workout.
    struct EnergyContext {
        var bodyMassKg: Double?
        var profile = BodyProfile.unknown
        var foreign: [DateInterval] = []
    }

    /// Health's newest weight, sanitized; nil when there is none and when the
    /// read was refused — HealthKit does not tell the two apart.
    func latestBodyMass() async -> BodyMassReading? {
        await health.latestBodyMass()
            .flatMap { r in Self.sanitizedBodyMass(r.kg).map { BodyMassReading(kg: $0, date: r.date) } }
    }

    /// Whether a Health sample replaces the number in force: yes when there
    /// is no number, yes when the sample is NEWER than the number's own
    /// statement, no otherwise — the person who typed a weight this morning
    /// is the later source than the scale they last stood on a month ago.
    /// A number with no date (a file from before the date was kept) ranks
    /// below any sample, which is what such files always got.
    static func adopts(reading: BodyMassReading, over kg: Double?, statedAt: Date?) -> Bool {
        guard kg != nil else { return true }
        guard let statedAt else { return true }
        return reading.date > statedAt
    }

    static func sanitizedBodyMass(_ kg: Double) -> Double? {
        guard kg.isFinite, kg > 0 else { return nil }
        return min(kg, 500)
    }

    /// Nothing is read from Health unless a weight makes the reading useful:
    /// without one there is no calorie to compute, and the queries would be
    /// two questions asked for no answer.
    ///
    /// `pending` is read after the profile query, so a workout finished while
    /// it ran is inside the swept window.
    func energyContext(bodyMassKg: Double?, watchRecordsWorkouts: Bool,
                       pending: () -> [WorkoutRecord]) async -> EnergyContext {
        guard let kg = bodyMassKg, !watchRecordsWorkouts else {
            return EnergyContext()
        }
        var context = EnergyContext(bodyMassKg: kg)
        context.profile = await health.profile()
        let spans = pending()
            .map { Self.interval(for: $0, estimate: Self.estimatedDurationSec(for: $0)) }
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

    /// Saves one record's workout; false when Health refused or failed.
    func export(_ record: WorkoutRecord, context: EnergyContext) async -> Bool {
        let span = Self.interval(for: record, estimate: Self.estimatedDurationSec(for: record))
        let kcal = await activeKcal(for: record, span: span, context: context)
        return await health.saveWorkout(start: span.start, end: span.end,
                                        activeKcal: kcal, journalID: record.id)
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
    /// rather than spelling the sum out again, so the estimate cannot drift
    /// from the plan's own length. Records without a snapshot get a flat 35 min.
    ///
    /// The whole sum runs in Double because the exercise snapshot comes back
    /// out of the journal file: in Int the products would trap on a
    /// hand-edited load, and the final conversion traps on anything Int cannot
    /// hold.
    private static func estimatedDurationSec(for record: WorkoutRecord) -> Int {
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
