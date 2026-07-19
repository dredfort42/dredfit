//
//  HealthStore.swift
//  Dredfit
//
//  v1.3: a write-only bridge to Apple Health. Completed workouts become
//  HKWorkout samples (functional strength training, actual duration).
//  Nothing is ever read from Health and nothing leaves the device —
//  App Privacy stays an honest "Data Not Collected".
//

import Foundation
import HealthKit

/// Injectable seam: AppStore talks to Health through this protocol,
/// unit tests substitute a spy.
protocol WorkoutHealthWriting {
    var isAvailable: Bool { get }
    /// Asks for write-only workout authorization. Returns true only when
    /// the user actually granted sharing.
    func requestWriteAuthorization() async -> Bool
    /// Saves one workout interval. Returns false on any failure — the app
    /// treats Health as best-effort and never nags about it.
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
