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
        XCTAssertTrue(store.debutPatterns.isEmpty,
                      "nothing has been performed yet, so nothing can be new")
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
                    XCTAssertGreaterThan(planned?.variation ?? 0, maxPerformed,
                                         "\(p): a debut is a variation above everything performed")
                }
                break
            }
            train(store, .more)
        }
        XCTAssertTrue(sawDebut, "the run must cross at least one variation boundary")
    }

    /// The subject of the two tests below, walked to until it has a debut.
    ///
    /// Deliberately NOT `store.debutPatterns.first`. That was a `Set`, Swift
    /// randomises the hash seed per process, and one session can carry several
    /// debuts at once (MilestoneTests.testSeveralNewVariationsInOneWorkout) —
    /// so "first" named a different movement from run to run and the mutation
    /// these tests exist to catch went red only on some runs.
    ///
    /// The pull SLOT, specifically: it stands in every session, only its
    /// branch rotates. That is what lets the badge still be asked about after
    /// the workout that skipped it — a rotating movement is simply absent from
    /// the next plan, and the skip test used to wrap its only real assertion
    /// in "if it is still there" and pass in silence when it was not.
    private func walkToAPullDebut(_ store: AppStore, sessions limit: Int = 200) throws -> Pattern? {
        let slot = try XCTUnwrap(
            store.nextSession.exercises.first { Pattern.pullSide.contains($0.pattern) }?.pattern,
            "every session carries a pull slot — without one there is no subject")
        var walked = 0
        while !store.debutPatterns.contains(slot) {
            guard walked < limit else { return nil }
            train(store, .more)
            walked += 1
        }
        return slot
    }

    /// Performing the new variation retires its badge: the tier is in the
    /// journal now, so the same variation must not announce itself twice —
    /// once it has been trained, its debut is done.
    func testDebutClearsAfterTheVariationIsPerformed() throws {
        let store = AppStore(storageURL: tempURL)
        guard let debut = try walkToAPullDebut(store) else {
            return XCTFail("the pull slot never reached a new variation — the walk is "
                           + "broken, and nothing below would be about the badge")
        }
        // Do the workout that contains the debut — on plan, nothing skipped.
        train(store, .plan)
        XCTAssertFalse(store.debutPatterns.contains(debut),
                       "a performed variation is no longer a debut")
    }

    func testSkippingTheDebutKeepsTheBadge() throws {
        let store = AppStore(storageURL: tempURL)
        guard let debut = try walkToAPullDebut(store) else {
            return XCTFail("the pull slot never reached a new variation — the walk is "
                           + "broken, and nothing below would be about the badge")
        }
        train(store, .plan, skipped: [debut])
        // Asserted, not assumed: the claim underneath is vacuous if the
        // movement left the plan, and "if it is still there" is how the old
        // version of this test said nothing at all on a third of its runs.
        XCTAssertTrue(store.nextSession.exercises.contains { $0.pattern == debut },
                      "the pull slot stays in every plan, so the badge is still being asked about")
        XCTAssertTrue(store.debutPatterns.contains(debut),
                      "skipping must not count as performing the variation")
    }
}
