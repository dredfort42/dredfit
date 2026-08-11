//
//  WorkoutSnapshotTests.swift
//  DredfitTests
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

    func testSnapshotWithNoProgressIsNotOffered() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 0, setIndex: 0,
            workoutStart: .now, savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession)))
        XCTAssertNil(store.resumableWorkout(),
                     "there is nothing to continue — the card must not show")
    }

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

    /// A report of pain is progress worth offering back on its own — the
    /// workout must not come back with the report lost.
    func testDiscomfortAloneMakesASnapshotResumable() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 0, setIndex: 0,
            discomfort: [.calf],
            workoutStart: .now.addingTimeInterval(-5 * 60), savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession)))
        let resumed = store.resumableWorkout()
        XCTAssertNotNil(resumed, "something was reported — the card must show")
        XCTAssertEqual(resumed?.discomfort, [.calf])
    }

    /// A snapshot written before the field existed still decodes.
    func testSnapshotWithoutTheDiscomfortFieldStillResumes() throws {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        let raw = try XCTUnwrap(String(data: try Data(contentsOf: tempURL), encoding: .utf8))
        XCTAssertFalse(raw.contains("\"discomfort\""),
                       "an empty report must not be written at all")
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertNotNil(reloaded.resumableWorkout())
        XCTAssertNil(reloaded.resumableWorkout()?.discomfort)
    }

    /// A hold request is progress worth offering back on its own — the
    /// workout must not come back with the request lost.
    func testAPinAloneMakesASnapshotResumable() {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: 1, exIndex: 0, setIndex: 0,
            pinned: [.squat],
            workoutStart: .now.addingTimeInterval(-5 * 60), savedAt: .now,
            fingerprint: WorkoutSnapshot.fingerprint(of: store.nextSession)))
        let resumed = store.resumableWorkout()
        XCTAssertNotNil(resumed, "something was asked for — the card must show")
        XCTAssertEqual(resumed?.pinned, [.squat])
    }

    /// A snapshot written before the pinned field existed still decodes —
    /// and an empty set is never written at all.
    func testSnapshotWithoutThePinnedFieldStillResumes() throws {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        let raw = try XCTUnwrap(String(data: try Data(contentsOf: tempURL), encoding: .utf8))
        XCTAssertFalse(raw.contains("\"pinned\""),
                       "an empty request must not be written at all")
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertNotNil(reloaded.resumableWorkout())
        XCTAssertNil(reloaded.resumableWorkout()?.pinned)
    }

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

    func testImportedBackupCarriesNoSnapshot() throws {
        let store = AppStore(storageURL: tempURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        let backup = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        try store.importBackup(from: backup)
        XCTAssertNil(store.pendingWorkout)
    }

    // MARK: - Cost of writing so often

    func testSnapshotWritesDoNotTouchTheWidget() throws {
        let widgetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: widgetURL) }
        let store = AppStore(storageURL: tempURL, widgetSnapshotURL: widgetURL)

        // The init already wrote one; clear it and watch who writes next.
        try FileManager.default.removeItem(at: widgetURL)
        store.saveWorkoutSnapshot(makeSnapshot(for: store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: widgetURL.path),
                       "a mid-workout snapshot must not rewrite the widget snapshot")
        store.clearWorkoutSnapshot()
        XCTAssertFalse(FileManager.default.fileExists(atPath: widgetURL.path),
                       "dropping a snapshot changes nothing the widget shows")

        store.completeWorkout(session: store.nextSession, result: .plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: widgetURL.path),
                      "completing the workout must still reach the widget")
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
