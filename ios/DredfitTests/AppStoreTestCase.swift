//
//  Suites that persist an AppStore to a scratch JSON file all need the same
//  two things around every test: a fresh temp URL to write it to, and that
//  file gone again afterward. This base class owns the pair, and a suite
//  overrides `tempURLPrefix` only when it wants its own temp files
//  distinguishable at a glance.
//
//  No subclass count here on purpose: suites get added, and a count kept in
//  a comment goes stale before this file is next touched. Count it when you
//  need it — `grep -rl ': AppStoreTestCase' DredfitTests | wc -l`.
//

import XCTest
@testable import Dredfit

/// Reminders that go nowhere, for a store whose test is not about them.
struct QuietNotifications: NotificationScheduling {
    func requestAuthorization() async -> Bool { false }
    func removePendingRequests(withIdentifiers ids: [String]) {}
    func addReminder(id: String, title: String, body: String,
                     fireDate: DateComponents) {}
}

@MainActor
class AppStoreTestCase: XCTestCase {

    nonisolated(unsafe) var tempURL: URL!

    /// The filename prefix used to build this suite's temp JSON path.
    /// Override to make the file distinguishable at a glance.
    var tempURLPrefix: String { "dredfit-test" }

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tempURLPrefix)-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A store kept away from everything outside the test. The bundle runs
    /// hosted in the signed app, so `AppStore`'s defaults are the real App
    /// Group snapshot, HealthKit and the notification centre.
    func makeStore(storageURL: URL? = nil,
                   health: WorkoutHealthWriting = HealthSpy(),
                   notifications: NotificationScheduling = QuietNotifications(),
                   widgetSnapshotURL: URL? = nil) -> AppStore {
        let url: URL = storageURL ?? tempURL
        return AppStore(storageURL: url, health: health,
                        notifications: notifications,
                        widgetSnapshotURL: widgetSnapshotURL)
    }

    /// A fixed hour-10 date on the given day, for the suites that build
    /// calendar fixtures.
    ///
    /// `guard`/`fatalError` rather than a force unwrap: the three arguments
    /// below are always fixture constants, so this can only fail on a
    /// genuinely invalid fixture date, and a descriptive crash beats the
    /// generic "unexpectedly found nil" trap either way. Not `throws` —
    /// switching would need a `try` at every call site across the suites
    /// that use this helper, all at once.
    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        guard let value = Calendar.current.date(
            from: DateComponents(year: y, month: m, day: d, hour: 10)
        ) else {
            fatalError("invalid calendar fixture: \(y)-\(m)-\(d)")
        }
        return value
    }

    /// The start of the day `n` days before today — the instant a journal
    /// entry must carry for `gapDays` to read exactly `n`.
    ///
    /// MIDNIGHTS, not elapsed seconds: `gapDays` puts both dates through
    /// `startOfDay` (#172), so Monday 23:00 → Tuesday 01:00 reads as one
    /// day, not zero. Across a DST transition an elapsed-seconds seed
    /// (`n × 86_400`) lands in the neighbouring calendar day — in
    /// Europe/Berlin the 25-hour day of 25.10 turns a "14 days ago" seed into
    /// 13 for any run started after 23:00 — which is exactly the kind of
    /// boundary these suites assert on.
    ///
    /// The day's START, not "now minus n days": it is inside the target day
    /// whatever the clock did, and for `n == 0` it is never in the future,
    /// which a same-time-of-day seed would be for half of every day.
    func daysAgo(_ n: Int) throws -> Date {
        let cal = Calendar.current
        return try XCTUnwrap(cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: Date())),
                             "the calendar must be able to step \(n) days back")
    }
}
