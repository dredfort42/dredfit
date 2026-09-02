import XCTest
@testable import Dredfit

/// One saved workout as the spy recorded it. A struct rather than a tuple
/// because a third member — the calories — put the tuple over the linter's
/// ceiling, and the ceiling is right: `saved[0].2` reads like nothing.
struct SavedWorkout: Equatable {
    let start: Date
    let end: Date
    let kcal: Double?
    let journalID: String
}

/// A Health spy: records saved intervals and the calories that rode along,
/// grants or denies on demand, simulates save failures (all, or from a given
/// 1-based call), answers the four reads with whatever a test needs, and can
/// hold one save mid-flight on `gate` so a test can interleave store mutations
/// with a suspended backfill.
final class HealthSpy: WorkoutHealthWriting, @unchecked Sendable {
    var available = true
    var grant = true
    var allFail = false
    var failFromCall: Int?
    var gate: HealthGate?
    var gateAtCall: Int?
    var saved: [SavedWorkout] = []
    private(set) var callCount = 0
    /// What the device would answer. All four default to "nothing there",
    /// which is also what a refused read looks like — HealthKit does not
    /// distinguish the two, and neither can the app.
    var bodyMassKg: Double?
    var profile = BodyProfile()
    var basalKcal: Double?
    var foreign: [DateInterval] = []
    private(set) var foreignQueries = 0
    private(set) var restingQueries: [DateInterval] = []
    /// Counted because the weight is now read on every activation, and a test
    /// that cannot see the read cannot tell "not asked" from "asked and
    /// ignored". Gated for the same reason `saveWorkout` is: a test that moves
    /// the world BEFORE the read starts proves nothing — the early guard
    /// catches it and the assertion passes for the wrong reason.
    private(set) var massQueries = 0
    var massGate: HealthGate?

    var isAvailable: Bool { available }

    func requestAuthorization() async -> Bool { grant }

    func latestBodyMassKg() async -> Double? {
        massQueries += 1
        await massGate?.wait()
        return bodyMassKg
    }

    func profile() async -> BodyProfile { profile }

    func restingKcal(start: Date, end: Date) async -> Double? {
        restingQueries.append(DateInterval(start: start, end: max(start, end)))
        return basalKcal
    }

    /// Answers like the real reader does — only what touches the window —
    /// so a test cannot pass by handing back an interval nobody asked about.
    func foreignWorkoutIntervals(start: Date, end: Date) async -> [DateInterval] {
        foreignQueries += 1
        let window = DateInterval(start: start, end: max(start, end))
        return foreign.filter { ($0.intersection(with: window)?.duration ?? 0) > 0 }
    }

    func saveWorkout(start: Date, end: Date, activeKcal: Double?,
                     journalID: String) async -> Bool {
        callCount += 1
        if callCount == gateAtCall { await gate?.wait() }
        saved.append(SavedWorkout(start: start, end: end, kcal: activeKcal,
                                  journalID: journalID))
        if start >= end { return false }   // HealthKit rejects such intervals
        if allFail { return false }
        if let f = failFromCall, callCount >= f { return false }
        return true
    }
}

/// A one-shot async gate: `wait()` suspends until `open()`.
@MainActor
final class HealthGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
