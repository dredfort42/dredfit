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
    private func returned(after days: Int, level: Int = 20) -> AppStore {
        var state = EngineState.initial
        state.counter = 11
        for p in Pattern.allCases { state.levels[p] = level }
        let record = WorkoutRecord(
            sessionNumber: 11,
            date: Calendar.current.date(byAdding: .day, value: -days, to: .now)!,
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

    func testMarkIllnessEasesThePlanWithoutTouchingLevels() {
        let store = returned(after: 5)
        let tierBefore = store.nextSession.exercises.first { $0.pattern == .pull }!.tier
        store.markIllness()
        let tierAfter = store.nextSession.exercises.first { $0.pattern == .pull }!.tier
        XCTAssertEqual(tierAfter, tierBefore - 1, "the plan is one tier gentler")
        XCTAssertEqual(store.engineState.levels[.pull], 20, "the stored level stands")
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
