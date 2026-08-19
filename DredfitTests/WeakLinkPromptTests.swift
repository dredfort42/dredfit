//
//  WeakLinkPromptTests.swift
//  DredfitTests
//
//  v2.15 (spec §26.3, #135): the movement the trainee never names. Someone who
//  only knows the one-tap gesture rates "tough" whenever the pushes come up;
//  because the pushes are in most sessions, the model reads that as "the whole
//  programme is too hard" and nine weeks later the programme is gone — while
//  the movement that actually hurts is still in every plan. The journal has
//  seen the correlation all along; this asks one question about it.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class WeakLinkPromptTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-weaklink-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A store whose journal is `count` sessions, each one an unnamed "tough"
    /// when it carried `culprit` and "on plan" otherwise — the naive persona.
    private func naiveStore(sessions count: Int, culprit: Pattern = .pushV) -> AppStore {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<count {
            let session = store.nextSession
            let carries = session.exercises.contains { $0.pattern == culprit }
            _ = store.completeWorkout(session: session, result: carries ? .less : .plan)
        }
        return store
    }

    func testThePromptNamesTheMovementThatKeepsLandingUnderTough() {
        let store = naiveStore(sessions: 12)
        XCTAssertEqual(store.unnamedLessSuspect(), .pushV)
        XCTAssertTrue(store.shouldAskAboutSuspect())
    }

    func testAnHonestTraineeIsNeverAsked() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<12 {
            _ = store.completeWorkout(session: store.nextSession, result: .plan)
        }
        XCTAssertNil(store.unnamedLessSuspect(), "nothing is failing — nothing to ask about")
        XCTAssertFalse(store.shouldAskAboutSuspect())
    }

    func testATraineeWhoAlreadyNamesTheMovementIsNeverAsked() {
        // Saying "this one hurt" is the answer the prompt is trying to reach.
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<12 {
            let session = store.nextSession
            let carries = session.exercises.contains { $0.pattern == .pushV }
            _ = store.completeWorkout(session: session, result: carries ? .less : .plan,
                                      discomfort: carries ? [.pushV] : [])
        }
        XCTAssertNil(store.unnamedLessSuspect())
    }

    func testTheQuestionIsAskedOncePerSession() {
        let store = naiveStore(sessions: 12)
        XCTAssertTrue(store.shouldAskAboutSuspect())
        store.dismissSuspectPrompt()
        XCTAssertFalse(store.shouldAskAboutSuspect(), "a question, not a campaign")

        // The next workout is a new session, so the question may return.
        _ = store.completeWorkout(session: store.nextSession, result: .less)
        XCTAssertTrue(store.shouldAskAboutSuspect())
    }

    func testAnsweringYesRestsTheMovementOnItsNextAppearance() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        store.confirmSuspectHurts(suspect)
        XCTAssertTrue(store.settings.pendingDiscomfort.contains(suspect))
        XCTAssertFalse(store.shouldAskAboutSuspect(), "the question is answered")

        // Walk until the movement appears; that session takes the pain path.
        var applied = false
        for _ in 0..<8 where !applied {
            let session = store.nextSession
            let carries = session.exercises.contains { $0.pattern == suspect }
            let before = store.engineState.levels[suspect] ?? 0
            _ = store.completeWorkout(session: session, result: .plan)
            if carries {
                applied = true
                // The load comes off (this persona never left the floor, so
                // there is nothing below zero to take) and the rest is armed.
                XCTAssertLessThanOrEqual(store.engineState.levels[suspect] ?? 0, before,
                                         "the pain path never adds load")
                XCTAssertGreaterThan(store.engineState.freezeRemaining(suspect), 0,
                                     "and rests the movement")
                XCTAssertNotNil(store.engineState.sore[suspect],
                                "the episode is on record, so growth waits for a confirmation")
                XCTAssertFalse(store.settings.pendingDiscomfort.contains(suspect),
                               "the answer is spent, not sticky")
            }
        }
        XCTAssertTrue(applied, "the movement appears within a rotation")
    }

    func testTheAnswerSurvivesARelaunch() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        store.confirmSuspectHurts(suspect)

        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertTrue(reloaded.settings.pendingDiscomfort.contains(suspect))
        XCTAssertFalse(reloaded.shouldAskAboutSuspect())
    }

    func testTheSofterAnswerHoldsTheLevelInsteadOfTakingTheLoadOff() throws {
        // "Just hard" is not a diagnosis: the signal only knows the movement
        // keeps coinciding with a tough session, so the cheap answer must cost
        // a pause, not a rest with a confirmation gate (spec §26.3).
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        store.confirmSuspectIsHard(suspect)
        XCTAssertTrue(store.settings.pendingPinned.contains(suspect))
        XCTAssertFalse(store.settings.pendingDiscomfort.contains(suspect))

        var applied = false
        for _ in 0..<8 where !applied {
            let session = store.nextSession
            let carries = session.exercises.contains { $0.pattern == suspect }
            _ = store.completeWorkout(session: session, result: .plan)
            if carries {
                applied = true
                XCTAssertGreaterThan(store.engineState.freezeRemaining(suspect), 0,
                                     "growth pauses")
                XCTAssertNil(store.engineState.sore[suspect],
                             "but no pain episode is opened — nothing waits for a fact")
                XCTAssertFalse(store.settings.pendingPinned.contains(suspect))
            }
        }
        XCTAssertTrue(applied)
    }

    func testAMovementAlreadyRestingIsNotSuggested() throws {
        let store = naiveStore(sessions: 12)
        let suspect = try XCTUnwrap(store.unnamedLessSuspect())
        store.confirmSuspectHurts(suspect)
        for _ in 0..<8 {
            _ = store.completeWorkout(session: store.nextSession, result: .plan)
            if store.engineState.freezeRemaining(suspect) > 0 { break }
        }
        XCTAssertNil(store.unnamedLessSuspect(),
                     "while it rests there is nothing left to ask")
    }
}
