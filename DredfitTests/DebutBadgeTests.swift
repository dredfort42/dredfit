import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class DebutBadgeTests: AppStoreTestCase {
    /// Every workout gets its own day: stacked on a single instant the weekly
    /// ceiling would hold the walk short of any ladder boundary forever.
    ///
    /// And every probe the plan offers is PASSED. In v3 that is the only door
    /// into a new movement (§40.4) — a run of "easy" taps alone can no longer
    /// cross a variation, so a walk that did not answer its probes would never
    /// produce a debut at all.
    private var day = 0
    private func train(_ store: AppStore, _ result: FeedbackResult,
                       skipped: Set<Pattern> = []) {
        day += 1
        let session = store.nextSession
        var probes: [Pattern: Int] = [:]
        for ex in session.exercises {
            guard let probe = ex.probe else { continue }
            probes[ex.pattern] = Dose.grid(probe.unit).min
        }
        _ = store.completeWorkout(session: session, result: result,
                                  overrides: [:], skipped: skipped,
                                  probes: probes,
                                  date: Date(timeIntervalSinceNow: Double(day) * 86_400))
    }

    /// Before any workout there is nothing to compare against — the first
    /// plan must not open covered in "new variation" pills.
    func testFreshStoreHasNoDebuts() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertTrue(store.debutPatterns.isEmpty)
    }

    func testDebutAppearsWhenAPatternCrossesIntoANewVariation() {
        let store = AppStore(storageURL: tempURL)
        var sawDebut = false
        // A variation is a whole grid of doses now — twelve rungs at three
        // sets each — so the walk to the first boundary needs room. The
        // subject (a crossing raises the badge) is unchanged.
        for _ in 0..<120 {
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
                                .map(\.variation).max()
                        }
                        .max() ?? 0
                    XCTAssertGreaterThan(planned?.variation ?? 0, maxPerformed)
                }
                break
            }
            train(store, .more)
        }
        XCTAssertTrue(sawDebut, "the run must cross at least one variation boundary")
    }

    /// Performing the new variation retires its badge: the tier is in the
    /// journal now, so the same variation must not announce itself twice —
    /// once it has been trained, its debut is done.
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
