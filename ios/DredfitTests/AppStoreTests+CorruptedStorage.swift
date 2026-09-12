//
//  The storage-corruption and freeze tests, moved out of AppStoreTests.swift
//  to keep it under the linter's file and type-body ceilings. Grouped here
//  because they share one shape: a state file that cannot be trusted
//  (garbage bytes, a stale permission, one bad journal entry) must never cost
//  the rest of the journal, or get silently overwritten by the clean state
//  that stood in for it. The code moved unchanged.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Corrupted and unreadable storage
extension AppStoreTests {

    func testCorruptedStorageFallsBackToInitial() throws {
        try Data("{not a json".utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.records.isEmpty, "a corrupted file should give a clean start, not a crash")
        XCTAssertEqual(store.totalProgress, 0)
    }

    func testCorruptedStorageIsQuarantinedNotOverwritten() throws {
        try Data("{not a json".utf8).write(to: tempURL)
        let corruptURL = tempURL.deletingLastPathComponent()
            .appendingPathComponent(tempURL.deletingPathExtension().lastPathComponent + ".corrupt.json")
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        let store = AppStore(storageURL: tempURL)
        store.setSounds(false)   // any persisted mutation
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path),
                      "the unreadable file must be kept aside")
        XCTAssertEqual(try Data(contentsOf: corruptURL), Data("{not a json".utf8),
                       "the quarantined copy must be the original bytes")
    }

    /// Regression: a state file that exists but cannot be read (data
    /// protection before the first unlock, a transient I/O failure) must
    /// never be overwritten by the empty state that replaced it — and must
    /// resume normal persistence once the file becomes readable again.
    func testUnreadableStateFileFreezesPersistenceUntilReloaded() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let seed = AppStore(storageURL: tempURL)
        seed.completeWorkout(session: seed.nextSession, result: .plan)
        let original = try Data(contentsOf: tempURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }

        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.records.isEmpty, "the unreadable launch degrades to empty state")
        XCTAssertFalse(store.shouldShowOnboarding, "an unread journal is not a fresh install")
        XCTAssertTrue(store.journalFrozen)
        XCTAssertThrowsError(try store.exportURL(),
                             "a frozen launch has nothing honest to export")
        store.setSounds(false)   // any mutation that would persist

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        XCTAssertEqual(try Data(contentsOf: tempURL), original,
                       "the journal on disk must survive the frozen launch byte-for-byte")

        // A launch nobody touched yet takes the file the moment it can read
        // it — that is the prewarm-before-first-unlock case this is all for.
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        let untouched = AppStore(storageURL: tempURL)
        XCTAssertTrue(untouched.journalFrozen)
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        untouched.reloadIfNeeded()
        XCTAssertEqual(untouched.records.count, 1, "the journal must load once readable")
        untouched.setSounds(false)
        XCTAssertFalse(AppStore(storageURL: tempURL).settings.soundsEnabled,
                       "persistence must resume after a successful reload")
    }

    func testUsedFrozenLaunchIsNotReplacedByTheFileItCouldNotRead() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let seed = AppStore(storageURL: tempURL)
        for _ in 0..<3 { seed.completeWorkout(session: seed.nextSession, result: .plan) }
        let original = try Data(contentsOf: tempURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }

        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan)
        XCTAssertEqual(store.records.count, 1, "the frozen launch keeps its own work in memory")

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        store.reloadIfNeeded()
        XCTAssertEqual(store.records.count, 1, "a used launch must not be swapped mid-flight")
        XCTAssertEqual(store.engineState.counter, 1,
                       "the counter must stay where the running session expects it")
        XCTAssertEqual(try Data(contentsOf: tempURL), original,
                       "and the real journal on disk stays untouched")
    }

    /// One unreadable journal entry (e.g. written by a newer version)
    /// must not throw away the readable rest of the file.
    func testOneBadRecordDoesNotDropTheJournal() throws {
        let mixed = """
        {"engineState":{"counter":2,
          "levels":["squat",2,"push_h",2,"hinge",2,"pull",2,"push_v",2,"lunge",2,
                    "core_anti_ext",0,"core_rot",0,"calf",0],
          "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",0,"push_v",0,"lunge",0,
                        "core_anti_ext",0,"core_rot",0,"calf",0]},
         "records":[
           {"sessionNumber":1,"date":700000000,"result":"plan","totalLevelAfter":12},
           {"sessionNumber":2,"date":"not-a-date","result":"someday","totalLevelAfter":18}]}
        """
        try Data(mixed.utf8).write(to: tempURL)
        let corruptURL = tempURL.deletingLastPathComponent()
            .appendingPathComponent(tempURL.deletingPathExtension().lastPathComponent + ".corrupt.json")
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.records.count, 1, "the readable record must survive")
        XCTAssertEqual(store.records.first?.sessionNumber, 1)
        // RE-MARKED §41.7 (v3.1, 26.08.2026), class: the test pinned the defect.
        // §40.8's "there is no migration" was reversed, so the claim inverts:
        // an upgrading trainee's work is CARRIED OVER. The number itself is not
        // pinned here — this test is about the journal surviving a bad entry,
        // and `MigrationV2Tests` owns what the rungs land on.
        XCTAssertGreaterThan(store.totalProgress, Engine.totalProgress(.initial),
                             "the v2 rungs migrate, so progress is above a clean start")
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path),
                      "the full original must be kept aside when entries are dropped")
    }
}
