//
//  The silent decay tests for the 7-13 day blind zone (issue #37), in their
//  own file to keep AppStoreTests.swift under the linter's file and
//  type-body ceilings. Kept together because they share `storeWithWorkout`,
//  the history-seeding helper the decay window needs, and all pin the same
//  invariant: a break decays at most once, and a peeked-at break must not
//  cost more than one left alone.
//

import XCTest
import DredfitCore
@testable import Dredfit

// MARK: - Silent decay for the 7–13 day blind zone (issue #37)
extension AppStoreTests {

    /// A store whose last workout happened `daysAgo` days ago, after
    /// `sessions` workouts rated "plan": grown positions give a break room to
    /// fall.
    private func storeWithWorkout(daysAgo: Int, at url: URL, sessions: Int = 15) throws -> AppStore {
        // `daysAgo` on the base class: it seeds from MIDNIGHTS rather than
        // `now − n × 86 400` because `gapDays` puts both of its dates through
        // `startOfDay` (#172). 6/7 and 13/14 are the exact edges of the blind
        // zone the tests below stand on, and across a DST transition the
        // elapsed-seconds form lands in the neighbouring calendar day
        // (Europe/Berlin, 25.10, a run after 23:00).
        let cal = Calendar.current
        let date = try self.daysAgo(daysAgo)
        let store = makeStore(storageURL: url)
        // The seeding workouts are one CALENDAR day apart, ending on `date`.
        // Stacked on one instant they would age the weekly window by the
        // one-hour floor each, and the weekly budget — three growth events
        // for the slow tissues — would hold the positions near the clean
        // start. The last record still sits exactly `daysAgo` back, so every
        // gap this fixture is about is unchanged.
        for i in 0..<sessions {
            let day = try XCTUnwrap(cal.date(byAdding: .day, value: -(sessions - 1 - i), to: date),
                                    "the calendar must be able to step back inside the seeding run")
            _ = store.completeWorkout(session: store.nextSession, result: .plan, date: day)
        }
        return store
    }

    func testSilentDecayAppliesExactlyOncePerBreak() throws {
        let store = try storeWithWorkout(daysAgo: 10, at: tempURL)
        let before = AppStore.positions(of: store.engineState)
        store.applySilentDecayIfNeeded()
        for p in Pattern.allCases {
            // A decay is one rung of DOSE, floored by the grid — and
            // on the floor it takes a set instead, which is why the claim is
            // "no heavier", not "exactly minus one" for every movement.
            XCTAssertLessThanOrEqual(Engine.progress(store.engineState, p),
                                     Engine.progress(p, variation: before[p]!.variation,
                                                     sets: before[p]!.sets,
                                                     dose: before[p]!.dose),
                                     "\(p): a decay never adds")
        }
        let once = AppStore.positions(of: store.engineState)
        XCTAssertNotEqual(once, before, "the decay did something")
        store.applySilentDecayIfNeeded()
        XCTAssertEqual(AppStore.positions(of: store.engineState), once,
                       "the same break must not decay twice")
        // The stamp survives a relaunch — persisted, not in-memory.
        let reloaded = makeStore()
        reloaded.applySilentDecayIfNeeded()
        XCTAssertEqual(AppStore.positions(of: reloaded.engineState), once,
                       "a relaunch inside the same break must not decay again")
    }

    func testSilentDecayIgnoresGapsOutsideTheBlindZone() throws {
        for days in [0, 6, 14, 30] {
            let url = tempURL.deletingPathExtension().appendingPathExtension("\(days).json")
            defer { try? FileManager.default.removeItem(at: url) }
            let store = try storeWithWorkout(daysAgo: days, at: url)
            let before = store.engineState
            store.applySilentDecayIfNeeded()
            XCTAssertEqual(store.engineState, before,
                           "gap \(days): outside [7, 14) nothing may change")
        }
    }

    func testDecayedBreakComebackTotalsExactlyTheTable() throws {
        let cal = Calendar.current
        // Calendar arithmetic, like the seed: 10 + 6 must stay 16 across DST.
        let day16 = try XCTUnwrap(cal.date(byAdding: .day, value: 6, to: .now),
                                  "the calendar must step 6 days forward")
        // Break that got peeked at on day 10: decay, then a weakened comeback.
        let peeked = try storeWithWorkout(daysAgo: 10, at: tempURL)
        peeked.applySilentDecayIfNeeded()
        peeked.acceptComeback(now: day16)
        // The same break with the app never opened: one plain comeback.
        let otherURL = tempURL.deletingPathExtension().appendingPathExtension("control.json")
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let control = try storeWithWorkout(daysAgo: 10, at: otherURL)
        control.acceptComeback(now: day16)
        // By construction: a decay plus a weakened comeback walks the same
        // rungs as one plain comeback, and the identity is read where it lands.
        XCTAssertEqual(AppStore.positions(of: peeked.engineState),
                       AppStore.positions(of: control.engineState),
                       "peeking mid-break must not cost more than staying away")
    }

    func testDecayStampGoesStaleAfterTheNextWorkout() throws {
        let store = try storeWithWorkout(daysAgo: 10, at: tempURL)
        store.applySilentDecayIfNeeded()
        // The break ends: a workout today re-anchors the stamp's reference.
        _ = store.completeWorkout(session: store.nextSession, result: .plan)
        let after = AppStore.positions(of: store.engineState)
        // A fresh 8-day break decays again — the old stamp must not block it.
        let day8 = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 8, to: .now),
                                 "the calendar must be able to step 8 days forward")
        store.applySilentDecayIfNeeded(now: day8)
        XCTAssertNotEqual(AppStore.positions(of: store.engineState), after,
                          "a new break must decay independently")
    }
}
