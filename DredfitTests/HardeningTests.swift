//
//  HardeningTests.swift
//  DredfitTests
//
//  v1.6 hardening seams: the day anchor that keeps date-derived UI honest
//  across midnight, the injectable reminder scheduler, and the Live Activity
//  staleDate arithmetic.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class HardeningTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-hardening-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    // MARK: - Day anchor

    /// Crossing midnight while the process stays alive must re-anchor the
    /// UI's "today" — the tab used to stay stuck on yesterday's "completed"
    /// state (with no Start button) until a cold launch.
    func testRefreshDayReanchorsAcrossMidnight() {
        let store = AppStore(storageURL: tempURL)
        store.completeWorkout(session: store.nextSession, result: .plan)
        XCTAssertTrue(store.doneToday)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        store.refreshDay(now: tomorrow)
        XCTAssertFalse(store.doneToday, "the new day must not inherit yesterday's done state")

        // Same-day activations must not move the anchor (no pointless renders).
        let anchor = store.today
        store.refreshDay(now: anchor.addingTimeInterval(60))
        XCTAssertEqual(store.today, anchor, "a same-day refresh must be a no-op")
    }

    // MARK: - Reminders (injectable scheduler)

    private struct ScheduledReminder {
        let id: String
        let weekday: Int
        let hour: Int
        let minute: Int
    }

    private final class NotificationSpy: NotificationScheduling {
        var grant = true
        var scheduled: [ScheduledReminder] = []
        func requestAuthorization() async -> Bool { grant }
        func removePendingRequests(withIdentifiers ids: [String]) {
            scheduled.removeAll { item in ids.contains(item.id) }
        }
        func addWeeklyReminder(id: String, title: String, body: String,
                               weekday: Int, hour: Int, minute: Int) {
            scheduled.append(ScheduledReminder(id: id, weekday: weekday,
                                               hour: hour, minute: minute))
        }
    }

    func testEnablingReminderSchedulesEveryTrainingWeekday() async {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.setReminderTime(hour: 8, minute: 15)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value

        // default rest day is Sunday (1) — six training-day reminders remain
        XCTAssertEqual(spy.scheduled.count, 6)
        XCTAssertFalse(spy.scheduled.contains { $0.weekday == 1 },
                       "no reminder on a rest day")
        XCTAssertTrue(spy.scheduled.allSatisfy { $0.hour == 8 && $0.minute == 15 })
    }

    func testToggleRestDayReschedulesReminders() async {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value
        XCTAssertEqual(spy.scheduled.count, 6)

        store.toggleRestDay(2)   // Monday becomes rest
        XCTAssertEqual(spy.scheduled.count, 5)
        XCTAssertFalse(spy.scheduled.contains { $0.weekday == 2 },
                       "a stale Monday reminder must not survive the toggle")
    }

    func testDisablingReminderClearsEverything() async {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value
        XCTAssertFalse(spy.scheduled.isEmpty)

        store.setReminderEnabled(false)
        XCTAssertTrue(spy.scheduled.isEmpty, "disabling must remove every pending reminder")
    }

    func testReminderDenialFlipsToggleOff() async {
        let spy = NotificationSpy()
        spy.grant = false
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value
        XCTAssertFalse(store.settings.reminderEnabled, "denial must be reflected in the toggle")
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    /// A backup restored onto a device that never granted notifications must
    /// not promise reminders: the import re-runs the authorization flow.
    func testImportWithRemindersRerunsAuthorization() async throws {
        let sourceSpy = NotificationSpy()
        let source = AppStore(storageURL: tempURL, notifications: sourceSpy)
        source.setReminderEnabled(true)
        await source.reminderAuthTask?.value
        let backup = try source.exportURL()
        defer { try? FileManager.default.removeItem(at: backup) }

        let otherURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let spy = NotificationSpy()
        spy.grant = false
        let fresh = AppStore(storageURL: otherURL, notifications: spy)
        try fresh.importBackup(from: backup)
        await fresh.reminderAuthTask?.value

        XCTAssertFalse(fresh.settings.reminderEnabled,
                       "an imported reminderEnabled must not survive a denied authorization")
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    // MARK: - Live Activity staleDate

    func testStaleDateArithmetic() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let restEnd = now.addingTimeInterval(90)
        let rest = RestActivityAttributes.ContentState(
            phase: .rest, title: "t", detail: "d", restEndDate: restEnd)
        XCTAssertEqual(WorkoutActivityController.staleDate(for: rest, now: now),
                       restEnd.addingTimeInterval(60),
                       "rest goes stale a minute after its own countdown ends")

        let work = RestActivityAttributes.ContentState(
            phase: .work, title: "t", detail: "d", restEndDate: nil)
        XCTAssertEqual(WorkoutActivityController.staleDate(for: work, now: now),
                       now.addingTimeInterval(20 * 60),
                       "a work set gets the 20-minute cap")
    }
}
