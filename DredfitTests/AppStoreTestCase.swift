//
//  Eighteen suites persisted an AppStore to a scratch JSON file and needed
//  the same two things around every test: a fresh temp URL to write it to,
//  and that file gone again afterward. Only the filename prefix ever
//  differed between them — this base class owns the pair, and a suite
//  overrides `tempURLPrefix` only when it wants its own temp files
//  distinguishable at a glance.
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
    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 10))!
    }
}
