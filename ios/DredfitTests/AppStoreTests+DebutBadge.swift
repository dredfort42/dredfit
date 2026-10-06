//
//  The debut badge tests, in a file of their own: the badge is its own
//  subject.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - The debut badge and what was performed

extension AppStoreTests {

    /// An exercise actually PERFORMED counts toward the debut history, while
    /// a skipped one does not. So the badge on a new variation stays standing
    /// through a session that skipped the movement — the variation really has
    /// never been performed — and goes the moment the trainee performs it.
    func testAPerformedExerciseCountsWhereAPainfulOneDoesNot() {
        let hurtURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: hurtURL) }
        // The weekly ceiling holds the slow-adapting patterns to three growth
        // events a week, so a walk up the scale cannot be a run of
        // same-instant taps — every workout here gets its own day.
        let start = Date()
        for (url, performed) in [(tempURL!, true), (hurtURL, false)] {
            let store = makeStore(storageURL: url)
            var day = 0
            // Every probe is passed: that is the only door into a new
            // movement, so a walk that ignored them would never get there.
            func train(_ result: FeedbackResult, overrides: [Pattern: Double] = [:],
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
            // A SKIP is the signal here: the badge's rule is about what the
            // person has DONE, not about what was planned for them.
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
}
