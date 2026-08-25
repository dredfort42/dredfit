//
// The do-no-harm gate wave: calibration bounded by the neighboring tier,
// landing ceilings and the set-band snap on the comeback, and the silent decay
// resetting the fail streak. Mirrors the corresponding blocks in the reference
// verifier — anything asserted here is asserted there too.
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

    // MARK: - Calibration bounded by the neighboring tier

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

    /// A slow-tissue pattern (held to a step at every tier by — the calf)
    /// calibrates no higher than the tier-1 ceiling: the Achilles remodels on
    /// a slower clock than the fact suggests.
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

    // MARK: - Comeback landing ceilings and the set-band snap

    /// The ladder of tier-bottom ceilings — every next storey of the break
    /// lands a floor lower, and the 179 → 180 cliff of the old 15/7 rows is
    /// gone.
    func testLandingCeilingsPastTheTableEdge() {
        let top = seeded(level: 47)
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 56).levels[.squat], 24,
                       "56 days: bottom of tier 4")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 90).levels[.squat], 16,
                       "90 days: bottom of tier 3")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 179).levels[.squat], 8,
                       "179 days: bottom of tier 2")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 180).levels[.squat], 8,
                       "180 days: the same floor — no cliff")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 365).levels[.squat], 0,
                       "365 days: a clean slate")
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 3650).levels[.squat], 0,
                       "ten years: same clean slate")
        // Below the ceiling the drop result stands.
        let low = seeded(level: 10)
        XCTAssertEqual(Engine.applyComeback(state: low, gapDays: 14).levels[.squat], 8,
                       "a low level keeps the plain table drop")
    }

    /// Crossing a set band snaps the rung to the band floor — the rule keeps
    /// its priority over the tier continuity.
    func testSetBandCrossingSnapsTheRung() {
        let top = seeded(level: 47)
        XCTAssertEqual(Engine.applyComeback(state: top, gapDays: 14).levels[.squat], 45,
                       "same band, rung preserved")
        let edge = seeded(level: 33)
        XCTAssertEqual(Engine.applyComeback(state: edge, gapDays: 14).levels[.squat], 24,
                       "a −2 across the 32 boundary snaps to the band floor")
    }

    /// A tier crossing below the bands lands by rep continuity — the same dose
    /// in the easier variation, never the lower tier's top.
    func testTierCrossingBelowTheBandsKeepsTheRung() {
        let mid = seeded(level: 20)
        let landed = Engine.applyComeback(state: mid, gapDays: 77).levels[.squat] ?? -1
        XCTAssertEqual(landed, 11, "L20 crosses into tier 2 carrying its 9 reps")
        XCTAssertEqual(Level.decode(landed).reps, Level.decode(20).reps)
    }

    /// The no-stacking identity of survives the ceilings and the snap: peeking
    /// mid-break costs exactly nothing, at every level and at the new
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

    // MARK: - Silent decay resets the streak

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
        // The subject is the 13/14-day boundary, so the delta is taken
        // session-wide.
        paused = Engine.applyFeedback(state: paused.underLessRun, session: session, result: .less)
        // Re-marked: a decay is a DESCENT and walks one step of the growth
        // path, not a whole level; the rating is a step too. Two steps down
        // from 12.0 are composed out of the rule itself rather than written as
        // the level 10, and the subject of the block — no premature deload —
        // is asserted exactly as before.
        let first = Level.fallBy(level: 12, sub: 0, cut: 0, by: 1)
        let want = Level.fallBy(level: first.level, sub: first.sub, cut: first.cut,
                                by: 1)
        for ex in session.exercises {
            assertPosition(paused, ex.pattern, want,
                           "\(ex.pattern.rawValue): one step of decay and one of the rating, no −3")
            XCTAssertEqual(paused.failStreak[ex.pattern], 1,
                           "\(ex.pattern.rawValue): the streak counts anew")
        }
        // The subject of itself: thirteen days may never cost MORE than
        // fourteen. The two sides stopped being commensurable in levels — one
        // walks the growth path, the other the comeback table — so they are
        // compared on the shared measure, which is what "cost" means.
        let fourteen = Engine.applyComeback(state: seeded(level: 12, streak: 2),
                                            gapDays: 14)
        XCTAssertEqual(fourteen.levels[.squat], 12 - EngineConfig.comebackBase,
                       "the 14-day comeback is the table's own drop")
        XCTAssertGreaterThanOrEqual(Level.posOrd(paused.position(.squat)),
                                    Level.posOrd(fourteen.position(.squat)),
                                    "thirteen days may never cost more than fourteen")
    }
}
