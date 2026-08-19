//
//  EngineV23Tests.swift
//  DredfitCoreTests
//
//  Zero-level calibration, comeback after a break, and per-tier rep/hold
//  starts. Mirrors the corresponding blocks in the reference verifier —
//  anything asserted here is asserted there too.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV23Tests: XCTestCase {

    // MARK: - Calibration (C1)

    /// From zero a pointed fact sets the level exactly, across the whole of
    /// tier 1 and in both units. This is what lets a trained beginner reach
    /// their real load in one workout instead of ten. The bottom row moved
    /// in v2.8 (spec §18.1): a fact EQUAL to the plan now steps like "on
    /// plan" — EngineV28Tests pins it — so the exact inversion starts at 1.
    func testFactFromZeroSetsTheLevelExactly() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)

        for ex in session.exercises {
            for level in 1...7 {
                let actual = ex.unit == .reps
                    ? EngineConfig.repStart[1]! + level
                    : EngineConfig.holdStart[1]! + level * EngineConfig.holdStepSec
                let next = Engine.applyFeedback(state: state, session: session,
                                                result: .plan,
                                                overrides: [ex.pattern: actual])
                XCTAssertEqual(next.levels[ex.pattern], level,
                               "\(ex.pattern.rawValue): actual \(actual) should calibrate to \(level)")
            }
        }
    }

    /// Calibration is strictly a zero-level affair: one step above it the +2
    /// cap is back.
    func testCapReturnsOnceTheLevelIsNonZero() {
        let state = EngineState.initial
        let first = Engine.applyFeedback(state: state,
                                         session: Engine.generateSession(state),
                                         result: .plan, overrides: [.pull: 20])
        XCTAssertEqual(first.levels[.pull], 12, "calibrated straight to 12")

        let second = Engine.applyFeedback(state: first,
                                          session: Engine.generateSession(first),
                                          result: .plan, overrides: [.pull: 99])
        XCTAssertEqual(second.levels[.pull], 12 + EngineConfig.maxUp(pattern: .pull, tier: 2),
                       "above zero an enormous fact still only moves by the cell")
    }

    /// A fact below the plan at zero leaves the level at zero and does not
    /// start a shortfall streak — there is nowhere further down to go.
    func testFactBelowPlanAtZeroChangesNothing() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        guard let ex = session.exercises.first(where: { $0.unit == .reps }) else {
            return XCTFail("no rep-based exercise in the first session")
        }
        let next = Engine.applyFeedback(state: state, session: session, result: .plan,
                                        overrides: [ex.pattern: 5])
        XCTAssertEqual(next.levels[ex.pattern], 0)
        XCTAssertEqual(next.failStreak[ex.pattern], 0, "no streak from a floor that cannot fall")
    }

    /// A skip still outranks a fact, calibration included.
    func testSkipOutranksACalibratingFact() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        guard let ex = session.exercises.first(where: { $0.unit == .reps }) else {
            return XCTFail("no rep-based exercise in the first session")
        }
        let next = Engine.applyFeedback(state: state, session: session, result: .plan,
                                        overrides: [ex.pattern: 20], skipped: [ex.pattern])
        XCTAssertEqual(next.levels[ex.pattern], 0, "a skipped pattern was not trained")
        XCTAssertEqual(next.failStreak[ex.pattern], 0)
    }

    /// Ratings without a fact keep their old deltas at zero — there is nothing
    /// to calibrate from, so nothing changes.
    func testRatingWithoutAFactIsUnchangedAtZero() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        let next = Engine.applyFeedback(state: state, session: session, result: .more)
        for ex in session.exercises {
            XCTAssertEqual(next.levels[ex.pattern], EngineConfig.deltaMore,
                           "\(ex.pattern.rawValue) should move by the plain delta")
        }
    }

    /// The bar branch calibrates from zero whenever the bar is switched on.
    func testBarBranchCalibratesFromZero() {
        var state = EngineState.initial
        state.hasBar = true
        let session = Engine.generateSession(state)
        guard session.exercises.contains(where: { $0.pattern == .pullBar }) else { return }
        let next = Engine.applyFeedback(state: state, session: session, result: .plan,
                                        overrides: [.pullBar: 45])
        XCTAssertEqual(next.levels[.pullBar], 5, "a 45 s hang is level 5 on the spot")
    }

    // MARK: - Comeback (C2)

    private func seeded(level: Int, streak: Int, counter: Int = 7) -> EngineState {
        var state = EngineState.initial
        state.counter = counter
        for p in Pattern.allCases {
            state.levels[p] = level
            state.failStreak[p] = streak
        }
        return state
    }

    func testComebackIsNoOpBelowTheThreshold() {
        for gap in [0, 1, 7, 13] {
            let before = seeded(level: 20, streak: 2)
            let after = Engine.applyComeback(state: before, gapDays: gap)
            XCTAssertEqual(after, before, "a \(gap)-day gap must change nothing")
        }
    }

    func testComebackDropTable() {
        // v2.12 (spec §22.1-22.2): from L30 the table drop rules inside the
        // tier; from 56 days the ceiling ladder (tier bottoms) takes over,
        // and tier crossings land by rep continuity. Expected values are the
        // actual landings.
        let table: [(gap: Int, landed: Int)] = [
            (14, 28), (34, 28), (35, 27), (55, 27),
            (56, 24), (76, 24),          // ceiling 24: bottom of tier 4
            (77, 16), (98, 16),          // ceiling 16: bottom of tier 3
            (119, 8), (140, 8),          // ceiling 8: bottom of tier 2
        ]
        for (gap, landed) in table {
            let after = Engine.applyComeback(state: seeded(level: 30, streak: 1), gapDays: gap)
            XCTAssertEqual(after.levels[.squat], landed, "\(gap) days should land at \(landed)")
            XCTAssertEqual(after.levels[.pullBar], landed,
                           "\(gap) days: the bar branch drops with everything else")
        }
        // v2.12 (spec §22.2): the ladder's tail — 119-364 days land no higher
        // than the bottom of tier 2, a year is a clean slate.
        for (gap, ceil) in [(180, 8), (200, 8), (364, 8), (365, 0), (3650, 0)] {
            let after = Engine.applyComeback(state: seeded(level: 30, streak: 1), gapDays: gap)
            XCTAssertEqual(after.levels[.squat], ceil,
                           "\(gap) days: landing ceiling \(ceil)")
            XCTAssertEqual(after.levels[.pullBar], ceil,
                           "\(gap) days: the bar branch lands with everything else")
        }
    }

    /// Levels clamp at zero, every streak resets, and the counter does not move:
    /// no workouts happened, but no debt was incurred either.
    func testComebackClampsResetsStreaksAndKeepsTheCounter() {
        var before = seeded(level: 1, streak: 2)
        before.levels[.squat] = 0
        let after = Engine.applyComeback(state: before, gapDays: 140)

        for p in Pattern.allCases {
            XCTAssertEqual(after.levels[p], 0, "\(p.rawValue) clamps at zero")
            XCTAssertEqual(after.failStreak[p], 0, "\(p.rawValue) streak resets")
        }
        XCTAssertEqual(after.counter, before.counter)
        XCTAssertEqual(after.hasBar, before.hasBar)
    }

    /// A break detrains the whole body, so the vertical branch drops even when
    /// the bar is switched off.
    func testComebackDropsTheBarBranchRegardlessOfHasBar() {
        for hasBar in [false, true] {
            var before = seeded(level: 20, streak: 0)
            before.hasBar = hasBar
            let after = Engine.applyComeback(state: before, gapDays: 35)
            XCTAssertEqual(after.levels[.pullBar], 17, "hasBar=\(hasBar)")
            XCTAssertEqual(after.hasBar, hasBar, "comeback must not touch the toggle")
        }
    }

    /// v2.12 (spec §22.1): a tier crossing lands by rep CONTINUITY — the same
    /// dose of reps in an easier variation, never the same mod-8 rung (which
    /// used to land on the lower tier's top with a higher dose, audit A3-1).
    func testEightStepDropIsExactlyOneTierAtTheSameStep() {
        let after = Engine.applyComeback(state: seeded(level: 20, streak: 0), gapDays: 77)
        let level = after.levels[.squat] ?? -1
        let before = Level.decode(20), now = Level.decode(level)

        XCTAssertEqual(now.tier, before.tier - 1)
        XCTAssertEqual(now.reps, before.reps,
                       "the rep dose survives the change of variation")
        XCTAssertEqual(level, 11, "L20 after 77 days: tier 2 × 9")
    }

    /// The streak reset is the point: the first shortfall after a comeback is
    /// a plain −1, not a deload riding in on the old streak.
    func testFirstShortfallAfterComebackDoesNotDeload() {
        var state = EngineState.initial
        for _ in 0..<12 {
            state = Engine.applyFeedback(state: state,
                                         session: Engine.generateSession(state), result: .more)
        }
        for _ in 0..<2 {
            // v2.9: the subject is the comeback clearing the streak, so the
            // "less" is taken under a run — session-wide delta (spec §19.2).
            state = Engine.applyFeedback(state: state.underLessRun,
                                         session: Engine.generateSession(state), result: .less)
        }
        XCTAssertEqual(state.failStreak[.pull], 2, "two shortfalls banked")

        let back = Engine.applyComeback(state: state, gapDays: 30)
        XCTAssertEqual(back.failStreak[.pull], 0)

        let level = back.levels[.pull] ?? 0
        let after = Engine.applyFeedback(state: back.underLessRun,
                                         session: Engine.generateSession(back), result: .less)
        XCTAssertEqual(after.levels[.pull], level - 1,
                       "a plain −1, not −1−3: the old streak is gone")
        XCTAssertEqual(after.failStreak[.pull], 1, "the streak counts again from one")
    }

    /// Session generation after a comeback follows the encoding like any other
    /// state — the comeback produces a normal state, not a special mode.
    func testSessionAfterComebackMatchesTheEncoding() {
        let after = Engine.applyComeback(state: seeded(level: 25, streak: 2), gapDays: 60)
        let session = Engine.generateSession(after)

        XCTAssertEqual(session.exercises.count, EngineConfig.patternsPerSession)
        for ex in session.exercises {
            let decoded = Level.decode(after.levels[ex.pattern] ?? 0)
            XCTAssertEqual(ex.tier, decoded.tier)
            XCTAssertEqual(ex.sets, decoded.sets)
            XCTAssertEqual(ex.load, ex.unit == .reps ? decoded.reps : decoded.hold)
        }
    }

    // MARK: - Per-tier starts (C3)

    /// Every tier must have an explicit start — otherwise a future `tiers`
    /// bump would silently fall back to `?? repMin` / `?? holdMin` and skew
    /// the whole encoding for the new tier.
    func testPerTierStartsCoverEveryTier() {
        XCTAssertEqual(Set(EngineConfig.repStart.keys), Set(1...EngineConfig.tiers),
                       "repStart must define exactly tiers 1...\(EngineConfig.tiers)")
        XCTAssertEqual(Set(EngineConfig.holdStart.keys), Set(1...EngineConfig.tiers),
                       "holdStart must define exactly tiers 1...\(EngineConfig.tiers)")
    }

    func testForwardEncodingUsesPerTierStarts() {
        for level in 0...EngineConfig.levelMax {
            let d = Level.decode(level)
            let step = level % EngineConfig.stepsPerTier
            // Re-marked for v2.17 (spec §28.1): inside a sets band the start
            // and the step are the band's own — entering a band used to reset
            // the reps to the bottom of tier 4 and halve the actual work.
            let repStart = EngineConfig.repStartBand[d.sets] ?? EngineConfig.repStart[d.tier]!
            let holdStart = EngineConfig.holdStartBand[d.sets] ?? EngineConfig.holdStart[d.tier]!
            let holdStep = EngineConfig.holdStepBand[d.sets] ?? EngineConfig.holdStepSec
            XCTAssertEqual(d.reps, repStart + step, "L=\(level) reps")
            XCTAssertEqual(d.hold, holdStart + step * holdStep, "L=\(level) hold")
        }
    }

    /// Tier 1 keeps the original encoding — the per-tier floors only ever
    /// touch the tiers above it.
    func testTierOneIsUnchangedFromTheOldEncoding() {
        for level in 0...7 {
            let d = Level.decode(level)
            XCTAssertEqual(d.reps, 8 + level, "L=\(level) reps must match v2.2")
            XCTAssertEqual(d.hold, 20 + level * 5, "L=\(level) hold must match v2.2")
        }
    }

    /// Every level round-trips through the inverse for every pattern, tier,
    /// set band and unit.
    func testInverseInvertsTheNewEncodingEverywhere() {
        for pattern in Pattern.allCases {
            let lib = ExerciseLibrary.entry(for: pattern)
            for level in 0...EngineConfig.levelMax {
                let d = Level.decode(level)
                let actual = lib.unit(forTier: d.tier) == .reps ? d.reps : d.hold
                XCTAssertEqual(
                    Level.fromActual(pattern: pattern, tier: d.tier, sets: d.sets, actual: actual),
                    level, "\(pattern.rawValue) L=\(level) (tier \(d.tier), \(d.sets) sets)")
            }
        }
    }

    /// The whole point: entering a new tier asks for fewer reps than the top of
    /// the previous one, so a harder variation lands softly.
    func testEnteringATierAsksForFewerReps() {
        for level in [8, 16, 24] {
            let before = Level.decode(level - 1), after = Level.decode(level)
            XCTAssertEqual(after.tier, before.tier + 1)
            XCTAssertLessThan(after.reps, before.reps,
                              "L=\(level): \(before.reps) → \(after.reps) should be a step down")
        }
    }

    /// The level → (tier, step) mapping is still a bijection: 48 distinct pairs.
    func testEncodingRemainsBijective() {
        var seen = Set<String>()
        for level in 0...EngineConfig.levelMax {
            let d = Level.decode(level)
            let key = "\(d.tier)/\(d.sets)/\(level % EngineConfig.stepsPerTier)"
            XCTAssertFalse(seen.contains(key), "duplicate key \(key) at L=\(level)")
            seen.insert(key)
        }
        XCTAssertEqual(seen.count, EngineConfig.levelMax + 1)
    }
}
