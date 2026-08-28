import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class HealthExportTests: AppStoreTestCase {

    /// Runs `backfillHealth` in a child task and returns once the spy's gated
    /// save is actually in flight (suspended inside the gate).
    private func startBackfillAndWaitForGatedSave(
        _ store: AppStore, _ spy: HealthSpy) async -> Task<Void, Never> {
        let backfill = Task { await store.backfillHealth() }
        var spins = 0
        while spy.callCount < (spy.gateAtCall ?? 0) && spins < 10_000 {
            spins += 1
            await Task.yield()
        }
        XCTAssertEqual(spy.callCount, spy.gateAtCall, "the gated save must be in flight")
        return backfill
    }

    /// A record written before durations were stored has none, so the export
    /// estimates one — and that estimate carried the warm-up and cool-down as
    /// literal 5 and 3 while the engine had moved the cool-down to 4. Nothing
    /// pinned the number, so the minute went to Apple Health unnoticed. This
    /// reads both ends from `EngineConfig`, so a copy re-introduced here
    /// disagrees with the engine and fails.
    func testAnEstimatedDurationUsesTheEngineSBlockLengths() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()

        let session = store.nextSession
        store.completeWorkout(session: session, result: .plan)   // no durationSec
        await store.healthExportTask?.value

        XCTAssertEqual(spy.saved.count, 1, "the workout was exported")
        let saved = spy.saved[0].end.timeIntervalSince(spy.saved[0].start)

        var work = 0.0
        for ex in session.exercises {
            let sides: Double = ex.perSide ? 2 : 1
            let perSet = ex.unit == .reps
                ? Double(ex.load) * sides * 2.5
                : Double(ex.load) * sides
            work += Double(ex.sets) * perSet
                + (Double(ex.sets) - 1) * Double(ex.restSetSec)
                + Double(ex.restExerciseSec)
        }
        let blocks = Double((EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60)
        XCTAssertEqual(saved, (work + blocks).rounded(.down), accuracy: 1,
                       "the estimate must reserve the engine's own warm-up and cool-down")
    }

    /// A failed save must not flag the workout exported — it stays retriable
    /// until a later export succeeds.
    func testHealthFailedSaveKeepsWorkoutRetriable() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()
        spy.allFail = true
        store.completeWorkout(session: store.nextSession, result: .plan, durationSec: 30 * 60)
        await store.healthExportTask?.value
        XCTAssertEqual(spy.saved.count, 1, "the save was attempted")
        XCTAssertEqual(store.healthBackfillCount, 1,
                       "a failed save must not mark the workout exported")
        // the retry succeeds and clears the backlog
        spy.allFail = false
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "the retry exported the missed workout")
        XCTAssertEqual(spy.saved.count, 2)
    }

    /// Regression: a failed live export of workout N followed by a successful
    /// workout N+1 must not advance the high-water mark past N, which would
    /// leave workout N's failed export stuck with no chance to retry.
    func testHealthLaterSuccessDoesNotLoseEarlierFailedExport() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        _ = await store.enableHealth()

        spy.allFail = true
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: date(2026, 7, 14))
        await store.healthExportTask?.value
        XCTAssertEqual(store.healthBackfillCount, 1, "workout 1 stays pending")

        spy.allFail = false
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: date(2026, 7, 16))
        await store.healthExportTask?.value
        XCTAssertEqual(store.healthBackfillCount, 0,
                       "the next workout's export must retry the failed one first")
        XCTAssertEqual(spy.saved.count, 3, "one failed attempt plus both real exports")
        XCTAssertEqual(spy.saved[1].end, date(2026, 7, 14),
                       "the older workout exports before the newer one")
        XCTAssertEqual(spy.saved[2].end, date(2026, 7, 16))
    }

    func testResetProgressKeepsRecordIdentityAndHealthStateSound() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 10))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 12))
        _ = await store.enableHealth()
        await store.backfillHealth()
        XCTAssertEqual(spy.saved.count, 2)

        store.resetProgress()
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))
        XCTAssertEqual(store.records.last?.sessionNumber, 1,
                       "after the reset the journal reuses session numbers")
        XCTAssertEqual(Set(store.records.map(\.id)).count, store.records.count,
                       "record ids must stay unique across a reset")

        await store.healthExportTask?.value
        XCTAssertEqual(store.healthBackfillCount, 0)
        XCTAssertEqual(spy.saved.count, 3, "only the new workout exports — no duplicates")
        // "Only new ones" after the reset must not unmark or re-export anything
        store.skipHealthBackfill()
        await store.backfillHealth()
        XCTAssertEqual(spy.saved.count, 3, "skip must never re-export handled workouts")
    }

    func testHealthBackfillStopsAtFirstFailure() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 15))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))
        _ = await store.enableHealth()

        spy.failFromCall = 2               // session 1 exports, session 2 fails
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 2,
                       "backfill must stop at the first failure, not mark the tail exported")

        spy.failFromCall = nil             // resume
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "the resumed backfill exports the rest")
    }

    /// Regression: replacing the journal (importBackup) while a backfill is
    /// suspended inside a save must not flag, by stale index, a record that
    /// was never exported — the flag must land by record identity or not at
    /// all.
    func testImportDuringInFlightBackfillDoesNotMisflagByStaleIndex() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        for day in [10, 12, 14, 16] {
            store.completeWorkout(session: store.nextSession, result: .plan,
                                  date: date(2026, 7, day))
        }
        _ = await store.enableHealth()

        // A donor backup: three records, Health never enabled there. An
        // unrelated journal inherits neither the mark nor any flags
        // (issue #103), so all three donor records must stay pending — and
        // in particular the save in flight must not flag any of them by its
        // stale index.
        let donorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-donor-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: donorURL) }
        let donor = AppStore(storageURL: donorURL)
        for day in 1...3 {
            donor.completeWorkout(session: donor.nextSession, result: .plan,
                                  date: date(2026, 7, day))
        }
        let backup = try donor.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        // Hold the third save mid-flight (the loop sits past index 2), then
        // replace the journal under it and let the save finish.
        let gate = HealthGate()
        spy.gate = gate
        spy.gateAtCall = 3
        let backfill = await startBackfillAndWaitForGatedSave(store, spy)
        try store.importBackup(from: backup)
        gate.open()
        await backfill.value

        XCTAssertEqual(store.records.count, 3, "the imported journal must be intact")
        XCTAssertEqual(spy.saved.count, 3, "no further exports against the replaced journal")
        XCTAssertNotEqual(store.records.last?.healthExported, true,
                          "a record that was never saved must not be flagged exported")
        XCTAssertEqual(store.healthBackfillCount, 3,
                       "every imported workout stays pending for a real export")
    }

    func testDisablingHealthStopsAnInFlightBackfill() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        for day in [10, 12, 14] {
            store.completeWorkout(session: store.nextSession, result: .plan,
                                  date: date(2026, 7, day))
        }
        _ = await store.enableHealth()

        let gate = HealthGate()
        spy.gate = gate
        spy.gateAtCall = 2
        let backfill = await startBackfillAndWaitForGatedSave(store, spy)
        store.disableHealth()
        gate.open()
        await backfill.value

        // The save already in flight lands (it did reach Health) — but the
        // third record must not follow it after the toggle went off.
        XCTAssertEqual(spy.saved.count, 2, "no exports after the toggle went off")
        XCTAssertEqual(store.healthBackfillCount, 1, "the tail stays pending for a re-enable")
    }

    /// A record with a corrupt (negative) duration must not poison the
    /// backfill — it must still export, and its interval must still run
    /// forward in time.
    func testNegativeDurationDoesNotPoisonHealthBackfill() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: -20 * 60, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .plan,
                              date: date(2026, 7, 16))
        _ = await store.enableHealth()
        await store.backfillHealth()

        XCTAssertEqual(store.healthBackfillCount, 0, "both records must export")
        XCTAssertTrue(spy.saved.allSatisfy { $0.start < $0.end },
                      "every exported interval must move forward")
    }

    /// Importing an older backup of the SAME journal (no Health mark) must
    /// not move the mark backwards — otherwise re-enabling would re-export
    /// samples already in Health, which nothing here can notice: the workout
    /// read exists to spot ANOTHER app's session and filters our own out.
    /// Same lineage means shared record ids, so the fixture's dates are the
    /// journal's real dates — a real old backup keeps them.
    func testImportKeepsHealthMarkMonotonic() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .more, date: date(2026, 7, 16))
        _ = await store.enableHealth()
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "both workouts start out exported")

        // a backup of the same two workouts predating Health support — no
        // healthExportedThrough, no per-record flags, same dates
        let t1 = date(2026, 7, 14).timeIntervalSinceReferenceDate
        let t2 = date(2026, 7, 16).timeIntervalSinceReferenceDate
        let old = """
        {"engineState":{"counter":2,
          "levels":["squat",2,"push_h",2,"hinge",2,"pull",4,"push_v",2,"lunge",2,
                    "core_anti_ext",1,"core_rot",1,"calf",1],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[
           {"sessionNumber":1,"date":\(t1),"result":"plan","totalLevelAfter":12},
           {"sessionNumber":2,"date":\(t2),"result":"more","totalLevelAfter":18}],
         "settings":{"restWeekdays":[1],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-oldbackup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try Data(old.utf8).write(to: backupURL)
        try store.importBackup(from: backupURL)

        XCTAssertEqual(store.healthBackfillCount, 0,
                       "an old backup must not reset the mark and re-export handled workouts")
    }

    /// An unrelated journal (no shared record ids) must not inherit this
    /// device's Health mark — inheriting it stamped the foreign workouts
    /// "already exported" and hid them from the backfill forever (issue #103).
    func testUnrelatedImportDoesNotInheritTheHealthMark() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))
        _ = await store.enableHealth()
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "this journal starts fully exported")

        // A donor journal from another life: same session numbers, different
        // dates, Health never enabled there.
        let donorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-foreign-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: donorURL) }
        let donor = AppStore(storageURL: donorURL)
        donor.completeWorkout(session: donor.nextSession, result: .plan, date: date(2026, 6, 1))
        donor.completeWorkout(session: donor.nextSession, result: .plan, date: date(2026, 6, 3))
        let backup = try donor.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        try store.importBackup(from: backup)
        XCTAssertEqual(store.healthBackfillCount, 2,
                       "no foreign workout may be silently excluded from Health")
        // The Health toggle travelled with the donor's settings (off there) —
        // enabling on this device must find both workouts waiting.
        _ = await store.enableHealth()
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0)
        XCTAssertEqual(spy.saved.count, 4, "both foreign workouts really export")
    }

    /// An unrelated journal that carries its own flags keeps them as they
    /// are — the flags are that journal's truth, not this device's.
    func testUnrelatedImportRespectsItsOwnFlags() async throws {
        let donorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-flagged-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: donorURL) }
        let donorSpy = HealthSpy()
        let donor = AppStore(storageURL: donorURL, health: donorSpy)
        donor.completeWorkout(session: donor.nextSession, result: .plan, date: date(2026, 6, 1))
        _ = await donor.enableHealth()
        await donor.backfillHealth()
        donor.completeWorkout(session: donor.nextSession, result: .plan, date: date(2026, 6, 3))
        await donor.healthExportTask?.value
        XCTAssertEqual(donor.healthBackfillCount, 0, "the donor is fully exported")
        let backup = try donor.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        try store.importBackup(from: backup)
        XCTAssertEqual(store.healthBackfillCount, 0,
                       "the donor's own flags say everything is exported — believe them")
        await store.backfillHealth()
        XCTAssertTrue(spy.saved.isEmpty, "nothing may re-export on this device")
    }

    /// After a reset the journal restarts its session numbers under the old
    /// high mark — a reload must not stamp the new session 1 "exported"
    /// (issue #103: the legacy migration now runs only on flag-free files).
    func testResetThenReloadDoesNotStampTheNewJournal() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 10))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 12))
        _ = await store.enableHealth()
        await store.backfillHealth()
        store.disableHealth()

        store.resetProgress()
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))
        XCTAssertEqual(store.records.last?.sessionNumber, 1)
        XCTAssertNil(store.records.last?.healthExported, "not exported: Health is off")

        let reloaded = AppStore(storageURL: tempURL, health: HealthSpy())
        XCTAssertNil(reloaded.records.last?.healthExported,
                     "a reload must not stamp the post-reset session 1 by the old mark")
        XCTAssertEqual(reloaded.healthBackfillCount, 1,
                       "the new workout stays visible to a future backfill")
    }

    func testHealthDenialLeavesToggleOff() async {
        let spy = HealthSpy()
        spy.grant = false
        let store = AppStore(storageURL: tempURL, health: spy)
        let granted = await store.enableHealth()
        XCTAssertFalse(granted)
        XCTAssertFalse(store.settings.healthEnabled, "denial must leave the toggle off")
    }

    func testHealthBackfillExportsOnceAndNeverDuplicates() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))

        let granted = await store.enableHealth()
        XCTAssertTrue(granted)
        XCTAssertEqual(store.healthBackfillCount, 2)
        await store.backfillHealth()
        XCTAssertEqual(spy.saved.count, 2, "the backfill must export both past workouts")
        XCTAssertEqual(store.healthBackfillCount, 0)

        // toggling off and on again must not re-export old workouts
        store.disableHealth()
        _ = await store.enableHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "re-enabling must not duplicate")

        // estimate fallback: records without a stored duration — the interval
        // still ends at the record date and has a positive length
        let last = spy.saved.last!
        XCTAssertEqual(last.end, date(2026, 7, 16))
        XCTAssertGreaterThan(last.end.timeIntervalSince(last.start), 10 * 60)
    }

    func testHealthSkipBackfillMarksHistoryHandled() async {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy)
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        _ = await store.enableHealth()
        store.skipHealthBackfill()
        XCTAssertEqual(store.healthBackfillCount, 0)
        XCTAssertTrue(spy.saved.isEmpty, "\"only new ones\" must not export the past")

        // a new workout with a captured duration exports automatically
        store.completeWorkout(session: store.nextSession, result: .plan,
                              durationSec: 40 * 60, date: date(2026, 7, 16))
        await store.healthExportTask?.value
        XCTAssertEqual(spy.saved.count, 1, "a completed workout must land in Health")
        XCTAssertEqual(spy.saved[0].end.timeIntervalSince(spy.saved[0].start),
                       40 * 60, accuracy: 1, "the actual duration must be used")
    }

    /// Regression: the loop SELECTS an unexported record and FLAGS one by id,
    /// and the two predicates have to agree. Two records sharing an `id`
    /// (`sessionNumber` restarted by `resetProgress`, the same `date` to the
    /// double) sent every flag to the first of the pair; the second stayed
    /// unexported, was picked again, and the backfill wrote a duplicate
    /// HKWorkout per turn without ever terminating.
    ///
    /// `failFromCall` is the fail-safe, not the subject: without it the old
    /// code hangs the suite instead of failing it, and a test that can only
    /// report by timing out reports nothing (CI runs with
    /// `-default-test-execution-time-allowance`).
    func testDuplicateJournalIDsDoNotLoopTheBackfill() async {
        let spy = HealthSpy()
        spy.failFromCall = 5
        let store = AppStore(storageURL: tempURL, health: spy)
        // Only a hand-edited journal gets here — which is the input every
        // decoder in this project is written against.
        let stamp = date(2026, 7, 10)
        store.records = [
            WorkoutRecord(sessionNumber: 1, date: stamp, result: .plan),
            WorkoutRecord(sessionNumber: 1, date: stamp, result: .plan),
        ]
        XCTAssertEqual(store.records[0].id, store.records[1].id,
                       "the fixture is only a fixture if the ids really collide")
        _ = await store.enableHealth()

        await store.backfillHealth()

        XCTAssertEqual(spy.saved.count, 2, "one export per record, and then it stops")
        XCTAssertEqual(store.healthBackfillCount, 0, "both records end up flagged")
    }
}
