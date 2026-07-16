//
//  EngineTests.swift
//  Engine v2.1 invariants (port of the verify2.js checks).
//

import XCTest
@testable import DredfitCore

// Disambiguate from the Pattern type introduced in the macOS 26 SDK
private typealias Pattern = DredfitCore.Pattern

final class EngineTests: XCTestCase {

    // MARK: Level encoding

    func testLevelDecodeBounds() {
        for l in 0...EngineConfig.levelMax {
            let d = Level.decode(l)
            XCTAssertTrue((1...EngineConfig.tiers).contains(d.tier), "L=\(l) tier")
            XCTAssertTrue((8...15).contains(d.reps), "L=\(l) reps")
            XCTAssertTrue((20...55).contains(d.hold), "L=\(l) hold")
        }
    }

    func testLevelDecodeTierTransitions() {
        XCTAssertEqual(Level.decode(7), LevelDecoded(tier: 1, reps: 15, hold: 55))
        XCTAssertEqual(Level.decode(8), LevelDecoded(tier: 2, reps: 8, hold: 20))
        XCTAssertEqual(Level.decode(23), LevelDecoded(tier: 3, reps: 15, hold: 55))
        XCTAssertEqual(Level.decode(24), LevelDecoded(tier: 4, reps: 8, hold: 20))  // v2.1
        XCTAssertEqual(Level.decode(31), LevelDecoded(tier: 4, reps: 15, hold: 55)) // ceiling
    }

    func testLevelDecodeClamps() {
        XCTAssertEqual(Level.decode(999).tier, EngineConfig.tiers)
        XCTAssertEqual(Level.decode(-5), Level.decode(0))
    }

    // MARK: Rotation v2.1

    func testPullInEverySessionAndRotationCoverage() {
        var state = EngineState.initial
        var seen: [Pattern: Int] = [:]
        for k in 0..<8 {
            let s = Engine.generateSession(state)
            XCTAssertEqual(s.exercises.count, EngineConfig.patternsPerSession)
            let pats = s.exercises.map(\.pattern)
            XCTAssertEqual(Set(pats).count, pats.count, "duplicate pattern in session \(k)")
            XCTAssertTrue(pats.contains(.pull), "session \(k): no pull (fixed slot)")
            pats.forEach { seen[$0, default: 0] += 1 }
            state = Engine.applyFeedback(state: state, session: s, result: .plan)
        }
        XCTAssertEqual(seen[.pull], 8, "pull should be in each of the 8 sessions")
        for p in Pattern.ordered where p != .pull {
            XCTAssertEqual(seen[p], 5, "\(p): exactly 5 inclusions over 8 sessions")
        }
    }

    func testWeeklyPullPushBalance() {
        // 6 sessions (a week): pull is at least 0.7× the push volume
        var state = EngineState.initial
        var push = 0, pull = 0
        for _ in 0..<6 {
            let s = Engine.generateSession(state)
            for ex in s.exercises {
                if ex.pattern == .pushH || ex.pattern == .pushV { push += ex.sets }
                if ex.pattern == .pull { pull += ex.sets }
            }
            state = Engine.applyFeedback(state: state, session: s, result: .plan)
        }
        XCTAssertGreaterThanOrEqual(Double(pull), Double(push) * 0.7,
            "push/pull balance broken: pull=\(pull), push=\(push)")
    }

    // MARK: Regulator scenarios

    func testAlwaysPlanReachesCeiling() {
        var state = EngineState.initial
        for _ in 0..<60 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .plan)
        }
        // pull: +60; the rest: 5/8 × 60 ≈ +37 — all above the ceiling of 31
        for p in Pattern.ordered {
            XCTAssertEqual(state.levels[p], EngineConfig.levelMax, "\(p) not at the ceiling")
        }
        let s = Engine.generateSession(state)
        for ex in s.exercises {
            XCTAssertEqual(ex.tier, EngineConfig.tiers, "at the ceiling tier \(EngineConfig.tiers) is expected")
        }
    }

    func testAlwaysLessFloorsAtZero() {
        var state = EngineState.initial
        for _ in 0..<20 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .less)
            for p in Pattern.ordered {
                XCTAssertGreaterThanOrEqual(state.levels[p]!, 0)
            }
        }
        for p in Pattern.ordered { XCTAssertEqual(state.levels[p], 0) }
    }

    func testDeloadFiresOnThirdConsecutiveFail() {
        var state = EngineState.initial
        for _ in 0..<15 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .more)
        }
        let probe = Engine.generateSession(state).exercises[0].pattern
        var drops = 0
        var deloadSeen = false
        for _ in 0..<6 {
            let s = Engine.generateSession(state)
            let inSession = s.exercises.contains { $0.pattern == probe }
            let before = state.levels[probe]!
            state = Engine.applyFeedback(state: state, session: s, result: .less)
            guard inSession else { continue }
            drops += 1
            let diff = before - state.levels[probe]!
            if drops % EngineConfig.failsToDeload == 0 {
                XCTAssertEqual(diff, 1 + EngineConfig.deloadDrop, "deload on the 3rd underperformance")
                deloadSeen = true
            } else {
                XCTAssertEqual(diff, 1)
            }
        }
        XCTAssertTrue(deloadSeen)
    }

    func testOverrideCapsUpwardGrowth() {
        let state = EngineState.initial
        let s = Engine.generateSession(state)
        guard let ex = s.exercises.first(where: { $0.unit == .reps }) else {
            return XCTFail("no rep-based exercise in the first session")
        }
        // plan 8 reps (level 0), actual 14 → growth capped at +2
        let next = Engine.applyFeedback(state: state, session: s, result: .plan,
                                        overrides: [ex.pattern: 14])
        XCTAssertEqual(next.levels[ex.pattern], 2)
    }

    func testDeterminism() {
        let a = Engine.generateSession(.initial)
        let b = Engine.generateSession(.initial)
        XCTAssertEqual(a, b)
    }

    func testStateRoundTripsThroughCodable() throws {
        var state = EngineState.initial
        for _ in 0..<5 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .more)
        }
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    // MARK: Library

    func testLibraryComplete() {
        for p in Pattern.ordered {
            let e = ExerciseLibrary.entry(for: p)
            XCTAssertEqual(e.variations.count, EngineConfig.tiers, "\(p): \(EngineConfig.tiers) tiers")
            for v in e.variations {
                XCTAssertEqual(v.steps.count, 3, "\(v.name): 3 technique steps")
                XCTAssertEqual(v.mistakes.count, 2, "\(v.name): 2 mistakes")
                XCTAssertFalse(v.name.isEmpty)
            }
        }
    }
}
