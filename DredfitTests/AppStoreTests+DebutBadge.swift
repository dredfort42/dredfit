//
//  The debut badge tests, moved out of AppStoreTests.swift, which had grown
//  past nine hundred lines. It is still over the linter's file ceiling after
//  this — the point is that the badge is its own subject, not that the count
//  now passes. The code moved unchanged.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - The debut badge across the pain semantics

extension AppStoreTests {

    /// The sign that flips against discomfort: an exercise actually PERFORMED
    /// counts toward the debut history, while a painful one does not. moved
    /// where that shows: the report unloaded the movement to the previous
    /// tier, so the badge question returned only after a climb back.
    ///
    /// A later wave moves it again, and closer to the point: the first report
    /// keeps the variation and only drops the dose inside it, so the badge is
    /// still standing right after the report — the tier really has never been
    /// performed, because the report voided the session for it. It goes the
    /// moment the trainee actually performs that tier.
    ///
    /// The "performed" side used to be a held exercise. The hold is cancelled,
    /// so it is now an ordinary rated session — which is the same claim with
    /// one fewer input involved.
    func testAPerformedExerciseCountsWhereAPainfulOneDoesNot() {
        let hurtURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: hurtURL) }
        // The weekly ceiling holds the slow-adapting patterns to three levels
        // a week, so a walk up the scale can no longer be a run of
        // same-instant taps — every workout here gets its own day.
        let start = Date()
        for (url, performed) in [(tempURL!, true), (hurtURL, false)] {
            let store = AppStore(storageURL: url)
            var day = 0
            // Every probe is passed: since §40.4 that is the only door into a
            // new movement, so a walk that ignored them would never get there.
            func train(_ result: FeedbackResult, overrides: [Pattern: Int] = [:],
                       skipped: Set<Pattern> = []) {
                day += 1
                let session = store.nextSession
                var probes: [Pattern: Int] = [:]
                for ex in session.exercises {
                    guard let probe = ex.probe else { continue }
                    probes[ex.pattern] = Dose.grid(probe.unit).min
                }
                _ = store.completeWorkout(session: session, result: result,
                                          overrides: overrides, skipped: skipped,
                                          probes: probes,
                                          date: start.addingTimeInterval(Double(day) * 86_400))
            }
            func pullVariation() -> Int {
                store.nextSession.exercises.first { $0.pattern == .pull }!.variation
            }

            // Walk pull to its second variation: it is in every session, and
            // the weekly ceiling holds the slow tissues to three growth events
            // a week, so the climb takes weeks.
            while pullVariation() < 2 {
                guard day < 200 else {
                    return XCTFail("seeding: pull never reached its second variation")
                }
                train(.more)
            }
            // The movement used to be taken out of the session by a pain
            // report; a SKIP is the signal that survived, and the badge's rule
            // is the same either way — it is about what the person has DONE,
            // not about what was planned for them.
            if performed {
                train(.plan)
                XCTAssertFalse(store.debutPatterns.contains(.pull),
                               "actually performed — the second variation is no debut")
                continue
            }
            train(.plan, skipped: [.pull])
            XCTAssertEqual(pullVariation(), 2, "a skip does not change the variation")
            XCTAssertTrue(store.debutPatterns.contains(.pull),
                          "not performed — the second variation is still a debut")
            train(.plan)
            XCTAssertFalse(store.debutPatterns.contains(.pull),
                           "performed at last — the badge is spent")
        }
    }

    // SNIPPED: the two tests of the freeze — that a report rested the movement
    // and was kept apart from a plain skip in the journal, and that Today only
    // mentioned a resting movement while it was in the plan. Nothing rests any
    // more: a movement the person finds too hard stays in the plan and gets an
    // easier variation or fewer sets.
    //
    // The handle's own equivalents live in SessionLengthTests (what a handle
    // does to the plan) and WeakLinkPromptTests (that the movement stays in the
    // rotation afterwards).

    // SNIPPED: two more tests of the pain report — that a reported exercise
    // did not count as performed, and that the report froze the pattern,
    // stayed apart from a skip in the journal and survived a reload. The input
    // is gone; the journal field went with it.
}
