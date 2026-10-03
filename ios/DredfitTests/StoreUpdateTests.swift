import XCTest
import Observation
import DredfitCore
@testable import Dredfit

/// `update`, the one way into the persisted state from outside AppStore.swift,
/// and `seed`, the UI tests' way in.
@MainActor
final class StoreUpdateTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-update" }

    /// Raised from an observation's `onChange`, which runs synchronously in
    /// the mutation that triggers it — here, on the main actor of the test.
    private final class Flag: @unchecked Sendable { var raised = false }

    private func makeStore() -> AppStore {
        AppStore(storageURL: tempURL, health: HealthSpy(), notifications: QuietNotifications(),
                 widgetSnapshotURL: nil)
    }

    func testAChangeIsOnDiskWhenUpdateReturns() throws {
        let store = makeStore()
        store.update { $0.settings.soundsEnabled = false }
        let onDisk = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: tempURL))
        XCTAssertEqual(onDisk.settings?.soundsEnabled, false)
    }

    /// `update` assigns all four fields back; @Observable does not notify for
    /// a value equal to the one it replaces, and this is what relies on it.
    func testAChangeToOneFieldLeavesReadersOfAnotherAlone() {
        let store = makeStore()
        let records = Flag(), settings = Flag()
        withObservationTracking { _ = store.records } onChange: { records.raised = true }
        withObservationTracking { _ = store.settings } onChange: { settings.raised = true }
        store.update { $0.settings.soundsEnabled = false }
        XCTAssertTrue(settings.raised, "the premise: the tracking sees a change")
        XCTAssertFalse(records.raised)
    }

    #if DEBUG
    func testASeedIsNotWritten() {
        let store = makeStore()
        store.seed { $0.settings.soundsEnabled = false }
        XCTAssertFalse(store.settings.soundsEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "a seed is the state a launch read, written with the first real change")
    }
    #endif

    // MARK: - The import, one update

    func testAnImportOntoAPhoneWithoutTheShareTurnsHealthOff() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy, notifications: QuietNotifications(),
                             widgetSnapshotURL: nil)
        _ = await store.enableHealth()
        let backup = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }
        spy.shareGranted = false
        try store.importBackup(from: backup)
        XCTAssertFalse(store.settings.healthEnabled, "a backup cannot prove this phone granted the share")
        let reread = AppStore(storageURL: tempURL, health: spy, notifications: QuietNotifications(),
                              widgetSnapshotURL: nil)
        XCTAssertFalse(reread.settings.healthEnabled, "and the file says so too")
    }

    func testAnEntryExportedHereStaysExportedThroughTheImport() async throws {
        let spy = HealthSpy()
        let store = AppStore(storageURL: tempURL, health: spy, notifications: QuietNotifications(),
                             widgetSnapshotURL: nil)
        _ = await store.enableHealth()
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 14))
        await store.healthExportTask?.value
        spy.allFail = true
        store.completeWorkout(session: store.nextSession, result: .plan, date: date(2026, 7, 16))
        await store.healthExportTask?.value
        let backup = try store.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }
        spy.allFail = false
        await store.backfillHealth()
        XCTAssertEqual(store.healthBackfillCount, 0, "the premise: the second entry went out after the backup")
        try store.importBackup(from: backup)
        XCTAssertEqual(store.healthBackfillCount, 0, "or the backfill writes it to Health a second time")
    }
}
