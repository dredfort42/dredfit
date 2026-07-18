//
//  EngineTests.swift
//  Engine v2.2 invariants (port of the verify2.js checks).
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
            XCTAssertTrue((EngineConfig.setsBase...EngineConfig.setsMax).contains(d.sets), "L=\(l) sets")
            // v2.3: the range is per tier — 8...15 / 6...13 / 5...12 / 4...11
            let repLo = EngineConfig.repStart[d.tier]!
            let holdLo = EngineConfig.holdStart[d.tier]!
            XCTAssertTrue((repLo...(repLo + EngineConfig.stepsPerTier - 1)).contains(d.reps),
                          "L=\(l) reps \(d.reps) outside tier \(d.tier) range")
            XCTAssertTrue((holdLo...(holdLo + (EngineConfig.stepsPerTier - 1) * EngineConfig.holdStepSec))
                            .contains(d.hold),
                          "L=\(l) hold \(d.hold) outside tier \(d.tier) range")
        }
    }

    func testLevelDecodeTierTransitions() {
        XCTAssertEqual(Level.decode(7), LevelDecoded(tier: 1, sets: 3, reps: 15, hold: 55))
        // v2.3: each tier starts lower, so entering a tier is a step down in
        // reps — the whole point of the smoothing.
        XCTAssertEqual(Level.decode(8), LevelDecoded(tier: 2, sets: 3, reps: 6, hold: 15))
        XCTAssertEqual(Level.decode(23), LevelDecoded(tier: 3, sets: 3, reps: 12, hold: 50))
        XCTAssertEqual(Level.decode(24), LevelDecoded(tier: 4, sets: 3, reps: 4, hold: 10))
        XCTAssertEqual(Level.decode(31), LevelDecoded(tier: 4, sets: 3, reps: 11, hold: 45))
        // v2.2: set bands above tier 4
        XCTAssertEqual(Level.decode(32), LevelDecoded(tier: 4, sets: 4, reps: 4, hold: 10))
        XCTAssertEqual(Level.decode(39), LevelDecoded(tier: 4, sets: 4, reps: 11, hold: 45))
        XCTAssertEqual(Level.decode(40), LevelDecoded(tier: 4, sets: 5, reps: 4, hold: 10))
        XCTAssertEqual(Level.decode(47), LevelDecoded(tier: 4, sets: 5, reps: 11, hold: 45)) // ceiling
    }

    func testLevelDecodeClamps() {
        XCTAssertEqual(Level.decode(999).tier, EngineConfig.tiers)
        XCTAssertEqual(Level.decode(999).sets, EngineConfig.setsMax)
        XCTAssertEqual(Level.decode(-5), Level.decode(0))
    }

    /// v2.2: level → tier/sets/load → level round-trips on the whole 0...47,
    /// including pullBar whose unit switches from hold (tier 1) to reps.
    func testLevelEncodingRoundTripsWithSets() {
        for l in 0...EngineConfig.levelMax {
            let d = Level.decode(l)
            XCTAssertEqual(Level.fromActual(pattern: .squat, tier: d.tier,
                                            sets: d.sets, actual: d.reps), l, "reps L=\(l)")
            XCTAssertEqual(Level.fromActual(pattern: .coreAntiExt, tier: d.tier,
                                            sets: d.sets, actual: d.hold), l, "hold L=\(l)")
            let barActual = ExerciseLibrary.entry(for: .pullBar)
                .unit(forTier: d.tier) == .hold ? d.hold : d.reps
            XCTAssertEqual(Level.fromActual(pattern: .pullBar, tier: d.tier,
                                            sets: d.sets, actual: barActual), l, "pullBar L=\(l)")
        }
        // The spec's worked example: an actual below the band's floor drops back
        // a band. v2.3 moved the tier-4 floor from 8 reps to 4, so the example
        // input moves with it (6 → 2) — the property under test is unchanged.
        XCTAssertEqual(Level.fromActual(pattern: .pull, tier: 4, sets: 4, actual: 2), 30)
        XCTAssertEqual(Level.decode(30), LevelDecoded(tier: 4, sets: 3, reps: 10, hold: 40))
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
        for _ in 0..<80 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .plan)
        }
        // pull: +80; the rest: 5/8 × 80 = +50 — all above the v2.2 ceiling of 47
        for p in Pattern.ordered {
            XCTAssertEqual(state.levels[p], EngineConfig.levelMax, "\(p) not at the ceiling")
        }
        let s = Engine.generateSession(state)
        for ex in s.exercises {
            XCTAssertEqual(ex.tier, EngineConfig.tiers, "at the ceiling tier \(EngineConfig.tiers) is expected")
            XCTAssertEqual(ex.sets, EngineConfig.setsMax, "at the ceiling \(EngineConfig.setsMax) sets are expected")
            // v2.3: the ceiling is the top step of tier 4 — 11 reps / 45 s.
            XCTAssertEqual(ex.load, ex.unit == .reps ? 11 : 45,
                           "at the ceiling the load must be the top of tier 4")
        }
    }

    /// v2.2: the regulator works across set-band boundaries with no special cases.
    func testRegulatorCrossesBandBoundaries() {
        // "more" at 31 crosses into the 4-set band: 31 → 33
        var state = EngineState.initial
        state.levels[.pull] = 31
        var s = Engine.generateSession(state)
        XCTAssertEqual(s.exercises.first { $0.pattern == .pull }?.sets, 3)
        state = Engine.applyFeedback(state: state, session: s, result: .more)
        XCTAssertEqual(state.levels[.pull], 33, "«more» must cross the band boundary 31 → 33")
        s = Engine.generateSession(state)
        let ex = s.exercises.first { $0.pattern == .pull }!
        XCTAssertEqual(ex.sets, 4)
        XCTAssertEqual(ex.load, 5, "33 = 4×5 (v2.3: tier 4 starts at 4 reps)")

        // a third consecutive fail at 33 deloads back across the boundary: 33 → 32−3 = 29
        state.failStreak[.pull] = 2
        state = Engine.applyFeedback(state: state, session: s, result: .less)
        XCTAssertEqual(state.levels[.pull], 29, "deload must cross back into the 3-set band")
        XCTAssertEqual(state.failStreak[.pull], 0)
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
        // v2.3: from zero there is no cap — the fact IS the calibration.
        let next = Engine.applyFeedback(state: state, session: s, result: .plan,
                                        overrides: [ex.pattern: 14])
        XCTAssertEqual(next.levels[ex.pattern], 6, "a fact from zero sets the level exactly")

        // The cap still applies once the level is non-zero. Uses pull, which is
        // in every session, so the override is guaranteed to land.
        let before = next.levels[.pull] ?? 0
        XCTAssertGreaterThan(before, 0, "pull must be above zero for the cap to apply")
        let capped = Engine.applyFeedback(state: next, session: Engine.generateSession(next),
                                          result: .plan, overrides: [.pull: 99])
        XCTAssertEqual(capped.levels[.pull], before + EngineConfig.maxUpPerSession,
                       "above zero the +2 cap is unchanged")
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

    // MARK: Pull-up bar module (v2.2)

    /// With hasBar off, generation is fully independent of the pullBar branch
    /// and the branch stays frozen through feedback.
    func testHasBarOffIgnoresBarBranch() {
        var plain = EngineState.initial
        var loaded = EngineState.initial
        loaded.levels[.pullBar] = 47
        loaded.failStreak[.pullBar] = 2
        for k in 0..<8 {
            let a = Engine.generateSession(plain)
            let b = Engine.generateSession(loaded)
            XCTAssertEqual(a, b, "session \(k) depends on the pullBar branch")
            XCTAssertFalse(a.exercises.contains { $0.pattern == .pullBar })
            plain = Engine.applyFeedback(state: plain, session: a, result: .plan)
            loaded = Engine.applyFeedback(state: loaded, session: b, result: .plan)
            XCTAssertEqual(loaded.levels[.pullBar], 47, "the frozen branch must keep its level")
            XCTAssertEqual(loaded.failStreak[.pullBar], 2, "the frozen branch must keep its streak")
        }
    }

    /// With hasBar on, the pull slot alternates deterministically by counter
    /// parity, and the 8-pattern rotation property is untouched.
    func testHasBarAlternatesPullSlot() {
        var state = EngineState.initial
        state.hasBar = true
        var seen: [Pattern: Int] = [:]
        for k in 0..<16 {
            let s = Engine.generateSession(state)
            let pats = s.exercises.map(\.pattern)
            XCTAssertEqual(Set(pats).count, pats.count, "duplicate pattern in session \(k)")
            let hasPull = pats.contains(.pull), hasBar = pats.contains(.pullBar)
            XCTAssertNotEqual(hasPull, hasBar, "session \(k): exactly one pull slot")
            XCTAssertEqual(state.counter % 2 == 0, hasPull,
                           "session \(k): even counter → pull, odd → pullBar")
            // pullBar inherits pull's position in the canonical order
            let indices = pats.map { Pattern.ordered.firstIndex(of: $0 == .pullBar ? .pull : $0)! }
            XCTAssertEqual(indices, indices.sorted(), "session \(k): order broken")
            pats.forEach { seen[$0, default: 0] += 1 }
            state = Engine.applyFeedback(state: state, session: s, result: .plan)
        }
        XCTAssertEqual(seen[.pull], 8, "16 sessions: 8 horizontal")
        XCTAssertEqual(seen[.pullBar], 8, "16 sessions: 8 vertical")
        for p in Pattern.ordered where p != .pull {
            XCTAssertEqual(seen[p], 10, "\(p): 10 inclusions over 16 sessions")
        }
    }

    /// The pull and pullBar branches are fully independent: a session with one
    /// never moves the other's level or streak.
    func testPullBranchesAreIndependent() {
        var state = EngineState.initial
        state.hasBar = true
        for _ in 0..<6 {
            let s = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: s, result: .more)
        }
        XCTAssertEqual(state.counter % 2, 0, "setup: expected a pull session next")
        let barLevel = state.levels[.pullBar]!
        let barStreak = state.failStreak[.pullBar]!

        let pullSession = Engine.generateSession(state)
        let afterPull = Engine.applyFeedback(state: state, session: pullSession, result: .less)
        XCTAssertEqual(afterPull.levels[.pullBar], barLevel, "a pull session moved pullBar")
        XCTAssertEqual(afterPull.failStreak[.pullBar], barStreak)
        XCTAssertEqual(afterPull.levels[.pull], state.levels[.pull]! - 1)

        let barSession = Engine.generateSession(afterPull)
        XCTAssertTrue(barSession.exercises.contains { $0.pattern == .pullBar })
        let afterBar = Engine.applyFeedback(state: afterPull, session: barSession, result: .less)
        XCTAssertEqual(afterBar.levels[.pull], afterPull.levels[.pull], "a bar session moved pull")
        XCTAssertEqual(afterBar.failStreak[.pull], afterPull.failStreak[.pull])
        XCTAssertEqual(afterBar.levels[.pullBar], barLevel - 1)
    }

    /// The bar ladder starts as a hold (hang) and switches to reps at tier 2;
    /// the session exercise carries the per-tier unit.
    func testBarUnitFollowsTier() {
        var state = EngineState.initial
        state.hasBar = true
        state.counter = 1                     // odd → bar session
        var s = Engine.generateSession(state)
        var bar = s.exercises.first { $0.pattern == .pullBar }!
        XCTAssertEqual(bar.unit, .hold)
        XCTAssertEqual(bar.tier, 1)
        XCTAssertEqual(bar.load, 20, "the ladder starts with a 20 s hang")
        XCTAssertFalse(bar.perSide, "bar exercises are bilateral")

        state.levels[.pullBar] = 8            // tier 2 — negatives, reps
        s = Engine.generateSession(state)
        bar = s.exercises.first { $0.pattern == .pullBar }!
        XCTAssertEqual(bar.unit, .reps)
        XCTAssertEqual(bar.tier, 2)
        XCTAssertEqual(bar.load, 6, "v2.3: tier 2 starts at 6 reps")
    }

    /// Skips (v2.1.1) apply to the bar branch with zero special cases:
    /// a skipped bar session freezes its non-zero streak.
    func testSkipFreezesBarStreak() {
        var state = EngineState.initial
        state.hasBar = true
        state.counter = 1
        state.levels[.pullBar] = 6
        state.failStreak[.pullBar] = 1
        let s = Engine.generateSession(state)
        let after = Engine.applyFeedback(state: state, session: s, result: .less,
                                         overrides: [.pullBar: 40], skipped: [.pullBar])
        XCTAssertEqual(after.levels[.pullBar], 6, "skip must keep the bar level")
        XCTAssertEqual(after.failStreak[.pullBar], 1, "skip must freeze the bar streak")
    }

    /// A v2.1-era JSON state (9 patterns, no hasBar) decodes with the defaults.
    func testLegacyStateDecodesWithBarDefaults() throws {
        let legacy = """
        {"counter":5,
         "levels":["squat",2,"push_h",3,"hinge",2,"pull",5,"push_v",2,"lunge",2,
                   "core_anti_ext",1,"core_rot",1,"calf",1],
         "failStreak":["squat",0,"push_h",0,"hinge",0,"pull",1,"push_v",0,"lunge",0,
                       "core_anti_ext",0,"core_rot",0,"calf",0]}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertFalse(state.hasBar, "old files must decode with hasBar off")
        XCTAssertEqual(state.levels[.pullBar], 0, "the bar branch must default to level 0")
        XCTAssertEqual(state.failStreak[.pullBar], 0)
        XCTAssertEqual(state.levels[.pull], 5, "existing levels must survive")
    }

    // MARK: Library

    func testLibraryComplete() {
        var positions = 0
        for p in Pattern.allCases {
            let e = ExerciseLibrary.entry(for: p)
            XCTAssertEqual(e.variations.count, EngineConfig.tiers, "\(p): \(EngineConfig.tiers) tiers")
            for (i, v) in e.variations.enumerated() {
                positions += 1
                XCTAssertEqual(v.steps.count, 3, "\(v.name): 3 technique steps")
                XCTAssertEqual(v.mistakes.count, 2, "\(v.name): 2 mistakes")
                XCTAssertFalse(v.name.isEmpty)
                XCTAssertTrue([LoadUnit.reps, .hold].contains(e.unit(forTier: i + 1)))
            }
        }
        XCTAssertEqual(positions, 40, "v2.2 library: 40 positions")
        // pullBar: hold at tier 1, reps above; all bilateral
        let bar = ExerciseLibrary.entry(for: .pullBar)
        XCTAssertEqual((1...4).map { bar.unit(forTier: $0) }, [.hold, .reps, .reps, .reps])
        XCTAssertTrue(bar.variations.allSatisfy { !$0.unilateral }, "bar exercises are bilateral")
    }
}
