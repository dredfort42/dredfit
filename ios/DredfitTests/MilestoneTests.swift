import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class MilestoneTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-milestone" }

    /// A store with a known counter and chosen positions.
    ///
    /// Seeded through a file rather than by assignment: `engineState` is
    /// `private(set)` so that only `completeWorkout` can move it, and these
    /// tests have no business being the exception. This also exercises the
    /// real load path — which, since §40.8, is the only thing that separates a
    /// seeded state from a clean start.
    ///
    /// `atCeiling` puts a movement on the top of ITS CURRENT variation, with a
    /// journal to match: that is the one position a probe is offered from
    /// (§40.4), and a probe is now the only door into a new movement.
    private func seededStore(counter: Int = 0,
                             atCeiling: [Pattern] = [],
                             atTopVariation: [Pattern] = [],
                             atFloorOfSecond: [Pattern] = [],
                             failStreak: [Pattern: Int] = [:]) throws -> AppStore {
        func variation(_ p: Pattern) -> Int {
            if atTopVariation.contains(p) { return Library.count(p) }
            if atFloorOfSecond.contains(p) { return 2 }
            return 1
        }
        func dose(_ p: Pattern) -> Int {
            let grid = Dose.grid(Library.unit(p, variation(p)))
            return atCeiling.contains(p) || atTopVariation.contains(p) ? grid.max : grid.min
        }
        func pairs(_ value: (Pattern) -> Int) -> String {
            Pattern.allCases.map { "\"\($0.rawValue)\",\(value($0))" }.joined(separator: ",")
        }
        // The journal is sparse, and only the movements that were put
        // somewhere have one — the rest have never been anywhere.
        let journal = (atCeiling + atTopVariation + atFloorOfSecond).map { p in
            let rows = (1...variation(p)).map { v in
                "\"\(v)\":\(v == variation(p) ? dose(p) : Dose.grid(Library.unit(p, v)).max)"
            }.joined(separator: ",")
            return "\"\(p.rawValue)\",{\(rows)}"
        }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(counter),
          "vars":[\(pairs(variation))],
          "doses":[\(pairs(dose))],
          "shown":[\(journal)],
          "failStreak":[\(pairs { failStreak[$0] ?? 0 })]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    /// The session for a given counter, as a pure engine function — the probe
    /// pattern must come from the session the seeded store will actually
    /// generate, not from session 1.
    private func session(atCounter counter: Int) -> Session {
        var state = EngineState.initial
        state.counter = counter
        return Engine.generateSession(state)
    }

    /// A number for every probe the plan offers, at the target it asks for —
    /// what a person who passed every probe would have entered.
    private func passing(_ session: Session) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for ex in session.exercises {
            guard let probe = ex.probe else { continue }
            out[ex.pattern] = Dose.grid(probe.unit).min
        }
        return out
    }

    // MARK: - A new movement

    func testVariationUpNamesTheExerciseYouJustUnlocked() throws {
        let subject = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(atCeiling: [subject])
        let session = store.nextSession
        XCTAssertNotNil(session.exercises.first { $0.pattern == subject }?.probe,
                        "the seed must actually offer a probe")

        let earned = store.completeWorkout(session: session, result: .plan,
                                           probes: passing(session))

        XCTAssertEqual(earned.count, 1, "only the seeded pattern crosses a variation")
        guard case .variationUp(let pattern, let variation, let exercise) = earned[0] else {
            return XCTFail("expected a new variation, got \(earned[0])")
        }
        XCTAssertEqual(pattern, subject)
        XCTAssertEqual(variation, 2)
        // The name must come from the NEW variation, not the one just left.
        XCTAssertEqual(exercise, Library.name(subject, 2))
    }

    /// The probe is the only door: a person who stands on the ceiling and
    /// enters nothing crosses nothing, and nothing is announced.
    func testAnUnresolvedProbeEarnsNothing() throws {
        let subject = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(atCeiling: [subject])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan)

        XCTAssertTrue(earned.isEmpty, "an unresolved probe is not a milestone")
        XCTAssertEqual(store.engineState.vars[subject], 1)
    }

    func testSetBandMilestoneOnTheTopVariation() throws {
        let subject = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(atTopVariation: [subject])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan)

        XCTAssertEqual(earned.count, 1)
        guard case .setBand(let pattern, let sets, _) = earned[0] else {
            return XCTFail("expected a set band, got \(earned[0])")
        }
        XCTAssertEqual(pattern, subject)
        XCTAssertEqual(sets, 4)
    }

    /// A rating on its own can no longer cross a variation — that is the whole
    /// point of §40.4 — so the drop this test needs is produced the way one
    /// still is: by the deload on the third shortfall, seeded with a streak of
    /// two. The subject, "a step down is never announced", is untouched.
    func testDroppingAVariationIsNotAMilestone() throws {
        let subject = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(atFloorOfSecond: [subject],
                                    failStreak: [subject: EngineConfig.failsToDeload - 1])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .less)

        XCTAssertEqual(store.engineState.vars[subject], 1,
                       "the movement really did fall back a variation")
        XCTAssertTrue(earned.isEmpty, "a step down is never announced")
    }

    func testSkippedPatternEarnsNothing() throws {
        let subject = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(atCeiling: [subject])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan,
                                           skipped: [subject],
                                           probes: passing(session))

        XCTAssertEqual(store.engineState.vars[subject], 1, "a skip changes nothing")
        XCTAssertTrue(earned.isEmpty)
    }

    /// The property is "a neighbour that stays put must not swallow this
    /// movement's milestone"; what makes a neighbour stay put has changed
    /// three times — a pin, a freeze, and now a SKIP, which is the signal that
    /// survived them all.
    func testAMovementThatStaysPutDoesNotSwallowAMilestone() throws {
        let subject = session(atCounter: 9).exercises[0].pattern
        let stillOther = session(atCounter: 9).exercises[1].pattern
        let store = try seededStore(counter: 9, atCeiling: [subject])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan,
                                           skipped: [stillOther],
                                           probes: passing(session))

        XCTAssertEqual(earned.count, 2, "the new variation and the jubilee both land")
        guard case .variationUp(let pattern, _, _) = earned[0] else {
            return XCTFail("expected the new variation on top, got \(earned[0])")
        }
        XCTAssertEqual(pattern, subject)
        XCTAssertEqual(earned[1], .jubilee(workouts: 10))
        XCTAssertEqual(store.engineState.doses[stillOther],
                       Dose.grid(Library.unit(stillOther, 1)).min,
                       "the movement that stayed put stayed put")
        XCTAssertEqual(store.engineState.sub[stillOther] ?? 0, 0,
                       "and it collected no sub-step either")
    }

    // MARK: - The acceptance case: a hard session earns nothing

    func testSessionRatedLessEarnsNoMilestones() throws {
        let store = try seededStore(counter: 3)           // 4 is not a jubilee
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .less)

        XCTAssertTrue(earned.isEmpty)
    }

    // MARK: - Jubilees

    func testJubileeAtTheTenthWorkout() throws {
        let store = try seededStore(counter: 9)
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan)

        XCTAssertEqual(earned, [.jubilee(workouts: 10)])
    }

    /// A jubilee fires on one exact counter value and never again, so it is
    /// unaffected by how hard that session actually was — a harder result
    /// earns it exactly the same.
    func testJubileeSurvivesAHardSession() throws {
        let store = try seededStore(counter: 9)
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .less)

        XCTAssertEqual(earned, [.jubilee(workouts: 10)])
    }

    func testJubileeSchedule() {
        for counter in [10, 25, 50, 100, 150, 200] {
            XCTAssertTrue(MilestoneDetector.isJubilee(counter), "\(counter) is a jubilee")
        }
        for counter in [0, 1, 9, 11, 24, 26, 49, 75, 99, 101, 125] {
            XCTAssertFalse(MilestoneDetector.isJubilee(counter), "\(counter) is not")
        }
    }

    // MARK: - Several at once

    func testNewVariationsAreListedAboveTheJubilee() throws {
        let subject = session(atCounter: 9).exercises[0].pattern
        let store = try seededStore(counter: 9, atCeiling: [subject])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan,
                                           probes: passing(session))

        XCTAssertEqual(earned.count, 2)
        guard case .variationUp = earned[0] else {
            return XCTFail("the new variation belongs on top, got \(earned[0])")
        }
        XCTAssertEqual(earned[1], .jubilee(workouts: 10))
    }

    func testSeveralNewVariationsInOneWorkout() throws {
        let patterns = session(atCounter: 0).exercises.prefix(3).map(\.pattern)
        let store = try seededStore(atCeiling: Array(patterns))
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan,
                                           probes: passing(session))

        XCTAssertEqual(earned.count, 3)
        XCTAssertEqual(Set(earned.map(\.id)).count, 3, "rows must be distinct")
    }
}
