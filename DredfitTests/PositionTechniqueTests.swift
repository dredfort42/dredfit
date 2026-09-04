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
        XCTAssertEqual(Warmup.moves(sessionNumber: 1).count, 6)
        XCTAssertEqual(Set(Warmup.moves(sessionNumber: 1).map(\.id)).count, 6, "ids must be unique")
        for move in Warmup.moves(sessionNumber: 1) {
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
        for move in Warmup.moves(sessionNumber: 1) {
            XCTAssertTrue((2...3).contains(move.steps.count),
                          "\(move.id): \(move.steps.count) steps")
            XCTAssertFalse(move.steps.contains(where: \.isEmpty),
                           "\(move.id): an empty step")
        }
    }

    func testSheetModelMirrorsItsSource() {
        let move = Warmup.moves(sessionNumber: 1)[0]
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

    /// A move from the composition that draws both unilateral moves. Found
    /// rather than named by session number: the rotation is what decides who
    /// appears, and a hard-coded 4 would go stale the first time the pool
    /// changes.
    private var unilateralWarmupMove: WarmupMove? {
        (1...Warmup.compositionCount)
            .flatMap(Warmup.moves(sessionNumber:))
            .first(where: \.perSide)
    }

    func testCapsulesTellTheBlocksAndTheSidesApart() {
        let warmup = PositionTechnique(warmup: Warmup.moves(sessionNumber: 1)[0]).capsule
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

    /// §41.12: the warm-up has two sides now, and the sheet says the length of
    /// ONE of them. "warm-up · 30 s" on a move that runs 15 + 15 would be the
    /// number of neither half — the sheet is read while the countdown is
    /// frozen, precisely to check what is being asked.
    func testAUnilateralWarmupMoveNamesTheLengthOfOneSide() throws {
        let move = try XCTUnwrap(unilateralWarmupMove, "the pool must draw a unilateral move")
        let capsule = PositionTechnique(warmup: move).capsule
        XCTAssertTrue(capsule.contains("\(Warmup.sideSeconds)"),
                      "the capsule must name one side: \(capsule)")
        XCTAssertFalse(capsule.contains("\(Warmup.moveSeconds)"),
                       "the whole slot is not what the person is asked for: \(capsule)")
        let bilateral = try XCTUnwrap(Warmup.moves(sessionNumber: 1).first { !$0.perSide })
        XCTAssertNotEqual(capsule, PositionTechnique(warmup: bilateral).capsule,
                          "a unilateral move must not read like a bilateral one")
    }
}
