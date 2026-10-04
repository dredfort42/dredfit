//
//  A write that fails must say so, and the next write that works must take
//  the message back.
//
//  The store logs a failed write and carries on, so a person training on a
//  full disk would see nothing until the workout was gone. The writer is made to
//  fail the plain way: its file sits in a directory that does not exist yet,
//  and creating the directory is what "the disk recovered" means. No fake
//  writer — `StateFile.write` is the real one, atomicity included.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SaveFailureTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-savefail" }

    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-missing-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    /// A store whose first write fails, with the failure already asserted:
    /// a store that wrote fine would make every test below vacuous.
    private func failedStore() throws -> AppStore {
        let store = makeStore(storageURL: stateURL)
        XCTAssertNil(store.lastPersistError, "nothing has been written yet")
        store.setSounds(false)
        XCTAssertNotNil(store.lastPersistError, "the fixture must actually fail to write")
        return store
    }

    private func recover() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func test_aFailedWrite_isRecorded() throws {
        let store = try failedStore()
        XCTAssertFalse(store.settings.soundsEnabled,
                       "the change itself stays in memory — only the file missed it")
    }

    func test_theNextSuccessfulWrite_clearsTheError() throws {
        let store = try failedStore()
        try recover()

        store.setSounds(true)

        XCTAssertNil(store.lastPersistError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func test_retryPersist_writesTheStateThatWasKeptInMemory() throws {
        let store = try failedStore()
        try recover()

        store.retryPersist()

        XCTAssertNil(store.lastPersistError, "a working disk takes the retry")
        XCTAssertFalse(AppStore(storageURL: stateURL, widgetSnapshotURL: nil).settings.soundsEnabled,
                       "and what it took is the change the first write missed")
    }

    func test_retryPersist_onAStillFailingDisk_keepsTheError() throws {
        let store = try failedStore()

        store.retryPersist()

        XCTAssertNotNil(store.lastPersistError, "the banner must not claim a save that did not happen")
    }

    func test_activate_retriesAFailedWrite() throws {
        let store = try failedStore()
        try recover()

        store.activate()

        XCTAssertNil(store.lastPersistError, "coming back to the app is the second chance a quiet session gets")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
    }
}
