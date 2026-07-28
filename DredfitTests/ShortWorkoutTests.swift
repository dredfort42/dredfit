//
//  ShortWorkoutTests.swift
//  DredfitTests
//
//  The short workout's selection rule (issue #27). The rule is a pure
//  function of (session, counter, levels), so the tests are exhaustive
//  rather than illustrative: the coverage property — every movement trained
//  at least once in any 8 consecutive short workouts — is the whole reason
//  the anchor exists, and it is checked by simulation, not by example.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class ShortWorkoutTests: XCTestCase {

    private func state(counter: Int, levels: [Pattern: Int] = [:], hasBar: Bool = false)
        -> EngineState {
        var state = EngineState.initial
        state.counter = counter
        state.hasBar = hasBar
        for (pattern, level) in levels { state.levels[pattern] = level }
        return state
    }

    private func plan(_ state: EngineState) -> Set<Pattern> {
        let session = Engine.generateSession(state)
        return ShortWorkout.plan(session: session,
                                 counter: state.counter,
                                 levels: state.levels)!
    }

    // MARK: - The three slots

    func testAlwaysThreeExercises() {
        for counter in 0..<24 {
            XCTAssertEqual(plan(state(counter: counter)).count, ShortWorkout.exerciseCount,
                           "counter \(counter) did not yield three exercises")
        }
    }

    func testPullSlotIsAlwaysKept() {
        for counter in 0..<24 {
            let chosen = plan(state(counter: counter))
            XCTAssertTrue(chosen.contains(.pull),
                          "counter \(counter): the pull slot must never be dropped")
        }
    }

    func testBarSessionsKeepTheVerticalPullSlot() {
        // With the bar on, odd counters hand the pull slot to pull_bar — the
        // short version has to follow the branch the session actually took.
        for counter in stride(from: 1, to: 16, by: 2) {
            let chosen = plan(state(counter: counter, hasBar: true))
            XCTAssertTrue(chosen.contains(.pullBar),
                          "counter \(counter): the bar session's pull slot is pull_bar")
            XCTAssertFalse(chosen.contains(.pull))
        }
    }

    func testAnchorIsTheFirstMovementOfTheRotationWindow() {
        for counter in 0..<24 {
            let anchor = Engine.rotationAnchor(counter: counter)
            XCTAssertTrue(plan(state(counter: counter)).contains(anchor),
                          "counter \(counter): the anchor \(anchor.rawValue) must be trained")
        }
    }

    func testLaggardIsTheLowestOfWhatRemains() {
        // calf at 0 against everything else at 12: whenever calf is in the
        // session and is neither the pull slot nor the anchor, it must be
        // the third pick.
        var levels = Dictionary(uniqueKeysWithValues: Pattern.ordered.map { ($0, 12) })
        levels[.calf] = 0
        for counter in 0..<24 {
            let current = state(counter: counter, levels: levels)
            let session = Engine.generateSession(current)
            guard session.exercises.contains(where: { $0.pattern == .calf }) else { continue }
            XCTAssertTrue(plan(current).contains(.calf),
                          "counter \(counter): the laggard must be picked up")
        }
    }

    func testSelectionIsDeterministic() {
        let current = state(counter: 5, levels: [.squat: 7, .calf: 3])
        let first = plan(current)
        for _ in 0..<10 { XCTAssertEqual(plan(current), first) }
    }

    func testTieOnLevelsResolvesBySessionOrder() {
        // Everything level 0: the laggard is a tie across four movements, and
        // the winner must be the one the flow would reach first.
        let current = state(counter: 3)
        let session = Engine.generateSession(current)
        let chosen = plan(current)
        let anchor = Engine.rotationAnchor(counter: 3)
        let expected = session.exercises
            .map(\.pattern)
            .first { $0 != .pull && $0 != .pullBar && $0 != anchor }
        XCTAssertTrue(chosen.contains(try XCTUnwrap(expected)),
                      "the tie must go to the earliest exercise in the session")
    }

    // MARK: - The property the anchor exists for

    func testEveryMovementIsTrainedWithinEightShortWorkouts() {
        // Nothing but short workouts, from uneven levels, for 8 sessions in a
        // row: the union has to cover all nine rotation patterns. This is the
        // claim the naive "pull + two lowest" rule failed.
        var levels = Dictionary(uniqueKeysWithValues: Pattern.ordered.map { ($0, 10) })
        levels[.squat] = 25
        levels[.pushH] = 22
        levels[.hinge] = 18
        for start in 0..<8 {
            var covered: Set<Pattern> = []
            for counter in start..<(start + 8) {
                covered.formUnion(plan(state(counter: counter, levels: levels)))
            }
            XCTAssertEqual(covered, Set(Pattern.ordered),
                           "starting at \(start), these were never trained: "
                           + "\(Set(Pattern.ordered).subtracting(covered).map(\.rawValue))")
        }
    }

    func testNoMovementWaitsLongerThanEightSessions() {
        let levels = Dictionary(uniqueKeysWithValues: Pattern.ordered.map { ($0, 10) })
        var lastSeen: [Pattern: Int] = [:]
        var worstGap = 0
        for counter in 0..<64 {
            for pattern in plan(state(counter: counter, levels: levels)) {
                if let previous = lastSeen[pattern] {
                    worstGap = max(worstGap, counter - previous)
                }
                lastSeen[pattern] = counter
            }
        }
        XCTAssertLessThanOrEqual(worstGap, 8, "a movement waited \(worstGap) sessions")
    }

    // MARK: - The estimate

    func testEstimateIsShorterThanTheFullSessionAndCountsWarmupAndCooldown() {
        let current = state(counter: 0)
        let session = Engine.generateSession(current)
        let chosen = ShortWorkout.plan(session: session, counter: 0,
                                       levels: current.levels)!
        let short = ShortWorkout.estimatedMin(session: session, plan: chosen)
        XCTAssertLessThan(Double(short), session.estimatedTotalMin,
                          "the short version must be shorter")
        XCTAssertGreaterThan(short, EngineConfig.warmupMin + EngineConfig.cooldownMin,
                             "warm-up and cool-down are part of the promise")
    }

    /// The engine's own arithmetic, not a copy: a full list must reproduce
    /// the session's own estimate exactly.
    func testEstimateMatchesTheEngineForTheWholeSession() {
        let session = Engine.generateSession(state(counter: 0))
        XCTAssertEqual(Engine.estimatedMin(exercises: session.exercises),
                       session.estimatedTotalMin)
    }
}
