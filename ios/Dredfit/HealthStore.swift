//
//  Writes workouts, reads only what a calorie needs. Nothing leaves the
//  device — App Privacy stays an honest "Data Not Collected", because reading
//  a weight to divide by it is not collecting it.
//

import Foundation
import HealthKit

/// Where a workout in Health came from, and when. Just enough of an
/// `HKWorkout` to decide whether it is ours.
nonisolated struct WorkoutOrigin: Equatable, Sendable {
    let bundleID: String?
    let start: Date
    let end: Date
}

/// Injectable seam: unit tests substitute a spy.
protocol WorkoutHealthWriting {
    var isAvailable: Bool { get }
    /// True only when the user actually granted the WORKOUT share. Every other
    /// type — energy sharing, and all four reads — may be refused on its own,
    /// and each refusal only costs the feature that needs it.
    func requestAuthorization() async -> Bool
    /// Latest recorded body mass in kilograms, or nil when there is none and
    /// when the read was refused. HealthKit does not distinguish the two.
    func latestBodyMassKg() async -> Double?
    /// Height, age and sex in one snapshot; every field independently absent.
    func profile() async -> BodyProfile
    /// Basal (resting) energy Apple already computed for this interval.
    func restingKcal(start: Date, end: Date) async -> Double?
    /// Workouts recorded by OTHER apps that touch this window.
    func foreignWorkoutIntervals(start: Date, end: Date) async -> [DateInterval]
    /// False on any failure — Health is best-effort. `journalID` identifies
    /// the record this workout came from, and rides along as sample metadata.
    func saveWorkout(start: Date, end: Date, activeKcal: Double?,
                     journalID: String) async -> Bool
}

struct HealthKitWorkoutWriter: WorkoutHealthWriting {
    private let store = HKHealthStore()

    private static let shareTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [.workoutType()]
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }()

    private static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [.workoutType()]
        for id in [HKQuantityTypeIdentifier.bodyMass, .height, .basalEnergyBurned] {
            if let quantity = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(quantity)
            }
        }
        for id in [HKCharacteristicTypeIdentifier.dateOfBirth, .biologicalSex] {
            if let characteristic = HKObjectType.characteristicType(forIdentifier: id) {
                types.insert(characteristic)
            }
        }
        return types
    }()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes,
                                                 read: Self.readTypes)
        } catch {
            return false
        }
        // Only the workout share decides the toggle. A feature that degrades
        // is not a feature that failed: refusing the energy share costs the
        // calories, refusing a read costs some accuracy, and the workout still
        // reaches Health in every one of those cases.
        return store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    func latestBodyMassKg() async -> Double? {
        await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
    }

    func profile() async -> BodyProfile {
        var profile = BodyProfile()
        // Characteristics are synchronous and THROW when unauthorised, which
        // is the same throw as "never filled in" — one catch covers both, and
        // it has to, because HealthKit will not say which happened.
        if let components = try? store.dateOfBirthComponents(),
           let birth = Calendar.current.date(from: components) {
            let years = Calendar.current.dateComponents([.year], from: birth, to: .now).year
            if let years, years >= 0, years < 130 { profile.ageYears = Double(years) }
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .female: profile.sex = .female
            case .male: profile.sex = .male
            case .other: profile.sex = .other
            case .notSet: profile.sex = nil
            @unknown default: profile.sex = nil
            }
        }
        profile.heightCm = await latestQuantity(.height, unit: .meterUnit(with: .centi))
        return profile
    }

    func restingKcal(start: Date, end: Date) async -> Double? {
        guard start < end,
              let type = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
        else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, statistics, _ in
                let sum = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: sum)
            }
            store.execute(query)
        }
    }

    func foreignWorkoutIntervals(start: Date, end: Date) async -> [DateInterval] {
        guard start < end else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, result, _ in
                continuation.resume(returning: result ?? [])
            }
            store.execute(query)
        }
        return Self.foreignIntervals(
            in: samples.map { WorkoutOrigin(bundleID: $0.sourceRevision.source.bundleIdentifier,
                                            start: $0.startDate, end: $0.endDate) },
            excluding: Bundle.main.bundleIdentifier)
    }

    /// OUR OWN workouts are not a second recording of the session. Without this
    /// filter the first export writes a workout, the next run finds it
    /// overlapping, and the app silently forbids itself energy from then on.
    ///
    /// Pure, and separated from the query for exactly that reason: this filter
    /// is the trap in this file, and a guard that can only run on a device with
    /// a paired watch is a guard that never goes red.
    static func foreignIntervals(in origins: [WorkoutOrigin],
                                 excluding mine: String?) -> [DateInterval] {
        origins
            .filter { $0.bundleID != mine }
            .map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
    }

    func saveWorkout(start: Date, end: Date, activeKcal: Double?,
                     journalID: String) async -> Bool {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store,
                                       configuration: configuration,
                                       device: .local())
        do {
            try await builder.beginCollection(at: start)
            if let sample = energySample(activeKcal, start: start, end: end,
                                         journalID: journalID) {
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            // finishWorkout can report "no workout" without throwing — that
            // must read as a failure, or the record is flagged exported while
            // nothing reached Health.
            let workout: HKWorkout? = try await builder.finishWorkout()
            return workout != nil
        } catch {
            return false
        }
    }

    /// `nil` unless there is a number AND permission to write it. Sharing
    /// energy can be refused while sharing workouts is granted, and adding an
    /// unauthorised sample THROWS — which fails the save, and a failed save
    /// stops the whole backfill tail by design. The calories are worth less
    /// than the workout, so they are what gets dropped.
    private func energySample(_ kcal: Double?, start: Date, end: Date,
                              journalID: String) -> HKQuantitySample? {
        guard let kcal, kcal.isFinite, kcal > 0, start < end,
              let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              store.authorizationStatus(for: type) == .sharingAuthorized
        else { return nil }
        // Provenance, not measurement. The version says which revision of the
        // estimate produced this number — without it, a figure written before
        // and after a model change are indistinguishable forever. The external
        // id says which journal entry it came from, which is the only way to
        // answer "why does this one differ" against a person's own history.
        // Both types are dictated by the headers: NSNumber and NSString, and a
        // wrong type throws rather than being ignored.
        let metadata: [String: Any] = [
            HKMetadataKeyAlgorithmVersion: NSNumber(value: EnergyEstimate.modelRevision),
            HKMetadataKeyExternalUUID: journalID,
        ]
        return HKQuantitySample(type: type,
                                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                start: start, end: end, metadata: metadata)
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: sort) { _, result, _ in
                continuation.resume(returning: result ?? [])
            }
            store.execute(query)
        }
        guard let sample = samples.first as? HKQuantitySample else { return nil }
        let value = sample.quantity.doubleValue(for: unit)
        return value.isFinite && value > 0 ? value : nil
    }
}
