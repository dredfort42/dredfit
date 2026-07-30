//
//  PositionTechniqueTests.swift
//  DredfitTests
//
//  The warm-up and cool-down mini-sheets (issue #34) are data-driven:
//  every one of the 15 positions carries 2–3 non-empty steps, and the
//  sheet model builds a capsule that tells the block and the sides apart.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class PositionTechniqueTests: XCTestCase {

    /// Two compositions that together surface all nine pool positions.
    private var allCooldownPositions: [CooldownPosition] {
        let all = Cooldown.positions(performed: [.squat, .pull, .pushH, .coreRot, .calf, .lunge])
            + Cooldown.positions(performed: [.calf, .lunge, .coreAntiExt])
        var seen: [CooldownPosition] = []
        for position in all where !seen.contains(position) { seen.append(position) }
        return seen
    }

    func testTheWarmupBlockIsSixDistinctMoves() {
        XCTAssertEqual(Warmup.moves.count, 6)
        XCTAssertEqual(Set(Warmup.moves.map(\.id)).count, 6, "ids must be unique")
        for move in Warmup.moves {
            XCTAssertFalse(move.name.isEmpty, "\(move.id): empty name")
        }
    }

    func testEveryPositionCarriesTwoToThreeSteps() {
        let cooldown = allCooldownPositions
        XCTAssertEqual(cooldown.count, 9, "the two compositions must surface the whole pool")
        for position in cooldown {
            XCTAssertTrue((2...3).contains(position.steps.count),
                          "\(position.id): \(position.steps.count) steps")
            XCTAssertFalse(position.steps.contains(where: \.isEmpty),
                           "\(position.id): an empty step")
        }
        for move in Warmup.moves {
            XCTAssertTrue((2...3).contains(move.steps.count),
                          "\(move.id): \(move.steps.count) steps")
            XCTAssertFalse(move.steps.contains(where: \.isEmpty),
                           "\(move.id): an empty step")
        }
    }

    func testSheetModelMirrorsItsSource() {
        let move = Warmup.moves[0]
        let fromWarmup = PositionTechnique(warmup: move)
        XCTAssertEqual(fromWarmup.id, move.id)
        XCTAssertEqual(fromWarmup.name, move.name)
        XCTAssertEqual(fromWarmup.steps, move.steps)

        let position = allCooldownPositions[0]
        let fromCooldown = PositionTechnique(cooldown: position)
        XCTAssertEqual(fromCooldown.id, position.id)
        XCTAssertEqual(fromCooldown.name, position.name)
        XCTAssertEqual(fromCooldown.steps, position.steps)
    }

    func testCapsulesTellTheBlocksAndTheSidesApart() {
        let warmup = PositionTechnique(warmup: Warmup.moves[0]).capsule
        let positions = allCooldownPositions
        let perSide = PositionTechnique(
            cooldown: positions.first(where: \.perSide)!).capsule
        let bilateral = PositionTechnique(
            cooldown: positions.first(where: { !$0.perSide })!).capsule
        XCTAssertFalse(warmup.isEmpty)
        XCTAssertNotEqual(warmup, bilateral, "warm-up and cool-down must be told apart")
        XCTAssertNotEqual(perSide, bilateral, "a per-side slot reads differently")
        // The capsules carry the real block constants, not copies of them.
        XCTAssertTrue(warmup.contains("\(Warmup.moveSeconds)"))
        XCTAssertTrue(perSide.contains("\(Cooldown.sideSeconds)"))
        XCTAssertTrue(bilateral.contains("\(Cooldown.positionSeconds)"))
    }
}
