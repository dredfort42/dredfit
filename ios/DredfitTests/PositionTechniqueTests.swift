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

    /// A warm-up move that splits the way `halves` says. Found rather than
    /// named by session number: the rotation is what decides who appears, and
    /// a hard-coded 2 would go stale the first time the pool changes.
    private func warmupMove(halves: WarmupHalves?) -> WarmupMove? {
        (1...Warmup.compositionCount)
            .flatMap(Warmup.moves(sessionNumber:))
            .first { $0.halves == halves }
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

    /// §41.12: a split warm-up move has two halves, and the sheet says the
    /// length of ONE of them. "warm-up · 30 s" on a move that runs 15 + 15
    /// would be the number of neither half — the sheet is read while the
    /// countdown is frozen, precisely to check what is being asked.
    ///
    /// Both kinds, and they must not read alike: a circle is reversed, not
    /// swapped, and the capsule is where the person finds out which.
    func testASplitWarmupMoveNamesTheLengthOfOneHalf() throws {
        let bySide = try XCTUnwrap(warmupMove(halves: .sides), "the pool must draw one")
        let byDirection = try XCTUnwrap(warmupMove(halves: .directions), "...and one of these")
        let whole = try XCTUnwrap(warmupMove(halves: nil))
        let capsules = [bySide, byDirection].map { PositionTechnique(warmup: $0).capsule }
        for capsule in capsules {
            XCTAssertTrue(capsule.contains("\(Warmup.halfSeconds)"),
                          "the capsule must name one half: \(capsule)")
            XCTAssertFalse(capsule.contains("\(Warmup.moveSeconds)"),
                           "the whole slot is not what is asked for: \(capsule)")
        }
        XCTAssertEqual(Set(capsules).count, 2, "sides and directions must not read alike")
        XCTAssertFalse(capsules.contains(PositionTechnique(warmup: whole).capsule),
                       "a split move must not read like a move that runs straight through")
    }
}
