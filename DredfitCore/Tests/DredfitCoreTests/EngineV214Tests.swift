//
//  EngineV214Tests.swift
//  DredfitCoreTests
//
//  Engine v2.14 (spec §25, issues #139/#140/#138): honest facts. Three ways
//  the model punished the trainee for reporting the truth, all with the same
//  root cause — rung arithmetic done in coordinates the fact does not live in:
//  the 5-second encoding step (#139), the sets the gate had already trimmed
//  (#140), and the lower tier's repStart, which grows DOWNWARD (#138).
//

import XCTest
@testable import DredfitCore

// macOS puts a C `Pattern` struct (Quickdraw) in scope, so the package
// build needs the name pinned — same line every test file in here carries.
private typealias Pattern = DredfitCore.Pattern

final class EngineV214Tests: XCTestCase {

    private func seeded(_ level: Int, _ over: [Pattern: Int] = [:]) -> EngineState {
        var s = EngineState.initial
        for p in Pattern.allCases { s.levels[p] = level }
        for (p, v) in over { s.levels[p] = v }
        return s
    }

    /// The rotation only shows five of the eight rotating patterns per
    /// session, so a probe has to walk the counter until the one it needs
    /// appears — the state is otherwise identical.
    private func exercise(_ p: Pattern, in state: EngineState) -> (EngineState, Session, SessionExercise)? {
        var probe = state
        for counter in 0..<EngineConfig.stepsPerTier {
            probe.counter = counter
            let s = Engine.generateSession(probe)
            if let ex = s.exercises.first(where: { $0.pattern == p }) { return (probe, s, ex) }
        }
        return nil
    }

    // MARK: - §25.1 A hold fact just above the plan (#139)

    func testHoldFactsJustAboveThePlanCountAsMeetingIt() throws {
        let seed = seeded(0, [.pull: EngineConfig.levelMax])
        let (state, session, ex) = try XCTUnwrap(exercise(.coreAntiExt, in: seed))
        XCTAssertEqual(ex.unit, .hold)
        let onPlan = Engine.applyFeedback(state: state, session: session, result: .plan,
                                          overrides: [.coreAntiExt: ex.load]).levels[.coreAntiExt]
        // Re-marked for v2.21 (spec §32.4): the window is one LOCAL rung of
        // the ladder, not five seconds.
        let window = Level.step(of: ex.unit, tier: ex.tier,
                                sets: Level.decode(0).sets, load: ex.load)
        XCTAssertGreaterThan(window, 1, "tier 1 rung 0 is 2 s wide — the window has room")
        for extra in 1..<window {
            let got = Engine.applyFeedback(state: state, session: session, result: .plan,
                                           overrides: [.coreAntiExt: ex.load + extra])
                .levels[.coreAntiExt]
            XCTAssertEqual(got, onPlan,
                           "plan +\(extra)s must not score worse than exactly the plan")
        }
    }

    func testTheLevelIsMonotoneInTheReportedFact() throws {
        // The property the whole ticket is about, swept across the scale.
        for pattern in [Pattern.coreAntiExt, .coreRot, .squat, .pull] {
            for level in [0, 5, 12, 20, 33, 47] {
                let seed = pattern == .pull
                    ? seeded(0, [.pull: level])
                    : seeded(0, [pattern: level, .pull: EngineConfig.levelMax])
                guard let (state, session, ex) = exercise(pattern, in: seed) else { continue }
                var previous = -1
                // Re-marked for v2.21 (spec §32.4): the old bound was
                // 2 × holdStepSec = 10; the widest ladder rung is 4 s, so 10
                // still clears two rungs anywhere on the scale.
                for actual in 0...(ex.load + 10) {
                    let got = Engine.applyFeedback(state: state, session: session, result: .plan,
                                                   overrides: [pattern: actual]).levels[pattern] ?? 0
                    XCTAssertGreaterThanOrEqual(
                        got, previous,
                        "\(pattern) L\(level): fact \(actual) scored below fact \(actual - 1)")
                    previous = got
                }
            }
        }
    }

    func testARepFactStillNeedsToMatchExactly() throws {
        // For reps the window is one step wide, so nothing changes there.
        let seed = seeded(20, [.pull: EngineConfig.levelMax])
        let (state, session, ex) = try XCTUnwrap(exercise(.squat, in: seed))
        XCTAssertEqual(ex.unit, .reps)
        let onPlan = try XCTUnwrap(Engine.applyFeedback(state: state, session: session,
                                                        result: .plan,
                                                        overrides: [.squat: ex.load]).levels[.squat])
        // Two more reps clear the per-session cap's first step, so the
        // overshoot is visible; one more rep coincides with the "on plan"
        // step by arithmetic, which is why the window is one step wide.
        let above = try XCTUnwrap(Engine.applyFeedback(state: state, session: session,
                                                       result: .plan,
                                                       overrides: [.squat: ex.load + 2]).levels[.squat])
        XCTAssertGreaterThan(above, onPlan, "a real overshoot outscores 'the plan met'")
    }

    // MARK: - §25.2 The set-band gate and a point fact (#140)

    func testAGatedPlanInvertsTheSameWayAnUngatedOneDoes() throws {
        for level in [32, 36, 40, 44, 47] {
            let gated = seeded(0, [.pushH: level, .pull: 0])
            let free = seeded(0, [.pushH: level, .pull: EngineConfig.levelMax])
            let (gated2, gs, gex) = try XCTUnwrap(exercise(.pushH, in: gated))
            let (free2, fs, fex) = try XCTUnwrap(exercise(.pushH, in: free))
            XCTAssertLessThan(gex.sets, fex.sets, "L\(level): the gate really trimmed the sets")
            for actual in [0, 1, 4, 6, 10, 20] {
                let g = Engine.applyFeedback(state: gated2, session: gs, result: .plan,
                                             overrides: [.pushH: actual]).levels[.pushH]
                let f = Engine.applyFeedback(state: free2, session: fs, result: .plan,
                                             overrides: [.pushH: actual]).levels[.pushH]
                XCTAssertEqual(g, f, "L\(level) fact \(actual): the gate changed the verdict")
            }
        }
    }

    func testOvershootingAGatedPlanNeverDropsTheLevelOrFeedsTheDeload() throws {
        let seed = seeded(0, [.pushH: 32, .pull: 0])
        let (gated, session, ex) = try XCTUnwrap(exercise(.pushH, in: seed))
        let after = Engine.applyFeedback(state: gated, session: session, result: .plan,
                                         overrides: [.pushH: ex.load + 6])
        XCTAssertGreaterThan(try XCTUnwrap(after.levels[.pushH]), 32,
                             "an honest overshoot climbs; it used to drop 32 → 30")
        XCTAssertEqual(after.failStreak[.pushH], 0,
                       "and it is not an underperformance")
    }

    // MARK: - §25.3 A descent may not make the plan heavier (#138)

    func testAnHonestZeroOnASetsBandDoesNotAddReps() throws {
        for level in [32, 33, 40, 41] {
            let seed = seeded(0, [.pushH: level, .pull: EngineConfig.levelMax])
            let (state, session, _) = try XCTUnwrap(exercise(.pushH, in: seed))
            let after = try XCTUnwrap(Engine.applyFeedback(state: state, session: session,
                                                           result: .plan,
                                                           overrides: [.pushH: 0]).levels[.pushH])
            XCTAssertLessThan(after, level, "a zero still goes down")
            XCTAssertTrue(Level.noHarder(pattern: .pushH, from: level, to: after),
                          "L\(level) → L\(after) asked for more work")
        }
    }

    func testADescentNeverAsksForMoreWorkAnywhereOnTheScale() throws {
        for pattern in Pattern.allCases {
            for level in 0...EngineConfig.levelMax {
                let seed = pattern == .pull
                    ? seeded(0, [.pull: level])
                    : seeded(0, [pattern: level, .pull: EngineConfig.levelMax])
                guard let (state, session, ex) = exercise(pattern, in: seed) else { continue }
                for actual in [0, 1, 2, max(0, ex.load - 1)] {
                    let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                                     overrides: [pattern: actual])
                        .levels[pattern] ?? 0
                    guard after < level else { continue }
                    XCTAssertTrue(Level.noHarder(pattern: pattern, from: level, to: after),
                                  "\(pattern) L\(level) fact \(actual) → L\(after) is heavier")
                }
            }
        }
    }

    func testARunOfZerosWalksDownToTheFloorInsteadOfStalling() {
        var state = seeded(EngineConfig.levelMax)
        var previous = EngineConfig.levelMax
        var appearances = 0
        for _ in 0..<40 where previous > 0 {
            let session = Engine.generateSession(state)
            if session.exercises.contains(where: { $0.pattern == .pushH }) {
                state = Engine.applyFeedback(state: state, session: session, result: .plan,
                                             overrides: [.pushH: 0])
                let now = state.levels[.pushH] ?? 0
                XCTAssertLessThan(now, previous, "each honest zero moves down")
                previous = now
                appearances += 1
            } else {
                state = Engine.applyFeedback(state: state, session: session, result: .plan)
            }
        }
        XCTAssertEqual(previous, 0)
        XCTAssertLessThanOrEqual(appearances, 8, "the descent converges rather than crawling")
    }

    func testNoHarderAcceptsALandingOnATierFloor() {
        // Below tier 2's floor every rung of tier 1 asks for more reps — the
        // floor is the only place left, and it is a genuinely easier movement.
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: 8, to: 0))
        XCTAssertFalse(Level.noHarder(pattern: .pull, from: 8, to: 7))
        // Re-marked for v2.17 (spec §28.1): band 4 now asks 4×6 rather than
        // 4×4, so the levels that count as "no harder" moved with it. The
        // property is unchanged — these are the boundaries, checked by hand.
        // Re-marked again for v2.19 (spec §30.2): the gate now also reads the
        // dose of a single set, so dropping a set to buy reps no longer
        // passes. 3×8 and 4×6 are the same 24 reps in total, but eight in a
        // set against six is harder in the only place the trainee feels it.
        // The check is not weakened — it moved from accepting that pair to
        // rejecting it, and the nearest accepted landing is asserted below.
        XCTAssertFalse(Level.noHarder(pattern: .pushH, from: 32, to: 28),
                       "3×8 asks eight reps a set against the plan's six")
        XCTAssertTrue(Level.noHarder(pattern: .pushH, from: 32, to: 26),
                      "3×6 keeps the plan's dose per set and drops a set")
        XCTAssertEqual(Level.descendNoHarder(pattern: .pushH, from: 32, factLevel: 28), 26,
                       "the descent steps past the rungs that trade sets for reps")
        XCTAssertFalse(Level.noHarder(pattern: .pushH, from: 32, to: 31),
                       "3×11 = 33 is more work than 4×6 = 24")
        XCTAssertTrue(Level.noHarder(pattern: .pushH, from: 32, to: 0),
                      "the floor of tier 1 is always allowed")
        XCTAssertFalse(Level.noHarder(pattern: .pushH, from: 32, to: 7),
                       "but the top of tier 1 asks 15 reps against 6")
    }

    // MARK: - The valid domain is untouched

    func testAFactEqualToThePlanStillStepsAsOnPlan() throws {
        let state = seeded(10, [.pull: EngineConfig.levelMax])
        let session = Engine.generateSession(state)
        for ex in session.exercises where ex.pattern != .pull {
            let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                             overrides: [ex.pattern: ex.load]).levels[ex.pattern]
            let cap = EngineConfig.maxUp(pattern: ex.pattern, tier: ex.tier)
            XCTAssertEqual(after, min(10 + EngineConfig.deltaPlan, 10 + cap),
                           "\(ex.pattern) moved differently on an exact match")
        }
    }
}
