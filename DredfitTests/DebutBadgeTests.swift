import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class DebutBadgeTests: XCTestCase {
    /// v2.22 (spec §33): every workout gets its own day. Growth moves one set
    /// at a time now, so a tier is 24 growth events rather than 8 — and stacked
    /// on a single instant the §28.5 weekly ceiling (six sub-steps for the fast
    /// tissues) would hold the walk short of any tier boundary forever.
    private var day = 0
    private func train(_ store: AppStore, _ result: FeedbackResult,
                       skipped: Set<Pattern> = []) {
        day += 1
        store.completeWorkout(session: store.nextSession, result: result,
                              overrides: [:], skipped: skipped,
                              date: Date(timeIntervalSinceNow: Double(day) * 86_400))
    }

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

    func testDebutAppearsWhenAPatternCrossesIntoANewTier() {
        let store = AppStore(storageURL: tempURL)
        var sawDebut = false
        // v2.22 (spec §33): a tier is 24 growth events now, not 8 — growth
        // moves one set at a time — so the walk to the first tier boundary
        // needs room. The subject (a crossing raises the badge) is unchanged.
        for _ in 0..<60 {
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
            train(store, .more)
        }
        XCTAssertTrue(sawDebut, "the run must cross at least one tier boundary")
    }

    /// Performing the new variation retires its badge: the tier is in the
    /// journal now, so the same variation must not announce itself twice —
    func testDebutClearsAfterTheVariationIsPerformed() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<60 where store.debutPatterns.isEmpty {
            train(store, .more)
        }
        guard let debut = store.debutPatterns.first else {
            return XCTFail("no debut appeared to complete")
        }
        // Do the workout that contains the debut — on plan, nothing skipped.
        train(store, .plan)
        XCTAssertFalse(store.debutPatterns.contains(debut),
                       "a performed variation is no longer a debut")
    }

    func testSkippingTheDebutKeepsTheBadge() {
        let store = AppStore(storageURL: tempURL)
        for _ in 0..<60 where store.debutPatterns.isEmpty {
            train(store, .more)
        }
        guard let debut = store.debutPatterns.first else {
            return XCTFail("no debut appeared to skip")
        }
        train(store, .plan, skipped: [debut])
        if store.nextSession.exercises.contains(where: { $0.pattern == debut }) {
            XCTAssertTrue(store.debutPatterns.contains(debut),
                          "skipping must not count as performing the variation")
        }
    }
}
