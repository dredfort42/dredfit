//
//  WorkoutSnapshotTests.swift
//  DredfitTests
//
//  v1.7: the mid-workout snapshot that lets a session survive process
//  death. The invariants under test: it persists across a relaunch, it is
//  only offered while it is honest to offer it (fresh, matching the engine,
//  nothing completed today), and a corrupted snapshot can never take the
//  journal down with it.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class WorkoutSnapshotTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-snapshot-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A mid-workout snapshot the way the flow would write it: real
    /// progress, and a fingerprint of the session the store would offer.
    private func makeSnapshot(for store: AppStore,
                              sessionNumber: Int = 1,
                              savedAt: Date = .now) -> WorkoutSnapshot {
        WorkoutSnapshot(sessionNumber: sessionNumber,
                        exIndex: 4, setIndex: 1,
                        restEndDate: nil, restTotalSec: nil,
                        actuals: [.pushH: 9], skipped: [.coreAntiExt],
                        workoutStart: savedAt.addingTimeInterval(-20 * 60),
                        savedAt: savedAt,
                        fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession))
    }

    // MARK: - The point of the feature

    /// The exact scenario from the audit: iOS evicts the app during a rest,
    /// the user relaunches — five finished exercises must still be there.
    func testSnapshotSurvivesRelaunch() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))

        let relaunched = AppStore(storageURL: tempURL)
        let resumed = relaunched.resumableWorkout()
        XCTAssertNotNil(resumed, "a fresh snapshot must be offered after a cold start")
        XCTAssertEqual(resumed?.exIndex, 4)
        XCTAssertEqual(resumed?.actuals, [.pushH: 9])
        XCTAssertEqual(resumed?.skipped, [.coreAntiExt])
    }

    func testClearedSnapshotStaysClearedAcrossRelaunch() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        store.clearWorkoutSnapshot()

        XCTAssertNil(AppStore(storageURL: tempURL).resumableWorkout(),
                     "a discarded workout must not come back")
    }

    // MARK: - Validity gates

    /// Three hours later it is a different training occasion, not an
    /// interrupted one — "continue" would be a lie about what the session was.
    func testStaleSnapshotIsNotOffered() {
        let store = AppStore(storageURL: tempURL)
        let saved = Date.now
        store.saveWorkoutSnapshot(makeSnapshot(for: store, savedAt: saved))

        let justInside = saved.addingTimeInterval(AppStore.workoutResumeWindow - 60)
        XCTAssertNotNil(store.resumableWorkout(now: justInside))

        let justPast = saved.addingTimeInterval(AppStore.workoutResumeWindow + 60)
        XCTAssertNil(store.resumableWorkout(now: justPast),
                     "the resume offer must expire with the occasion")
    }

    /// Completing the workout is the snapshot's natural end: the engine has
    /// moved on, and the stale snapshot must be cleared, not just outvoted.
    func testCompletingTheWorkoutClearsTheSnapshot() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        store.completeWorkout(session: store.nextSession, result: .plan)

        XCTAssertNil(store.pendingWorkout, "completion must clear the snapshot")
        XCTAssertNil(AppStore(storageURL: tempURL).pendingWorkout,
                     "the cleared state must be the persisted one")
    }

    /// A snapshot whose session no longer matches the engine (feedback was
    /// applied, progress was reset) must never resume into the wrong workout.
    func testMismatchedSessionNumberIsNotOffered() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store, sessionNumber: 5))
        XCTAssertNil(store.resumableWorkout(),
                     "session 5 does not belong to a counter at 0")
    }

    /// Н-1: the session number is not identity. Toggling the pull-up bar
    /// regenerates a different session under the same number — the
    /// fingerprint must catch it, or the snapshot's indices, actuals and
    /// skips would land on a different exercise list.
    func testBarToggleInvalidatesTheSnapshot() {
        let store = AppStore(storageURL: tempURL)
        // Session 2 (odd counter) is the one the bar module rewrites.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        store.completeWorkout(session: store.nextSession, result: .plan, date: yesterday)
        store.saveWorkoutSnapshot(makeSnapshot(for: store, sessionNumber: 2))
        XCTAssertNotNil(store.resumableWorkout(), "sanity: the snapshot is valid as saved")

        store.setHasBar(true)
        XCTAssertNil(store.resumableWorkout(),
                     "the bar toggle regenerated session 2 — the old snapshot must not resume into it")
    }

    /// Н-1, same guard, other entrance: an accepted comeback lowers levels
    /// without moving the counter, so the regenerated session differs too.
    func testAcceptedComebackInvalidatesTheSnapshot() {
        let store = AppStore(storageURL: tempURL)
        let longAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        // A real level to drop from, recorded a month back.
        store.completeWorkout(session: store.nextSession, result: .more, date: longAgo)
        store.saveWorkoutSnapshot(makeSnapshot(for: store, sessionNumber: 2))
        XCTAssertNotNil(store.resumableWorkout(), "sanity: the snapshot is valid as saved")

        store.acceptComeback()
        XCTAssertNil(store.resumableWorkout(),
                     "a comeback regenerates the plan — the old snapshot must not resume into it")
    }

    /// Н-2: a snapshot from the moment the warm-up ended — first set
    /// untouched, nothing recorded — offers nothing. The honest launch for
    /// it is the plain Start, warm-up included.
    func testSnapshotWithNoProgressIsNotOffered() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 0, setIndex: 0,
            workoutStart: .now, savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession)))
        XCTAssertNil(store.resumableWorkout(),
                     "there is nothing to continue — the card must not show")
    }

    /// The mirror case: position zero but mid-rest means a set IS behind
    /// (the flow advances indices only after the rest) — that is progress.
    func testFirstSetRestSnapshotIsOffered() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 0, setIndex: 0,
            restEndDate: .now.addingTimeInterval(45), restTotalSec: 60,
            workoutStart: .now.addingTimeInterval(-5 * 60), savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession)))
        XCTAssertNotNil(store.resumableWorkout(),
                        "a set was completed — this interruption is worth offering back")
    }

    /// Н-3: reaching the rating screen is progress in itself — the snapshot
    /// stays resumable (and the flow restores straight onto the rating).
    func testFeedbackSnapshotIsOffered() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 5, setIndex: 2,
            actuals: [.pushH: 9],
            workoutStart: .now.addingTimeInterval(-30 * 60), savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession),
            atFeedback: true))
        let resumed = store.resumableWorkout()
        XCTAssertNotNil(resumed)
        XCTAssertEqual(resumed?.atFeedback, true,
                       "the restore path needs the flag to land on the rating, not the last set")
    }

    /// A pre-fingerprint snapshot (older build) has nil where the print
    /// should be — it must fail closed, not resume unverified.
    func testSnapshotWithoutFingerprintIsNotOffered() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 4, setIndex: 1,
            actuals: [.pushH: 9],
            workoutStart: .now, savedAt: .now))
        XCTAssertNil(store.resumableWorkout(),
                     "no fingerprint means no proof the session still matches")
    }

    func testResetProgressDropsTheSnapshot() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        store.resetProgress()
        XCTAssertNil(store.pendingWorkout,
                     "restarted session numbers must not collide with an old snapshot")
    }

    /// An imported history is another device's (or another day's) state — a
    /// half-finished workout does not travel with it.
    func testImportedBackupCarriesNoSnapshot() throws {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        let backup = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        try store.importBackup(from: backup)
        XCTAssertNil(store.pendingWorkout)
    }

    // MARK: - Robustness

    /// A snapshot written by a newer version (or plain corruption) must
    /// degrade to "nothing to resume" — never quarantine the whole journal.
    func testCorruptSnapshotDoesNotCostTheJournal() throws {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: tempURL)) as? [String: Any])
        json["pendingWorkout"] = ["unexpected": "shape"]
        try JSONSerialization.data(withJSONObject: json)
            .write(to: tempURL, options: .atomic)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.records.count, 1,
                       "the journal must survive an unreadable snapshot")
        XCTAssertNil(reloaded.pendingWorkout)
    }
}
