//
//  MilestoneTests.swift
//  DredfitTests
//
//  Milestones are derived from the state on either side of applyFeedback,
//  so these tests seed a level, complete one workout, and read what came
//  back. Levels are chosen at band boundaries on purpose: 7 → 8 crosses a
//  tier, 31 → 32 crosses a set band, and 8 → 7 crosses one downwards.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class MilestoneTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-milestone-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// A store with a known counter and chosen levels.
    ///
    /// Seeded through a file rather than by assignment: `engineState` is
    /// `private(set)` so that only `completeWorkout` can move it, and these
    /// tests have no business being the exception. This also exercises the
    /// real load path.
    private func seededStore(counter: Int = 0,
                             levels: [Pattern: Int] = [:]) throws -> AppStore {
        func pairs(_ value: (Pattern) -> Int) -> String {
            Pattern.allCases.map { "\"\($0.rawValue)\",\(value($0))" }.joined(separator: ",")
        }
        let json = """
        {"engineState":{"counter":\(counter),
          "levels":[\(pairs { levels[$0] ?? 0 })],
          "failStreak":[\(pairs { _ in 0 })]},
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

    // MARK: - Tier milestones

    func testTierUpNamesTheExerciseYouJustUnlocked() throws {
        let probe = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(levels: [probe: 7])   // top of tier 1
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan)

        XCTAssertEqual(earned.count, 1, "only the seeded pattern crosses a tier")
        guard case .tierUp(let pattern, let tier, let exercise) = earned[0] else {
            return XCTFail("expected a tier-up, got \(earned[0])")
        }
        XCTAssertEqual(pattern, probe)
        XCTAssertEqual(tier, 2)
        // The name must come from the new tier, not the one just left behind.
        XCTAssertEqual(exercise,
                       ExerciseLibrary.entry(for: probe).variations[1].name)
    }

    func testSetBandMilestoneWhenTierIsAlreadyAtTheCeiling() throws {
        let probe = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(levels: [probe: 31])  // last level on 3 sets
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan)

        XCTAssertEqual(earned.count, 1)
        guard case .setBand(let pattern, let sets, _) = earned[0] else {
            return XCTFail("expected a set band, got \(earned[0])")
        }
        XCTAssertEqual(pattern, probe)
        XCTAssertEqual(sets, 4)
    }

    func testDroppingATierIsNotAMilestone() throws {
        let probe = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(levels: [probe: 8])   // bottom of tier 2
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .less)

        XCTAssertEqual(Level.decode(store.engineState.levels[probe]!).tier, 1,
                       "the level really did fall back a tier")
        XCTAssertTrue(earned.isEmpty, "a step down is never announced")
    }

    func testSkippedPatternEarnsNothing() throws {
        let probe = session(atCounter: 0).exercises[0].pattern
        let store = try seededStore(levels: [probe: 7])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan,
                                           skipped: [probe])

        XCTAssertEqual(store.engineState.levels[probe], 7, "a skip changes nothing")
        XCTAssertTrue(earned.isEmpty)
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
    /// deliberately not gated on how the session went — unlike the review
    /// request, which can wait for a better day.
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

    func testTierUpsAreListedAboveTheJubilee() throws {
        let probe = session(atCounter: 9).exercises[0].pattern
        let store = try seededStore(counter: 9, levels: [probe: 7])
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan)

        XCTAssertEqual(earned.count, 2)
        guard case .tierUp = earned[0] else {
            return XCTFail("the tier-up belongs on top, got \(earned[0])")
        }
        XCTAssertEqual(earned[1], .jubilee(workouts: 10))
    }

    /// v2.3's calibration can hand a first workout several unlocks at once;
    /// the detector must return them all rather than collapsing to one.
    func testSeveralTierUpsInOneWorkout() throws {
        let patterns = session(atCounter: 0).exercises.prefix(3).map(\.pattern)
        let store = try seededStore(levels: Dictionary(uniqueKeysWithValues:
                                                    patterns.map { ($0, 7) }))
        let session = store.nextSession

        let earned = store.completeWorkout(session: session, result: .plan)

        XCTAssertEqual(earned.count, 3)
        XCTAssertEqual(Set(earned.map(\.id)).count, 3, "rows must be distinct")
    }
}
