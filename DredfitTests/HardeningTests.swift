//
//  HardeningTests.swift
//  DredfitTests
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

    /// Regression: crossing midnight while the process stays alive must
    /// re-anchor the UI's "today" — the tab must not stay stuck on
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
        let fireDate: DateComponents
    }

    private final class NotificationSpy: NotificationScheduling {
        var grant = true
        var scheduled: [ScheduledReminder] = []
        func requestAuthorization() async -> Bool { grant }
        func removePendingRequests(withIdentifiers ids: [String]) {
            scheduled.removeAll { item in ids.contains(item.id) }
        }
        func addReminder(id: String, title: String, body: String,
                         fireDate: DateComponents) {
            scheduled.append(ScheduledReminder(id: id, fireDate: fireDate))
        }
    }

    /// A concrete moment `days` from today at the given local time — the
    /// tests pin `now` explicitly so they never depend on when the suite runs.
    private func moment(days: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func slots(_ spy: NotificationSpy, sameDayAs date: Date) -> [ScheduledReminder] {
        let cal = Calendar.current
        return spy.scheduled.filter {
            guard let fire = cal.date(from: $0.fireDate) else { return false }
            return cal.isDate(fire, inSameDayAs: date)
        }
    }

    func testEnablingReminderSchedulesWindowOfTrainingDays() async {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.setReminderTime(hour: 8, minute: 15)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value
        store.rescheduleReminders(now: moment(hour: 6))   // before reminder time

        // default rest days are Sunday (1) and Wednesday (4) since issue #36
        // — any 28-day span holds exactly 4 of each
        XCTAssertEqual(spy.scheduled.count, 20)
        XCTAssertLessThan(spy.scheduled.count, 64, "must stay under the iOS pending cap")
        let cal = Calendar.current
        XCTAssertFalse(spy.scheduled.contains {
            [1, 4].contains(cal.component(.weekday, from: cal.date(from: $0.fireDate)!))
        }, "no reminder on a rest day")
        XCTAssertTrue(spy.scheduled.allSatisfy {
            $0.fireDate.year != nil && $0.fireDate.month != nil && $0.fireDate.day != nil
        }, "every slot is a one-shot for a concrete date, not a weekly series")
        XCTAssertTrue(spy.scheduled.allSatisfy {
            $0.fireDate.hour == 8 && $0.fireDate.minute == 15
        })
    }

    func testMorningWorkoutRemovesTodaysReminder() async {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.toggleRestDay(1)   // every day trains — no rest-day interference
        store.toggleRestDay(4)
        store.setReminderTime(hour: 20, minute: 0)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value

        let morning = moment(hour: 7)
        store.completeWorkout(session: store.nextSession, result: .plan, date: morning)

        XCTAssertTrue(slots(spy, sameDayAs: morning).isEmpty,
                      "a workout done before the reminder time must take today's slot down")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: morning)!
        XCTAssertFalse(slots(spy, sameDayAs: tomorrow).isEmpty,
                       "tomorrow's reminder must survive today's workout")
        XCTAssertEqual(spy.scheduled.count, 27)   // 28-day window minus done today
    }

    /// Trained after the reminder already fired: nothing to cancel, and the
    /// rebuild must not schedule a new slot into today's past.
    func testEveningWorkoutKeepsWindowIntact() async {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.toggleRestDay(1)   // every day trains, as above
        store.toggleRestDay(4)
        store.setReminderTime(hour: 9, minute: 0)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value

        let evening = moment(hour: 21)
        store.completeWorkout(session: store.nextSession, result: .plan, date: evening)

        XCTAssertTrue(slots(spy, sameDayAs: evening).isEmpty,
                      "no slot may be scheduled into today's past")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: evening)!
        XCTAssertFalse(slots(spy, sameDayAs: tomorrow).isEmpty)
    }

    func testToggleRestDayReschedulesReminders() async {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        store.setReminderEnabled(true)
        await store.reminderAuthTask?.value

        store.toggleRestDay(2)   // Monday joins the default Sunday+Wednesday
        store.rescheduleReminders(now: moment(hour: 6))
        XCTAssertEqual(spy.scheduled.count, 16)   // 28 minus 4 each of Sun, Mon, Wed
        let cal = Calendar.current
        XCTAssertFalse(spy.scheduled.contains {
            cal.component(.weekday, from: cal.date(from: $0.fireDate)!) == 2
        }, "a stale Monday reminder must not survive the toggle")
    }

    func testLegacyWeeklySeriesIsClearedOnReschedule() {
        let spy = NotificationSpy()
        let store = AppStore(storageURL: tempURL, notifications: spy)
        spy.scheduled.append(ScheduledReminder(id: "reminder-wd-3", fireDate: DateComponents()))

        store.rescheduleReminders(now: moment(hour: 6))
        XCTAssertTrue(spy.scheduled.isEmpty,
                      "the pre-1.8 weekly series must be removed and nothing added while disabled")
    }

    /// A relaunch rebuilds the window on activation, and a time change moves
    /// every slot — the schedule never drifts from the settings.
    func testWindowSurvivesRestartAndTimeChange() async {
        let first = AppStore(storageURL: tempURL, notifications: NotificationSpy())
        first.setReminderEnabled(true)
        await first.reminderAuthTask?.value

        let spy = NotificationSpy()
        let relaunched = AppStore(storageURL: tempURL, notifications: spy)
        relaunched.rescheduleReminders(now: moment(hour: 6))   // scenePhase .active path
        XCTAssertEqual(spy.scheduled.count, 20, "a restart must rebuild the full window")

        relaunched.setReminderTime(hour: 7, minute: 45)
        relaunched.rescheduleReminders(now: moment(hour: 6))
        XCTAssertTrue(spy.scheduled.allSatisfy {
            $0.fireDate.hour == 7 && $0.fireDate.minute == 45
        }, "a time change must move every slot in the window")
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

    func testFrozenLaunchKeepsThePendingReminderWindow() async throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let spy = NotificationSpy()
        let seed = AppStore(storageURL: tempURL, notifications: spy)
        seed.setReminderEnabled(true)
        await seed.reminderAuthTask?.value
        let pending = spy.scheduled.count
        XCTAssertGreaterThan(pending, 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }
        let frozen = AppStore(storageURL: tempURL, notifications: spy)
        frozen.rescheduleReminders()
        XCTAssertEqual(spy.scheduled.count, pending,
                       "a frozen launch must not clear the reminders it cannot see")

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        frozen.reloadIfNeeded()
        frozen.rescheduleReminders()
        XCTAssertEqual(spy.scheduled.count, pending,
                       "the window is rebuilt once the journal is readable again")
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
