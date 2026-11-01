import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class PositionTechniqueTests: XCTestCase {

    /// The whole pool of ten: each of session one's positions set aside in
    /// turn, over the rotation — a fallback only appears once its zone's first
    /// choice is gone.
    private var allCooldownPositions: [CooldownPosition] {
        var seen: [CooldownPosition] = []
        let first = Cooldown.positions(sessionNumber: 1).map(\.id)
        let asides: [[String]] = [[]] + first.map { [$0] }
        for hidden in asides {
            for session in 1...Cooldown.rotationPeriod {
                for position in Cooldown.positions(sessionNumber: session, hiding: Set(hidden))
                where !seen.contains(where: { $0.id == position.id }) {
                    seen.append(position)
                }
            }
        }
        return seen
    }

    func testTheWarmupBlockIsSixDistinctMoves() {
        XCTAssertEqual(Warmup.moves(sessionNumber: 1, opening: .squat).count, 6)
        XCTAssertEqual(Set(Warmup.moves(sessionNumber: 1, opening: .squat).map(\.id)).count, 6, "ids must be unique")
        for move in Warmup.moves(sessionNumber: 1, opening: .squat) {
            XCTAssertFalse(move.name.isEmpty, "\(move.id): empty name")
        }
    }

    func testEveryPositionCarriesTwoToThreeSteps() {
        let cooldown = allCooldownPositions
        XCTAssertEqual(cooldown.count, 10, "the compositions must surface the whole pool")
        for position in cooldown {
            XCTAssertTrue((2...3).contains(position.steps.count),
                          "\(position.id): \(position.steps.count) steps")
            XCTAssertFalse(position.steps.contains(where: \.isEmpty),
                           "\(position.id): an empty step")
        }
        for move in Warmup.moves(sessionNumber: 1, opening: .squat) {
            XCTAssertTrue((2...3).contains(move.steps.count),
                          "\(move.id): \(move.steps.count) steps")
            XCTAssertFalse(move.steps.contains(where: \.isEmpty),
                           "\(move.id): an empty step")
        }
    }

    func testSheetModelMirrorsItsSource() {
        let move = Warmup.moves(sessionNumber: 1, opening: .squat)[0]
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

    /// A warm-up move that reverses or not, as asked. Found rather than named
    /// by session number: the rotation is what decides who appears, and a
    /// hard-coded 2 would go stale the first time the pool changes.
    private func warmupMove(reverses: Bool) -> WarmupMove? {
        (1...Warmup.rotationPeriod)
            .flatMap { Warmup.moves(sessionNumber: $0, opening: .squat) }
            .first { $0.reverses == reverses }
    }

    func testCapsulesTellTheBlocksAndTheSidesApart() {
        let warmup = PositionTechnique(warmup: Warmup.moves(sessionNumber: 1, opening: .squat)[0]).capsule
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

    /// A circle has two halves, and the sheet says the length of ONE of them.
    /// "warm-up · 30 s" on a move that turns at fifteen would be the number of
    /// neither half — the sheet is read while the countdown is frozen,
    /// precisely to check what is being asked. And it says a DIRECTION: the
    /// cool-down's per-side capsule over a circle would tell the person to
    /// swap something they are meant to reverse.
    func testACircleNamesTheLengthOfOneDirection() throws {
        let circle = try XCTUnwrap(warmupMove(reverses: true), "the pool must draw a circle")
        let whole = try XCTUnwrap(warmupMove(reverses: false))
        let capsule = PositionTechnique(warmup: circle).capsule
        XCTAssertTrue(capsule.contains("\(Warmup.halfSeconds)"),
                      "the capsule must name one half: \(capsule)")
        XCTAssertFalse(capsule.contains("\(Warmup.moveSeconds)"),
                       "the whole slot is not what is asked for: \(capsule)")
        XCTAssertEqual(capsule, String(localized: "positionSheet.warmupPerDirection",
                                       defaultValue: "warm-up · \(Warmup.halfSeconds) s each way"))
        XCTAssertNotEqual(capsule, PositionTechnique(warmup: whole).capsule,
                          "a circle must not read like a move that runs straight through")
    }
}
