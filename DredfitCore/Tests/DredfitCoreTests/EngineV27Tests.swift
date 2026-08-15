//
//  EngineV27Tests.swift
//  DredfitCoreTests
//
//  The do-no-harm gate wave (spec §17): calibration bounded by the
//  neighboring tier, landing ceilings and the set-band snap on the comeback,
//  and the silent decay resetting the fail streak. Mirrors the corresponding
//  blocks in the reference verifier — anything asserted here is asserted
//  there too.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV27Tests: XCTestCase {

    private func seeded(level: Int, counter: Int = 0,
                        streak: Int = 0) -> EngineState {
        var state = EngineState.initial
        state.counter = counter
        for p in Pattern.allCases {
            state.levels[p] = level
            state.failStreak[p] = streak
        }
        return state
    }

    private func after(_ state: EngineState, _ result: FeedbackResult,
                       overrides: [Pattern: Int] = [:]) -> EngineState {
        Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                             result: result, overrides: overrides)
    }

    // MARK: - Calibration bounded by the neighboring tier (§17.1)

    /// The audit's teleport repro: an honest everyday fact from zero used to
    /// land in tiers 3–4 on day one. Now the inversion stops at the
    /// neighboring tier's ceiling.
    func testCalibrationStopsAtTheNeighboringTier() {
        let state = EngineState.initial
        let thirty = after(state, .plan, overrides: [.squat: 30])
        XCTAssertEqual(thirty.levels[.squat], 15,
                       "{squat: 30} lands at the tier-2 ceiling, not tier 3")
        let sixty = after(state, .plan, overrides: [.pushH: 60])
        XCTAssertEqual(sixty.levels[.pushH], 15,
                       "{push_h: 60} lands at 15, not the scale ceiling")
    }

    /// Inside the bound calibration stays exact — the everyday case is
    /// untouched.
    func testCalibrationInsideTheBoundIsExact() {
        let state = EngineState.initial
        let honest = after(state, .plan, overrides: [.squat: 14])
        XCTAssertEqual(honest.levels[.squat], 6,
                       "a fact of 14 still calibrates precisely to 6")
    }

    /// A slow-tissue pattern (held to a step at every tier by §15.3 — the
    /// calf) calibrates no higher than the tier-1 ceiling: the Achilles
    /// remodels on a slower clock than the fact suggests.
    func testSlowTissueCalibratesNoHigherThanTierOne() {
        XCTAssertTrue(EngineConfig.isSlowTissue(.calf))
        XCTAssertFalse(EngineConfig.isSlowTissue(.squat))
        var state = EngineState.initial
        state.counter = 1   // this rotation slot brings the calf into the session
        let session = Engine.generateSession(state)
        XCTAssertTrue(session.exercises.contains { $0.pattern == .calf })
        let calibrated = Engine.applyFeedback(state: state, session: session,
                                              result: .plan, overrides: [.calf: 40])
        XCTAssertEqual(calibrated.levels[.calf], 7,
                       "{calf: 40} lands at the tier-1 ceiling, not level 32")
    }

    // MARK: - Comeback landing ceilings and the set-band snap (§17.2)

    /// Half a year lands no higher than tier 2, a year no higher than tier 1
    /// — the calendar cap of −8 alone left a former ceiling user in tier 4.
    func testLandingCeilingsPastTheTableEdge() {
        let top = seeded(level: 47)
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 179).levels[.squat], 32,
                       "179 days: the ceiling does not act yet")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 180).levels[.squat], 15,
                       "180 days: tier-2 landing")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 365).levels[.squat], 7,
                       "365 days: tier-1 landing")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 3650).levels[.squat], 7,
                       "ten years: same tier-1 landing")
        // Below the ceiling the drop result stands.
        let low = seeded(level: 10)
        XCTAssertEqual(Engine.applyComeback(state: low, gapDays: 365).levels[.squat], 2,
                       "a low level keeps the plain table drop")
    }

    /// Crossing a set band snaps the rung to the band floor; inside a band
    /// the rung is preserved as documented since v2.3.
    func testSetBandCrossingSnapsTheRung() {
        let top = seeded(level: 47)
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 90).levels[.squat], 42,
                       "90 days: same band, rung preserved")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 140).levels[.squat], 32,
                       "140 days: band crossed, rung snapped to the floor")
        let edge = seeded(level: 33)
        XCTAssertEqual(Engine.applyComeback(state: edge, gapDays: 14).levels[.squat], 24,
                       "a −2 across the 32 boundary snaps too")
        // The audit's dose inversion is gone: 140 days now costs less volume
        // than 90 days.
        let d90 = Level.decode(42), d140 = Level.decode(32)
        XCTAssertGreaterThan(d90.sets * d90.reps, d140.sets * d140.reps)
    }

    /// Tier crossings below the set bands keep the rung — the snap must not
    /// leak into the documented v2.3 behavior.
    func testTierCrossingBelowTheBandsKeepsTheRung() {
        let mid = seeded(level: 20)
        XCTAssertEqual(Engine.applyComeback(state: mid, gapDays: 140).levels[.squat], 12,
                       "−8 below the bands is still exactly one tier down, same rung")
    }

    /// The no-stacking identity of §14.2 survives the ceilings and the snap:
    /// peeking mid-break costs exactly nothing, at every level and at the new
    /// boundaries too.
    func testDecayPlusWeakenedComebackStillEqualsThePlainComeback() {
        for gap in [140, 179, 180, 200, 365, 3650] {
            for level in 0...EngineConfig.levelMax {
                let plain = Engine.applyComeback(state: seeded(level: level, streak: 2),
                                                 gapDays: gap)
                let peeked = Engine.applyComeback(
                    state: Engine.applySilentDecay(state: seeded(level: level, streak: 2),
                                                   gapDays: 10),
                    gapDays: gap, alreadyDecayed: true)
                XCTAssertEqual(peeked.levels, plain.levels,
                               "L=\(level), gap \(gap): the two paths must land identically")
            }
        }
    }

    /// The landing level never rises as the break grows — the property whose
    /// absence was the audit's non-monotonic dose.
    func testLandingIsMonotonicInTheGap() {
        let gaps = [14, 35, 56, 77, 98, 119, 140, 179, 180, 200, 364, 365, 3650]
        for level in 0...EngineConfig.levelMax {
            var previous = Int.max
            for gap in gaps {
                let landed = Engine.applyComeback(state: seeded(level: level),
                                                  gapDays: gap).levels[.squat] ?? -1
                XCTAssertLessThanOrEqual(landed, previous,
                                         "L=\(level): landing rose between gaps at \(gap)")
                previous = landed
            }
        }
    }

    // MARK: - Silent decay resets the streak (§17.3)

    func testSilentDecayResetsTheFailStreak() {
        let decayed = Engine.applySilentDecay(state: seeded(level: 20, streak: 2),
                                              gapDays: 10)
        for p in Pattern.allCases {
            XCTAssertEqual(decayed.levels[p], 19, "\(p.rawValue): the −1 still applies")
            XCTAssertEqual(decayed.failStreak[p], 0,
                           "\(p.rawValue): the streak resets like the comeback's")
        }
    }

    /// The 13/14-day inversion is closed: a streak of 2, a 13-day pause and
    /// an honest "less" no longer ride into a deload — both sides of the
    /// boundary land on the same level.
    func testThirteenDaysNoLongerCostMoreThanFourteen() {
        var paused = Engine.applySilentDecay(state: seeded(level: 12, streak: 2),
                                             gapDays: 13)
        let session = Engine.generateSession(paused)
        // v2.9: the subject is the 13/14-day boundary, so the delta is taken
        // session-wide (spec §19.2).
        paused = Engine.applyFeedback(state: paused.underLessRun, session: session, result: .less)
        for ex in session.exercises {
            XCTAssertEqual(paused.levels[ex.pattern], 10,
                           "\(ex.pattern.rawValue): −1 decay and −1 rating, no −3")
            XCTAssertEqual(paused.failStreak[ex.pattern], 1,
                           "\(ex.pattern.rawValue): the streak counts anew")
        }
        let fourteen = Engine.applyComeback(state: seeded(level: 12, streak: 2),
                                            gapDays: 14)
        XCTAssertEqual(fourteen.levels[.squat], 10,
                       "the 14-day comeback lands on the same level")
    }
}
