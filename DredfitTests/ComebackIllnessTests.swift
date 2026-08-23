//
//  ComebackIllnessTests.swift
//  DredfitTests
//
//  The app half of the v2.12 comeback wave (issues #127, #128, #133): the
//  accept guard, the sighted decline path, and the "I was sick" lens as the
//  user meets them through AppStore.
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

    // MARK: - #133 the illness lens through the app

    /// v2.25 (spec §36.6): RE-MARKED, and the old mark was the bug. The lens
    /// used to show every level one tier easier; that made the plan HEAVIER in
    /// 84 cells of 480 (audit 20.08, P0-6), because rep continuity read a
    /// phantom field on the statics and the v2.21 ladders of tier 3 sit above
    /// those of tier 4 — hinge L24, `3×4` became `3×5 per leg`. The one tap a
    /// person has for "I need something lighter right now" did the opposite of
    /// its promise.
    ///
    /// The lens takes SETS off now — to half the band, rounded up — and leaves
    /// the level, the variation and the dose per set exactly where they are.
    /// Fewer sets of the same thing cannot be heavier by construction, so the
    /// promise holds with no cell to check.
    func testMarkIllnessEasesThePlanWithoutTouchingLevels() throws {
        let store = returned(after: 5)
        let before = try XCTUnwrap(store.nextSession.exercises.first { $0.pattern == .pull })
        store.markIllness()
        let after = try XCTUnwrap(store.nextSession.exercises.first { $0.pattern == .pull })
        XCTAssertEqual(after.tier, before.tier, "the lens moves volume, not the variation")
        XCTAssertEqual(after.load, before.load, "nor the dose per set")
        XCTAssertLessThan(after.sets, before.sets, "the plan is gentler by sets")
        XCTAssertEqual(store.engineState.levels[.pull], 20, "the stored level stands")
        XCTAssertEqual(store.engineState.cutOf(.pull), 0,
                       "the lens builds the plan's VIEW — it stores no cut of its own")
        XCTAssertEqual(store.illnessSessionsLeft, EngineConfig.illnessSessions)
    }

    func testTheLensSurvivesAReload() {
        let store = returned(after: 5)
        store.markIllness()
        store.completeWorkout(session: store.nextSession, result: .plan)
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.illnessSessionsLeft, EngineConfig.illnessSessions - 1,
                       "the countdown persists across launches")
    }

    func testTheQuietOfferLivesExactlyInTheBlindWindow() {
        XCTAssertFalse(returned(after: 0).shouldOfferIllnessTap(), "trained today")
        XCTAssertFalse(returned(after: 1).shouldOfferIllnessTap(), "an ordinary rest day")
        XCTAssertTrue(returned(after: 2).shouldOfferIllnessTap())
        XCTAssertTrue(returned(after: 13).shouldOfferIllnessTap())
        XCTAssertFalse(returned(after: 14).shouldOfferIllnessTap(),
                       "from fourteen days the comeback card carries the tap")
        let tapped = returned(after: 5)
        tapped.markIllness()
        XCTAssertFalse(tapped.shouldOfferIllnessTap(), "the lens is on — the offer is spent")
    }

    /// The card's sick path per spec §22.4: the comeback lands first, the
    /// lens goes on top of the landing.
    func testSickOnTheCardComposesComebackAndLens() {
        let store = returned(after: 35)
        store.acceptComeback()
        store.markIllness()
        XCTAssertLessThan(store.engineState.levels[.pull] ?? 99, 20, "the landing happened")
        XCTAssertEqual(store.illnessSessionsLeft, EngineConfig.illnessSessions)
        XCTAssertFalse(store.shouldOfferComeback(), "the question is closed")
    }
}
