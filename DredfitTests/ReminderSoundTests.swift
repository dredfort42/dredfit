//
//  ReminderSoundTests.swift
//  DredfitTests
//
//  The reminder's branded sound file (#84, stage C): written once into
//  Library/Sounds, never rewritten, and any provisioning failure degrades
//  to the stock sound rather than a silent notification.
//

import XCTest
import UserNotifications
@testable import Dredfit

@MainActor
final class ReminderSoundTests: XCTestCase {

    nonisolated(unsafe) private var tempLibrary: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempLibrary = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempLibrary,
                                                withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempLibrary)
        try await super.tearDown()
    }

    /// The first call provisions Sounds/dredfit_reminder_v1.wav with the
    /// generated tone; the second call leaves the existing file untouched —
    /// iOS caches notification sounds by name, so the bytes must never
    /// change under a name that already shipped.
    func testWritesTheFileOnceAndNeverRewritesIt() throws {
        let sound = ReminderSoundFile.notificationSound(library: tempLibrary)
        XCTAssertNotEqual(sound, .default, "the branded sound must be used")

        let file = tempLibrary.appendingPathComponent("Sounds")
            .appendingPathComponent(ReminderSoundFile.name)
        XCTAssertEqual(try Data(contentsOf: file), SignalTone.reminder,
                       "the file carries the generated tone, byte for byte")

        // A marker byte proves the second call does not rewrite the file.
        try Data([0xFF]).write(to: file)
        _ = ReminderSoundFile.notificationSound(library: tempLibrary)
        XCTAssertEqual(try Data(contentsOf: file), Data([0xFF]),
                       "an existing file must be left exactly as it was")
    }

    /// A library root that cannot hold a Sounds directory (the path is a
    /// file) must degrade to the stock sound — never crash, never go silent.
    func testFallsBackToDefaultWhenProvisioningFails() throws {
        let blocked = tempLibrary.appendingPathComponent("blocked", isDirectory: false)
        try Data("not a directory".utf8).write(to: blocked)
        let sound = ReminderSoundFile.notificationSound(library: blocked)
        XCTAssertEqual(sound, .default,
                       "a failed write must fall back to the system sound")
    }

    /// Re-provisioning after a wipe (delete + reinstall) starts clean.
    func testRecreatesTheFileAfterAWipe() throws {
        _ = ReminderSoundFile.notificationSound(library: tempLibrary)
        let sounds = tempLibrary.appendingPathComponent("Sounds")
        try FileManager.default.removeItem(at: sounds)

        let sound = ReminderSoundFile.notificationSound(library: tempLibrary)
        XCTAssertNotEqual(sound, .default)
        let file = sounds.appendingPathComponent(ReminderSoundFile.name)
        XCTAssertEqual(try Data(contentsOf: file), SignalTone.reminder)
    }
}
