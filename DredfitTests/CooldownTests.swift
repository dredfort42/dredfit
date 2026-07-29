//
//  CooldownTests.swift
//  DredfitTests
//
//  The cool-down composition (issue #28) is a pure function of the performed
//  patterns: deterministic, deduplicated, always six positions with the rest
//  pose last — or empty when nothing was performed.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class CooldownTests: XCTestCase {

    func testSixPositionsForAFullSession() {
        let session = Engine.generateSession(.initial)
        let positions = Cooldown.positions(performed: session.exercises.map(\.pattern))
        XCTAssertEqual(positions.count, Cooldown.positionCount)
        XCTAssertEqual(Set(positions.map(\.id)).count, positions.count, "no duplicates")
        XCTAssertEqual(positions.last?.id, "rest-pose", "the rest pose closes the block")
        XCTAssertEqual(positions[0].id, "hip-flexors")
        XCTAssertEqual(positions[1].id, "chest-wall")
    }

    func testCompositionIsDeterministic() {
        let performed = Engine.generateSession(.initial).exercises.map(\.pattern)
        let first = Cooldown.positions(performed: performed)
        for _ in 0..<5 {
            XCTAssertEqual(Cooldown.positions(performed: performed), first)
        }
    }

    func testMappingFollowsThePerformedMovements() {
        // pull → lats, squat → forward fold, calf → calf at the wall; in the
        // order the session ran them.
        let positions = Cooldown.positions(performed: [.pull, .squat, .calf])
        XCTAssertEqual(positions.map(\.id),
                       ["hip-flexors", "chest-wall",
                        "lat-stretch", "forward-fold", "calf-wall", "rest-pose"])
    }

    func testSharedPositionsDeduplicateAndTopUpFromThePool() {
        // squat and hinge share the forward fold; push_h and push_v share
        // wrists — three exercises' worth of movements can map to fewer than
        // three positions, and the pool tops the block back up to six.
        let positions = Cooldown.positions(
            performed: [.squat, .hinge, .pushH, .pushV, .pull, .lunge])
        XCTAssertEqual(positions.count, Cooldown.positionCount)
        XCTAssertEqual(Set(positions.map(\.id)).count, positions.count)
        // The mapped three come from the session in order: fold, wrists, lats.
        XCTAssertEqual(positions[2].id, "forward-fold")
        XCTAssertEqual(positions[3].id, "wrists")
        XCTAssertEqual(positions[4].id, "lat-stretch")
    }

    func testShortWorkoutStillGetsSixPositions() {
        // Three performed movements that all map to distinct positions.
        let positions = Cooldown.positions(performed: [.pull, .squat, .coreRot])
        XCTAssertEqual(positions.count, Cooldown.positionCount)
        // And three that collapse to two mapped positions — topped up.
        let collapsed = Cooldown.positions(performed: [.squat, .hinge, .pull])
        XCTAssertEqual(collapsed.count, Cooldown.positionCount)
        XCTAssertEqual(Set(collapsed.map(\.id)).count, collapsed.count)
    }

    func testNothingPerformedMeansNoCooldown() {
        XCTAssertTrue(Cooldown.positions(performed: []).isEmpty,
                      "a workout of pure skips has nothing to stretch")
    }

    func testTheBlockFillsExactlyTheEnginesReservedMinutes() {
        // 6 × 30 s = the 3 minutes `cooldownMin` has promised since 1.0:
        // sides and positions sum to the reserved minutes. The side-switch
        // pauses (issue #35) ride on top, within the "≈" every estimate has
        // always carried — they are deliberately not part of this equation.
        XCTAssertEqual(Cooldown.positionCount * Cooldown.positionSeconds,
                       EngineConfig.cooldownMin * 60)
    }

    func testAPerSidePositionSplitsIntoTwoWholeSidesPlusThePause() {
        // 15 + 5 + 15 (issue #35): the slot splits into two equal whole
        // sides, and the pause is the app-layer constant the acceptance
        // pinned — shared with the workout's per-side holds.
        XCTAssertEqual(Cooldown.sideSeconds * 2, Cooldown.positionSeconds,
                       "the sides must consume the whole slot")
        XCTAssertEqual(Cooldown.sideSeconds, 15)
        XCTAssertEqual(Cooldown.sideSwitchPauseSec, 5)
    }

    // MARK: - The stage machine (issue #35)

    /// pull → [hip flexors (per side), chest wall, lats, fold, calf... ] —
    /// enough to walk both a per-side and a bilateral position.
    private var machinePositions: [CooldownPosition] {
        Cooldown.positions(performed: [.pull])
    }

    func testAPerSidePositionWalksSidesAroundThePause() {
        let positions = machinePositions
        XCTAssertTrue(positions[0].perSide, "hip flexors open the block per side")
        XCTAssertEqual(Cooldown.openingStage(of: positions[0]), .firstSide)
        let pause = Cooldown.step(after: (0, .firstSide), positions: positions)
        XCTAssertEqual(pause?.stage, .switchPause)
        let second = Cooldown.step(after: (0, .switchPause), positions: positions)
        XCTAssertEqual(second?.stage, .secondSide)
        // ...and the second side leaves the position entirely.
        let next = Cooldown.step(after: (0, .secondSide), positions: positions)
        XCTAssertEqual(next?.index, 1)
        XCTAssertEqual(next?.stage, .single, "chest wall is bilateral")
    }

    func testTheBlockEndsAfterTheLastPosition() {
        let positions = machinePositions
        XCTAssertNil(Cooldown.step(after: (positions.count - 1, .single),
                                   positions: positions))
    }

    func testAdvanceNamesThePauseItEnters() {
        // The boundary crossed right now decides the signal: the first
        // side's end enters the pause (the falling switch tone), the
        // pause's end enters the second side (the usual go).
        let positions = machinePositions
        let intoPause = Cooldown.advance(from: (0, .firstSide), overshoot: 0,
                                         positions: positions)
        XCTAssertEqual(intoPause?.entered, .switchPause)
        XCTAssertEqual(intoPause?.remaining, Cooldown.sideSwitchPauseSec)
        let intoSecond = Cooldown.advance(from: (0, .switchPause), overshoot: 0,
                                          positions: positions)
        XCTAssertEqual(intoSecond?.entered, .secondSide)
        XCTAssertEqual(intoSecond?.remaining, Cooldown.sideSeconds)
    }

    func testAdvanceAbsorbsBackgroundedTimeAcrossStages() {
        // 22 s past the first side's end: the pause (5) and the second side
        // (15) are consumed whole, landing 2 s into the next position's 30.
        let positions = machinePositions
        let landing = Cooldown.advance(from: (0, .firstSide), overshoot: 22,
                                       positions: positions)
        XCTAssertEqual(landing?.index, 1)
        XCTAssertEqual(landing?.stage, .single)
        XCTAssertEqual(landing?.remaining, Cooldown.positionSeconds - 2)
        // An overshoot past the whole block is simply over.
        XCTAssertNil(Cooldown.advance(from: (0, .firstSide), overshoot: 10_000,
                                      positions: positions))
    }

    func testPerSideHintsAreOnUnilateralPositionsOnly() {
        let all = Cooldown.positions(
            performed: [.squat, .pull, .pushH, .coreRot, .calf, .lunge])
            + Cooldown.positions(performed: [.calf, .lunge, .coreAntiExt])
        for position in all {
            let expected = ["hip-flexors", "calf-wall", "seated-glute",
                            "lying-twist"].contains(position.id)
            XCTAssertEqual(position.perSide, expected,
                           "\(position.id): unexpected per-side flag")
        }
    }
}
