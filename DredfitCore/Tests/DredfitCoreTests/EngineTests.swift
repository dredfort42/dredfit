//
//  EngineTests.swift
//  Engine v2.1 invariants (port of the verify2.js checks).
//

import XCTest
@testable import DredfitCore

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

    // MARK: Honest skips (v2.1.1)

    /// A state with non-zero levels and zero streaks (5 "plan" sessions).
    private func warmedUpState() -> EngineState {
        var state = EngineState.initial
        for _ in 0..<5 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .plan)
        }
        return state
    }

    func testSkippedPatternKeepsLevelAndStreak() {
        let state = warmedUpState()
        let s = Engine.generateSession(state)
        for result in [FeedbackResult.less, .plan, .more] {
            for ex in s.exercises {
                let p = ex.pattern
                let after = Engine.applyFeedback(state: state, session: s,
                                                 result: result, skipped: [p])
                XCTAssertEqual(after.levels[p], state.levels[p],
                               "\(result)/\(p): a skipped pattern must not change level")
                XCTAssertEqual(after.failStreak[p], state.failStreak[p],
                               "\(result)/\(p): a skipped pattern must not change streak")
                XCTAssertEqual(after.counter, state.counter + 1)
                // a neighbour still moves by the ordinary delta
                let other = s.exercises.first { $0.pattern != p }!.pattern
                let expected = min(max((state.levels[other] ?? 0) + result.delta, 0),
                                   EngineConfig.levelMax)
                XCTAssertEqual(after.levels[other], expected,
                               "\(result)/\(p): neighbour \(other) moved wrong")
            }
        }
    }

    func testSkipBeatsOverride() {
        let state = warmedUpState()
        let s = Engine.generateSession(state)
        let p = s.exercises[0].pattern
        let after = Engine.applyFeedback(state: state, session: s, result: .plan,
                                         overrides: [p: 14], skipped: [p])
        XCTAssertEqual(after.levels[p], state.levels[p],
                       "an override for a skipped pattern must be ignored")
    }

    func testAllSkippedAdvancesOnlyCounter() {
        let state = warmedUpState()
        let s = Engine.generateSession(state)
        let after = Engine.applyFeedback(state: state, session: s, result: .more,
                                         skipped: Set(s.exercises.map(\.pattern)))
        XCTAssertEqual(after.counter, state.counter + 1)
        XCTAssertEqual(after.levels, state.levels, "all skipped: levels must stay")
        XCTAssertEqual(after.failStreak, state.failStreak, "all skipped: streaks must stay")
    }

    func testSkipOutsideSessionIsNoop() {
        let state = warmedUpState()
        let s = Engine.generateSession(state)
        let inSession = Set(s.exercises.map(\.pattern))
        let outside = Pattern.ordered.first { !inSession.contains($0) }!
        let a = Engine.applyFeedback(state: state, session: s, result: .plan)
        let b = Engine.applyFeedback(state: state, session: s, result: .plan,
                                     skipped: [outside])
        XCTAssertEqual(a, b, "skipping a pattern outside the session must be a no-op")
    }

    func testSkipFreezesFailStreakAndPostponesDeload() {
        // pump pull up, then two real underperformances → streak 2
        var state = EngineState.initial
        for _ in 0..<8 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .more)
        }
        for _ in 0..<2 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .less)
        }
        XCTAssertEqual(state.failStreak[.pull], 2, "setup: pull must be at streak 2")
        let level = state.levels[.pull]!

        // a skipped "less" session: the streak is frozen, not reset
        let frozen = Engine.applyFeedback(state: state,
                                          session: Engine.generateSession(state),
                                          result: .less, skipped: [.pull])
        XCTAssertEqual(frozen.failStreak[.pull], 2, "skip must freeze the streak")
        XCTAssertEqual(frozen.levels[.pull], level, "skip must keep the level")

        // the next real underperformance is the 3rd → deload −1−3
        let deloaded = Engine.applyFeedback(state: frozen,
                                            session: Engine.generateSession(frozen),
                                            result: .less)
        XCTAssertEqual(deloaded.levels[.pull], level - 1 - EngineConfig.deloadDrop,
                       "the 3rd real fail after a freeze must deload")
        XCTAssertEqual(deloaded.failStreak[.pull], 0, "deload must reset the streak")
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
