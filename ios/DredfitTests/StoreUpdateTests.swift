import XCTest
import Observation
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
}
