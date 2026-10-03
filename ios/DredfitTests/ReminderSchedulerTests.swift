import XCTest
@testable import Dredfit

/// The reminder window on its own: what is removed, what is added, and which
/// days are left out.
@MainActor
final class ReminderSchedulerTests: XCTestCase {

    private final class Pending: NotificationScheduling {
        var ids: [String] = []
        var removed: [[String]] = []
        func requestAuthorization() async -> Bool { true }
        func removePendingRequests(withIdentifiers ids: [String]) {
            removed.append(ids)
            self.ids.removeAll { ids.contains($0) }
        }
        func addReminder(id: String, title: String, body: String, fireDate: DateComponents) {
            ids.append(id)
        }
    }

    /// 10:00 today, so a 09:00 slot today has already passed and an 11:00 one
    /// has not.
    private var tenToday: Date {
        get throws {
            try XCTUnwrap(Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now))
        }
    }

    func testTheWholeWindowIsRebuiltFromScratch() throws {
        let pending = Pending()
        pending.ids = ["reminder-wd-3", "reminder-day-5"]
        ReminderScheduler(notifications: pending)
            .reschedule(enabled: true, hour: 11, minute: 0, now: try tenToday, remindsOn: { _ in true })
        XCTAssertEqual(pending.removed.count, 1)
        XCTAssertTrue(try XCTUnwrap(pending.removed.first).contains("reminder-wd-3"),
                      "the old weekly series is still cleared")
        XCTAssertEqual(pending.ids.count, ReminderScheduler.windowDays)
    }

    func testASlotThatAlreadyPassedTodayIsLeftOut() throws {
        let pending = Pending()
        ReminderScheduler(notifications: pending)
            .reschedule(enabled: true, hour: 9, minute: 0, now: try tenToday, remindsOn: { _ in true })
        XCTAssertFalse(pending.ids.contains("reminder-day-0"), "it would never fire, and sit in the list")
        XCTAssertEqual(pending.ids.count, ReminderScheduler.windowDays - 1)
    }

    func testOnlyTheDaysTheRuleAcceptsGetOne() throws {
        let pending = Pending()
        let today = Calendar.current.startOfDay(for: try tenToday)
        ReminderScheduler(notifications: pending)
            .reschedule(enabled: true, hour: 11, minute: 0, now: try tenToday,
                        remindsOn: { !Calendar.current.isDate($0, inSameDayAs: today) })
        XCTAssertFalse(pending.ids.contains("reminder-day-0"))
        XCTAssertTrue(pending.ids.contains("reminder-day-1"))
    }

    func testSwitchedOffItOnlyRemoves() throws {
        let pending = Pending()
        pending.ids = ["reminder-day-0"]
        ReminderScheduler(notifications: pending)
            .reschedule(enabled: false, hour: 11, minute: 0, now: try tenToday, remindsOn: { _ in true })
        XCTAssertTrue(pending.ids.isEmpty)
    }
}
