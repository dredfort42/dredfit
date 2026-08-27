//
//  Suites that persist an AppStore to a scratch JSON file all needed the
//  same two things around every test: a fresh temp URL to write it to, and
//  that file gone again afterward. Only the filename prefix ever differed
//  between them — this base class owns the pair, and a suite overrides
//  `tempURLPrefix` only when it wants its own temp files distinguishable at
//  a glance.
//
//  No subclass count here on purpose: it was "eighteen" in prose while the
//  real number had already moved to nineteen, and in a wave where several
//  partitions add suites concurrently a comment-borne count goes stale
//  again before this file is next touched. Count it when you need it —
//  `grep -rl ': AppStoreTestCase' DredfitTests | wc -l`.
//

import XCTest

@MainActor
class AppStoreTestCase: XCTestCase {

    nonisolated(unsafe) var tempURL: URL!

    /// The filename prefix used to build this suite's temp JSON path.
    /// Override to make the file distinguishable at a glance; the default
    /// matches what most suites used before this base class existed.
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

    /// A fixed hour-10 date on the given day — shared by the AppStore and
    /// HealthExport suites, which both built calendar fixtures the same way.
    ///
    /// `guard`/`fatalError` rather than a force unwrap: the three arguments
    /// below are always literal constants at the call site, so this can
    /// only fail on a genuinely invalid fixture date, and a descriptive
    /// crash beats the generic "unexpectedly found nil" trap either way.
    /// Not `throws` — every call site across the suites that use this helper
    /// predates that shape, and this base class does not own them all, so
    /// switching would require `try` everywhere at once.
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
    /// MIDNIGHTS, not elapsed seconds. Suites used to subtract `n × 86_400`
    /// and explain it with "gapDays counts whole 24h periods" — true until
    /// #172 (v2.24), which put both dates through `startOfDay` so that
    /// Monday 23:00 → Tuesday 01:00 stopped reading as a zero-day gap. The
    /// note survived that change in more than one suite; the arithmetic
    /// under it did not, independently, more than once. Across a DST
    /// transition an elapsed-seconds seed lands in the neighbouring
    /// calendar day — in Europe/Berlin the 25-hour day of 25.10 turns a
    /// "14 days ago" seed into 13 for any run started after 23:00 — which is
    /// exactly the kind of boundary these suites assert on.
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
