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
        // 6 × 30 s = the 3 minutes `cooldownMin` has promised since 1.0.
        XCTAssertEqual(Cooldown.positionCount * Cooldown.positionSeconds,
                       EngineConfig.cooldownMin * 60)
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
