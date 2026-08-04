//
//  HealthStore.swift
//  Dredfit
//
//  Write-only. Nothing is ever read from Health and nothing leaves the
//  device — App Privacy stays an honest "Data Not Collected".
//

import Foundation
import HealthKit

/// Injectable seam: unit tests substitute a spy.
protocol WorkoutHealthWriting {
    var isAvailable: Bool { get }
    /// True only when the user actually granted sharing.
    func requestWriteAuthorization() async -> Bool
    /// False on any failure — Health is best-effort.
    func saveWorkout(start: Date, end: Date) async -> Bool
}

struct HealthKitWorkoutWriter: WorkoutHealthWriting {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestWriteAuthorization() async -> Bool {
        do {
            try await store.requestAuthorization(toShare: [.workoutType()], read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    func saveWorkout(start: Date, end: Date) async -> Bool {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store,
                                       configuration: configuration,
                                       device: .local())
        do {
            try await builder.beginCollection(at: start)
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
}
