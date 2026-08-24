//
//  Engine edge cases not covered by invariants and golden fixtures.
//

import XCTest
@testable import DredfitCore

// Disambiguate from the Pattern type introduced in the macOS 26 SDK
private typealias Pattern = DredfitCore.Pattern

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

    /// A hold actual lands on the nearest rung of its ladder, ties DOWN.
    ///
    /// Re-marked for v2.21 (spec §32.5): tier 1 runs 20-22-24-26-29-32-35-39,
    /// so the rounding is by rung and not by five seconds. 21 s sits dead
    /// centre between 20 and 22 and settles onto the lower rung; 22 s IS rung
    /// 1; 55 s is off the top of the ladder, and the edge interval (4 s)
    /// carries it on to rung 11 — a level in tier 2. Continuing past the edge
    /// is what keeps the estimate monotone in the fact (§25.1): clamping at
    /// rung 7 would make an honest 43 s score below an honest 42.
    func testHoldOverrideLandsOnTheNearestRungOfItsLadder() {
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 21), 0)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 22), 1)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 23), 1)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 24), 2)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 39), 7)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 42), 8)
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 55), 11)
        // The bottom of the corridor the app offers: five seconds is far below
        // tier 1's floor and settles on the bottom of the scale, not on NaN.
        XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: 1, sets: 3, actual: 5), 0)
    }

    /// An actual below the bottom of the range drops the level into the previous tier (continuous formula).
    func testOverrideBelowRangeDropsToLowerTier() {
        // tier 2 starts at 6 reps, so an actual of 3 sits three steps below
        // its floor: (2-1)*8 + (3-6) = 5 → tier 1, 13 reps
        let l = Level.fromActual(pattern: .squat, tier: 2, sets: 3, actual: 3)
        XCTAssertEqual(l, 5)
        XCTAssertEqual(Level.decode(l).tier, 1)
        XCTAssertEqual(Level.decode(l).reps, 13)
    }

    /// Extreme actuals clamp to [0, levelMax].
    func testOverrideExtremesClamp() {
        XCTAssertEqual(Level.fromActual(pattern: .squat, tier: 1, sets: 3, actual: 0), 0)
        XCTAssertEqual(Level.fromActual(pattern: .squat, tier: 4, sets: 5, actual: 99),
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
        // pull: 4 × (+2) through tier 1, then one step per session — the
        // tier-2 and -3 cells hold it to +1 from level 8 on (#76).
        // v2.22 (spec §33): the run-up is longer — "more" is worth two
        // SUB-STEPS, not two levels — and the landing is derived, not pinned.
        var state = EngineState.initial
        for _ in 0..<60 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .more)
        }
        XCTAssertGreaterThanOrEqual(state.levels[.pull] ?? 0, 12,
                                    "the run-up must clear tier 2 for the descent to be visible")

        // Three sessions in a row we drop pull via a "plan − 2" actual.
        // Re-marked for v2.14 (spec §25.3): the landing is no longer a flat
        // "level − 2". A fact below the tier's floor means "this variation is
        // beyond me", so the descent goes to the floor of an easier tier —
        // what it may never do is hand back a HEAVIER plan, which is what the
        // old arithmetic did (repStart grows down the tiers). The deload
        // machinery itself is unchanged: the streak counts and resets.
        for i in 1...3 {
            let before = state.levels[.pull] ?? 0
            let s = Engine.generateSession(state)
            let ex = s.exercises.first { $0.pattern == .pull }!
            state = Engine.applyFeedback(state: state, session: s,
                                         result: .plan, overrides: [.pull: ex.load - 2])
            let after = state.levels[.pull] ?? 0
            XCTAssertLessThan(after, before, "step \(i): an underperformance goes down")
            XCTAssertTrue(Level.noHarder(pattern: .pull, from: before, to: after, fromCut: 0, toCut: 0),
                          "step \(i): the descent never asks for more work")
            if i == 3 {
                XCTAssertEqual(state.failStreak[.pull], 0, "after a deload the streak must reset")
            } else {
                XCTAssertEqual(state.failStreak[.pull], i)
            }
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

    /// All display strings are non-empty and contain numbers (for any levels,
    /// including the four- and five-set bands).
    func testDisplayStringsWellFormed() {
        var state = EngineState.initial
        for step in 0..<48 {
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
