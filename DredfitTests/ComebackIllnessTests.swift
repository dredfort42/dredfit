//
//  ComebackIllnessTests.swift
//  DredfitTests
//
//  The app half of the v2.12 comeback wave (issues #127, #128): the accept
//  guard, the sighted decline path and the numbered preview, as the user meets
//  them through AppStore. The "I was sick" lens the file is half-named after
//  was removed in v2.26 — its four tests, and why they went, are at the bottom.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class ComebackIllnessTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-test-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A store whose only workout was `days` ago, at a uniform level — seeded
    /// through the storage file, the same door the real app loads through.
    /// Elapsed seconds, not calendar days: gapDays counts whole 24h periods
    /// (v2.13, spec §7), and a calendar seed across a spring-forward
    /// transition would land an hour short of the exact 90/2-day boundaries.
    private func returned(after days: Int, level: Int = 20) -> AppStore {
        var state = EngineState.initial
        state.counter = 11
        for p in Pattern.allCases { state.levels[p] = level }
        let record = WorkoutRecord(
            sessionNumber: 11,
            date: Date(timeIntervalSinceNow: -Double(days) * 86_400),
            result: .plan,
            totalLevelAfter: level * Pattern.allCases.count)
        struct Seed: Encodable {
            let engineState: EngineState
            let records: [WorkoutRecord]
        }
        do {
            try JSONEncoder().encode(Seed(engineState: state, records: [record]))
                .write(to: tempURL)
        } catch {
            XCTFail("seeding failed: \(error)")
        }
        return AppStore(storageURL: tempURL)
    }

    // MARK: - #128 the reentrancy guard

    func testADoubleAcceptDropsOnlyOnce() {
        let store = returned(after: 35)
        store.acceptComeback()
        let once = store.engineState.levels[.pull]
        store.acceptComeback()   // a double tap, an assistive-tech repeat…
        XCTAssertEqual(store.engineState.levels[.pull], once,
                       "the second call must be a silent no-op")
        XCTAssertEqual(store.engineState.returnRun, 1,
                       "and must not deepen the v2.12 return series either")
    }

    func testAcceptAfterDeclineIsANoOpToo() {
        let store = returned(after: 35)
        store.declineComeback()
        let kept = store.engineState.levels[.pull]
        store.acceptComeback()
        XCTAssertEqual(store.engineState.levels[.pull], kept,
                       "the question was answered — a stray accept changes nothing")
    }

    // MARK: - #127 the sighted decline path

    func testTheFreshStartIsReachableFromNinetyDays() {
        XCTAssertFalse(returned(after: 89).offersFreshStart())
        XCTAssertTrue(returned(after: 90).offersFreshStart())
    }

    func testThePreviewShowsBothOffersAsNumbers() throws {
        let store = returned(after: 90)
        let preview = try XCTUnwrap(store.comebackPreview())
        XCTAssertNotEqual(preview.was, preview.easier,
                          "after a long break the two offers must differ")
        XCTAssertTrue(preview.was.contains("×"), "the old plan is numbers, not adjectives")
        XCTAssertTrue(preview.easier.contains("×"))
    }

    // SNIPPED v2.26 (§37.0): the four tests of the "I was sick" lens.
    // The lens made the plan HEAVIER in 76 cells out of 480 (finding S6-2, P0)
    // — the opposite of what the tap offered — so the mechanism went rather
    // than being fixed. `markIllness`, `illnessSessionsLeft` and the quiet
    // offer in the blind window went with it.
    //
    // The comeback half of this suite is untouched: it never belonged to the
    // lens, and §22.1-§22.3 are not part of this wave.
    //
    // The file keeps its name so the Xcode project does not have to move: the
    // rename would be a change to project.pbxproj for no behaviour at all.
}
