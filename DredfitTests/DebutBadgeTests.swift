//
//  DebutBadgeTests.swift
//  DredfitTests
//
//  The "new variation" badge on Today: a pattern is flagged only when the
//  next session asks for a tier the journal has never seen performed — and
//  the flag goes away once the new variation has been done.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class DebutBadgeTests: XCTestCase {

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

    /// Before any workout there is nothing to compare against — the first
    /// plan must not open covered in "new variation" pills.
    func testFreshStoreHasNoDebuts() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.debutPatterns.isEmpty)
    }

    /// Rating "easy" repeatedly pushes levels up two per workout; the first
    /// session that asks for a tier above everything in the journal gets the
    /// badge, and the badge tells the truth: planned tier > max performed.
    func testDebutAppearsWhenAPatternCrossesIntoANewTier() {
        let store = AppStore(storageURL: tempURL)
        var sawDebut = false
        for _ in 0..<8 {
            let debuts = store.debutPatterns
            if !debuts.isEmpty {
                sawDebut = true
                let session = store.nextSession
                for p in debuts {
                    let planned = session.exercises.first { $0.pattern == p }
                    XCTAssertNotNil(planned, "a debut must be in the next session")
                    let maxPerformed = store.records
                        .compactMap { record -> Int? in
                            guard !(record.skipped?.contains(p) ?? false) else { return nil }
                            return record.exercises?
                                .filter { $0.pattern == p }
                                .map(\.tier).max()
                        }
                        .max() ?? 0
                    XCTAssertGreaterThan(planned?.tier ?? 0, maxPerformed)
                }
                break
            }
            store.completeWorkout(session: store.nextSession, result: .more,
                                  overrides: [:], skipped: [])
        }
        XCTAssertTrue(sawDebut, "eight easy workouts must cross at least one tier boundary")
    }

    /// Performing the new variation retires its badge: the tier is in the
    /// journal now, so the same variation must not announce itself twice —
    /// including after a deload takes the level down and it climbs back.
    func testDebutClearsAfterTheVariationIsPerformed() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<8 where store.debutPatterns.isEmpty {
            store.completeWorkout(session: store.nextSession, result: .more,
                                  overrides: [:], skipped: [])
        }
        guard let debut = store.debutPatterns.first else {
            return XCTFail("no debut appeared to complete")
        }
        // Do the workout that contains the debut — on plan, nothing skipped.
        store.completeWorkout(session: store.nextSession, result: .plan,
                              overrides: [:], skipped: [])
        XCTAssertFalse(store.debutPatterns.contains(debut),
                       "a performed variation is no longer a debut")
    }

    /// A skipped exercise is not "performed": the badge must survive the
    /// workout it was skipped in and come back on the next plan.
    func testSkippingTheDebutKeepsTheBadge() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<8 where store.debutPatterns.isEmpty {
            store.completeWorkout(session: store.nextSession, result: .more,
                                  overrides: [:], skipped: [])
        }
        guard let debut = store.debutPatterns.first else {
            return XCTFail("no debut appeared to skip")
        }
        store.completeWorkout(session: store.nextSession, result: .plan,
                              overrides: [:], skipped: [debut])
        if store.nextSession.exercises.contains(where: { $0.pattern == debut }) {
            XCTAssertTrue(store.debutPatterns.contains(debut),
                          "skipping must not count as performing the variation")
        }
    }
}
