//
//  EdgeCaseTests.swift
//  Engine edge cases not covered by invariants and golden fixtures.
//

import XCTest
@testable import DredfitCore

final class EdgeCaseTests: XCTestCase {

    // MARK: - Actual values: bounds and special cases

    /// An actual for a pattern not present in the session must be silently ignored.
    func testOverrideForAbsentPatternIsIgnored() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        let inSession = Set(session.exercises.map(\.pattern))
        guard let absent = Pattern.ordered.first(where: { !inSession.contains($0) }) else {
            return XCTFail("all 9 patterns are in the session — rotation is broken")
        }
        let next = Engine.applyFeedback(state: state, session: session,
                                        result: .plan, overrides: [absent: 15])
        XCTAssertEqual(next.levels[absent], 0, "an actual for an absent pattern changed the level")
    }

    /// A hold actual rounds to the nearest 5 s step.
    func testHoldOverrideRoundsToNearestStep() {
        // 22 s → step round(0.4)=0 → level 0; 23 s → step round(0.6)=1 → level 1
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, actual: 22), 0)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, actual: 23), 1)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, actual: 55), 7)
    }

    /// An actual below the bottom of the range drops the level into the previous tier (continuous formula).
    func testOverrideBelowRangeDropsToLowerTier() {
        // tier 2, actual 5 reps: (2-1)*8 + (5-8) = 5 → tier 1, 13 reps
        let l = Level.fromActual(pattern: .squat, tier: 2, actual: 5)
        XCTAssertEqual(l, 5)
        XCTAssertEqual(Level.decode(l).tier, 1)
        XCTAssertEqual(Level.decode(l).reps, 13)
    }

    /// Extreme actuals clamp to [0, levelMax].
    func testOverrideExtremesClamp() {
        XCTAssertEqual(Level.fromActual(pattern: .squat, tier: 1, actual: 0), 0)
        XCTAssertEqual(Level.fromActual(pattern: .squat, tier: 4, actual: 99),
                       EngineConfig.levelMax)
    }

    /// An actual equal to the plan does not change the level and resets failStreak.
    func testOverrideEqualToPlanResetsFailStreak() {
        var state = EngineState.initial
        // two consecutive underperformances across all patterns of the first two sessions
        for _ in 0..<2 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .less)
        }
        let session = Engine.generateSession(state)
        let ex = session.exercises.first(where: { $0.unit == .reps })!
        let p = ex.pattern
        // level 0 → plan 8; actual 8 = plan → newL == oldL → the streak must reset
        let next = Engine.applyFeedback(state: state, session: session,
                                        result: .plan, overrides: [p: ex.load])
        XCTAssertEqual(next.failStreak[p], 0, "an on-plan actual did not reset the underperformance streak")
    }

    /// The deload also fires when the third consecutive fail came through an actual
    /// (not through a "less" rating). We use pull — it is in every session.
    func testDeloadTriggersViaOverrideDrop() {
        var state = EngineState.initial
        for _ in 0..<12 {  // pull: 12 × (+2) = 24
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .more)
        }
        XCTAssertEqual(state.levels[.pull], 24)

        // three sessions in a row we drop pull via a "plan − 2" actual
        var expected = 24
        for i in 1...3 {
            let s = Engine.generateSession(state)
            let ex = s.exercises.first { $0.pattern == .pull }!
            let actual = ex.load - 2
            state = Engine.applyFeedback(state: state, session: s,
                                         result: .plan, overrides: [.pull: actual])
            expected -= 2
            if i == 3 {
                expected -= EngineConfig.deloadDrop  // third fail → deload
                XCTAssertEqual(state.failStreak[.pull], 0, "after a deload the streak must reset")
            } else {
                XCTAssertEqual(state.failStreak[.pull], i)
            }
            XCTAssertEqual(state.levels[.pull], expected, "step \(i)")
        }
    }

    // MARK: - Rotation: periodicity and completeness

    /// The session's pattern set repeats with a period of 8 (rotation determinism).
    func testRotationPeriodicity() {
        var stateA = EngineState.initial
        var patternSets: [Set<Pattern>] = []
        for _ in 0..<16 {
            let s = Engine.generateSession(stateA)
            patternSets.append(Set(s.exercises.map(\.pattern)))
            stateA = Engine.applyFeedback(state: stateA, session: s, result: .plan)
        }
        for i in 0..<8 {
            XCTAssertEqual(patternSets[i], patternSets[i + 8],
                           "sessions \(i) and \(i+8) should share the same patterns")
        }
    }

    /// The exercise order in a session always follows Pattern.ordered.
    func testSessionExercisesFollowCanonicalOrder() {
        var state = EngineState.initial
        for _ in 0..<8 {
            let s = Engine.generateSession(state)
            let indices = s.exercises.map { Pattern.ordered.firstIndex(of: $0.pattern)! }
            XCTAssertEqual(indices, indices.sorted(), "exercises not in canonical order")
            state = Engine.applyFeedback(state: state, session: s, result: .plan)
        }
    }

    // MARK: - Duration estimate

    /// Duration is positive and non-decreasing as levels grow.
    func testEstimatedDurationGrowsWithLevel() {
        var state = EngineState.initial
        let start = Engine.generateSession(state).estimatedTotalMin
        XCTAssertGreaterThan(start, 0)
        for _ in 0..<40 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .more)
        }
        let grown = Engine.generateSession(state).estimatedTotalMin
        XCTAssertGreaterThan(grown, start, "duration did not grow as levels grew")
        XCTAssertLessThan(grown, 90, "duration is implausibly large")
    }

    // MARK: - Serialization

    /// A state with maximum levels survives a JSON round-trip.
    func testMaxedStateRoundTrip() throws {
        var state = EngineState.initial
        for p in Pattern.ordered { state.levels[p] = EngineConfig.levelMax }
        state.counter = 12345
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    /// All display strings are non-empty and contain numbers (for any levels).
    func testDisplayStringsWellFormed() {
        var state = EngineState.initial
        for step in 0..<32 {
            for p in Pattern.ordered { state.levels[p] = min(step, EngineConfig.levelMax) }
            let s = Engine.generateSession(state)
            for ex in s.exercises {
                XCTAssertFalse(ex.display.isEmpty)
                XCTAssertTrue(ex.display.contains("\(ex.sets)"))
                XCTAssertTrue(ex.display.contains("\(ex.load)"))
                XCTAssertFalse(ex.name.isEmpty)
            }
            state.counter += 1
        }
    }
}
