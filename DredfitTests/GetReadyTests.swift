import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class GetReadyTests: XCTestCase {

    /// The block composes six moves out of nine now (§40.1), so a stage
    /// machine cannot be asked about "the moves" — it has to be asked about a
    /// COMPOSITION. Session one's, throughout; the reserve tests in
    /// BlockReserveTests walk all of them.
    private let warmupMoves = Warmup.moves(sessionNumber: 1)

    /// The index of the one move that pays the transition supplement — the
    /// trip down to the floor.
    private var floorIndex: Int { warmupMoves.firstIndex { $0.needsSetup } ?? 0 }

    /// The dearest composition: the one the rotation fills with the most split
    /// moves (§41.12) — three of the four the pool has. Found, not named by
    /// session number: the rotation decides who appears, and a hard-coded 2
    /// goes stale the first time the pool changes.
    private var dearestComposition: [WarmupMove] {
        (1...Warmup.compositionCount)
            .map(Warmup.moves(sessionNumber:))
            .max { $0.filter(\.isSplit).count < $1.filter(\.isSplit).count } ?? []
    }

    /// What one warm-up move costs uninterrupted: the transition, then the
    /// slot — two halves and the switch pause when the move has a boundary.
    /// Hand-rolled on purpose, like the cool-down twin above: this file's job
    /// is to state the arithmetic independently of the production formula.
    private func cost(of move: WarmupMove) -> Int {
        let slot = move.isSplit
            ? Warmup.halfSeconds * 2 + Cooldown.sideSwitchPauseSec
            : Warmup.moveSeconds
        return GetReady.seconds
            + (move.needsSetup ? GetReady.setupSupplementSec : 0)
            + slot
    }

    // MARK: - The transition itself

    /// RE-MARKED, and the claim is now the OPPOSITE one.
    ///
    /// The two lengths used to be identical, and the test said so: #35 counts
    /// the switch inside a position, #52 the switch between positions, and one
    /// base served both. The transition doubled to ten seconds and the pause
    /// did NOT follow it, because they are not the same thing — travelling to
    /// another position takes time, turning over inside one does not. So what
    /// is pinned now is the split, in both directions, and its arithmetic
    /// counts the pause as five.
    func testTheTransitionAndTheSideSwitchPauseAreNoLongerTheSame() {
        XCTAssertEqual(GetReady.seconds, 10)
        XCTAssertEqual(Cooldown.sideSwitchPauseSec, 5)
        XCTAssertNotEqual(GetReady.seconds, Cooldown.sideSwitchPauseSec,
                          "the two lengths parted in v2.26 and must stay apart")
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: false), GetReady.seconds)
        XCTAssertEqual(Warmup.stageSeconds(.getReady, of: Warmup.moves(sessionNumber: 1)[0]),
                       GetReady.seconds,
                       "marching starts where the user already stands")
    }

    func testAPositionThatHasToBeGotIntoGetsTheSupplement() {
        // The differentiated pause of issue #83: base plus supplement for a
        // position that changes the starting position or needs a prop.
        XCTAssertEqual(GetReady.setupSupplementSec, 5)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: true),
                       GetReady.seconds + GetReady.setupSupplementSec)
        let positions = Cooldown.positions(performed: [.pull])
        XCTAssertEqual(positions[0].id, "hip-flexors")
        XCTAssertEqual(Cooldown.stageSeconds(.getReady, of: positions[0]),
                       GetReady.seconds + GetReady.setupSupplementSec,
                       "the block opens by getting down onto one knee")
    }

    func testOnlyTheStandingPositionsKeepTheBaseTransition() {
        // The flag travels with the data, so this is the list issue #83
        // pinned: in the warm-up only cat-cow leaves standing; in the
        // cool-down only forward fold, the lat stretch and the wrists stay
        // upright with no wall to walk to.
        // The warm-up composes six of nine now (§40.1), and three of the nine
        // are on the floor — so "who pays the supplement" is a property of the
        // COMPOSITION, not of a move. Exactly one per session, always the trip
        // down to the floor, in every composition there is.
        for session in 1...Warmup.compositionCount {
            let moves = Warmup.moves(sessionNumber: session)
            XCTAssertEqual(moves.filter(\.needsSetup).map(\.id), ["cat-cow"],
                           "session \(session)")
        }
        let allNine = Cooldown.positions(performed: [.squat, .pull, .pushH])
            + Cooldown.positions(performed: [.coreAntiExt, .calf, .lunge])
        let standing = Set(allNine.filter { !$0.needsSetup }.map(\.id))
        XCTAssertEqual(standing, ["forward-fold", "lat-stretch", "wrists"])
    }

    func testTheTransitionLeavesRoomForTheCountdownItPlays() {
        // The 3-2-1 has to fit inside it with a beat to spare for reading the
        // name of what is coming — a transition shorter than the ticks would
        // start mid-signal.
        XCTAssertGreaterThan(GetReady.seconds, 3)
    }

    // MARK: - Honest numbers

    /// What one position costs uninterrupted, supplement and sides included.
    ///
    /// Routes through `GetReady.stageSeconds(needsSetup:)` rather than
    /// re-deriving `seconds + setupSupplementSec` by hand — the hand-rolled
    /// version here and `BlockReserveTests.cost(_:CooldownPosition)` used to
    /// state the same formula two different ways, which stays correct only
    /// as long as nobody changes the production one without noticing the
    /// copy. Calling the real function makes that impossible instead of
    /// merely unlikely.
    private func cost(of position: CooldownPosition) -> Int {
        let hold = position.perSide
            ? Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec
            : Cooldown.positionSeconds
        return GetReady.stageSeconds(needsSetup: position.needsSetup) + hold
    }

    /// The decision this feature rests on: the transitions — supplements
    /// included since #83 — ride on top of the minutes the engine reserves for
    /// the two blocks. The worst case is exact: the dearest warm-up plus the
    /// fixed three positions plus the costliest three the mapping can draw.
    ///
    /// What is no longer exact is the FIT. §41.12 gave the warm-up the counted
    /// switch, the pair went from 540 s to 555, and a reserve is whole minutes
    /// — so 10:00 carries 45 s of slack. Under a minute, which is the property
    /// that replaced the equality: one minute of slack and the engine would be
    /// holding a minute the blocks do not use.
    func testBothBlocksFitInsideTheReservedWarmupAndCooldownMinutes() {
        let warmup = dearestComposition.map(cost(of:)).reduce(0, +)

        // One pattern per pool position; index 2 of a one-pattern composition
        // is the position that pattern maps to.
        let pool = [Pattern.squat, .pull, .pushH, .coreAntiExt, .calf, .lunge]
            .map { Cooldown.positions(performed: [$0])[2] }
        let worstMapped = pool.map(cost(of:)).sorted(by: >).prefix(3).reduce(0, +)
        let anyComposition = Cooldown.positions(performed: [.squat])
        let fixed = cost(of: anyComposition[0]) + cost(of: anyComposition[1])
            + cost(of: anyComposition[5])
        let reserved = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60

        // 215 → 245 → 260, because the base transition doubled (§37.7а) and
        // then the dearest composition took three switch pauses (§41.12); 265
        // → 295 on the cool-down side. The transition made the reserve grow,
        // which is what made it an engine change and not an app one.
        XCTAssertEqual(warmup, 260)
        XCTAssertEqual(fixed + worstMapped, 295)
        XCTAssertLessThanOrEqual(warmup + fixed + worstMapped, reserved,
                                 "the worst case overruns the reserved minutes")
        XCTAssertLessThan(reserved - (warmup + fixed + worstMapped), 60,
                          "a whole minute of slack: the reserve could be given back")
    }

    func testARealCompositionLeavesRoom() {
        let performed = Engine.generateSession(.initial).exercises.map(\.pattern)
        let cooldown = Cooldown.positions(performed: performed)
            .reduce(0) { $0 + cost(of: $1) }
        let warmup = warmupMoves.map(cost(of:)).reduce(0, +)
        XCTAssertLessThan(warmup + cooldown,
                          (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60)
    }

    // MARK: - The warm-up stage machine

    func testEveryWarmupMoveOpensWithTheTransition() {
        // The first one included: the user has just pressed Start and is
        // still standing by the phone.
        XCTAssertEqual(Warmup.step(after: (0, .getReady), moves: warmupMoves)?.stage, .move)
        let next = Warmup.step(after: (0, .move), moves: warmupMoves)
        XCTAssertEqual(next?.index, 1)
        XCTAssertEqual(next?.stage, .getReady)
    }

    func testTheWarmupEndsAfterTheLastMove() {
        XCTAssertNil(Warmup.step(after: (warmupMoves.count - 1, .move), moves: warmupMoves),
                     "the last move hands the flow to the first exercise")
        XCTAssertNotNil(Warmup.step(after: (warmupMoves.count - 1, .getReady),
                                    moves: warmupMoves),
                        "...but its own transition still has a move to announce")
    }

    func testWarmupAdvanceNamesTheStageItEnters() {
        let intoMove = Warmup.advance(from: (0, .getReady), overshoot: 0, moves: warmupMoves)
        XCTAssertEqual(intoMove?.entered, .move)
        XCTAssertEqual(intoMove?.remaining, Warmup.moveSeconds)
        let intoTransition = Warmup.advance(from: (0, .move), overshoot: 0,
                                            moves: warmupMoves)
        XCTAssertEqual(intoTransition?.entered, .getReady)
        XCTAssertEqual(intoTransition?.index, 1)
        XCTAssertEqual(intoTransition?.remaining, GetReady.seconds)
    }

    func testWarmupAdvanceAbsorbsBackgroundedTime() throws {
        // Past a move's end by the whole next transition plus two seconds: the
        // transition is consumed whole and the landing is 2 s into the move it
        // announced. This is written from the constant rather than from "7",
        // which was the base of five plus two and silently became wrong when
        // the base doubled.
        //
        // WHICH stage that move opens on is asked of the machine, not assumed:
        // this line meant "the whole slot" until arm circles became a split
        // move (§41.12) and the second move of the block stopped having one.
        let opening = try XCTUnwrap(Warmup.step(after: (1, .getReady),
                                                moves: warmupMoves)?.stage)
        let landing = Warmup.advance(from: (0, .move), overshoot: GetReady.seconds + 2,
                                     moves: warmupMoves)
        XCTAssertEqual(landing?.index, 1)
        XCTAssertEqual(landing?.stage, opening)
        XCTAssertEqual(landing?.remaining,
                       Warmup.stageSeconds(opening, of: warmupMoves[1]) - 2)
        // An absence past the whole block simply ends it.
        XCTAssertNil(Warmup.advance(from: (0, .move), overshoot: 10_000, moves: warmupMoves))
    }

    func testWarmupOvershootLandsOnAWholeMoveBoundary() {
        // A full move-plus-transition of absence advances by exactly one move
        // and lands at the top of the next transition, not mid-anything. The
        // cycle is the move's OWN: 35 s where the slot has a switch pause in
        // it (§41.12), 30 where it runs straight through.
        let cycle = Warmup.stageSeconds(.getReady, of: warmupMoves[1])
            + Warmup.slotSeconds(of: warmupMoves[1])
        let landing = Warmup.advance(from: (0, .move), overshoot: cycle, moves: warmupMoves)
        XCTAssertEqual(landing?.index, 2)
        XCTAssertEqual(landing?.stage, .getReady)
        XCTAssertEqual(landing?.remaining, GetReady.seconds)
    }

    func testTheSupplementedTransitionStretchesTheWayOntoTheFloor() {
        // The one warm-up supplement (issue #83): the transition that takes
        // the person down to the floor, and advance() absorbs it at its LONGER
        // length — the overshoot below is that whole transition plus 2 s of
        // the move itself, written from the constants so the supplement is
        // what the test is actually about.
        //
        // The block has three floor moves in its pool now (§40.1) and still
        // exactly ONE supplement: it is the trip DOWN that is paid for, not
        // each position on the floor.
        let onto = floorIndex
        XCTAssertGreaterThan(onto, 0, "the floor is never the first move")
        let supplemented = GetReady.seconds + GetReady.setupSupplementSec
        XCTAssertEqual(Warmup.stageSeconds(.getReady, of: warmupMoves[onto]), supplemented)
        let landing = Warmup.advance(from: (onto - 1, .move), overshoot: supplemented + 2,
                                     moves: warmupMoves)
        XCTAssertEqual(landing?.index, onto)
        XCTAssertEqual(landing?.stage, .move)
        XCTAssertEqual(landing?.remaining, Warmup.moveSeconds - 2)
    }

    // MARK: - The warm-up's two halves (§41.12)

    func testASplitWarmupMoveWalksTheTwoHalvesAroundThePause() throws {
        let moves = dearestComposition
        let index = try XCTUnwrap(moves.firstIndex(where: \.isSplit),
                                  "the dearest composition must draw a split move")
        XCTAssertEqual(Warmup.step(after: (index, .getReady), moves: moves)?.stage, .firstHalf)
        XCTAssertEqual(Warmup.step(after: (index, .firstHalf), moves: moves)?.stage, .switchPause)
        XCTAssertEqual(Warmup.step(after: (index, .switchPause), moves: moves)?.stage, .secondHalf)
        // All three stay on the same move: the switch is inside one position,
        // not travel to another, and an index that walked would show the next
        // move's name over the wrong countdown.
        for stage in [Warmup.Stage.getReady, .firstHalf, .switchPause] {
            XCTAssertEqual(Warmup.step(after: (index, stage), moves: moves)?.index, index,
                           "\(stage) must not walk off the move it belongs to")
        }
        let next = Warmup.step(after: (index, .secondHalf), moves: moves)
        XCTAssertEqual(next?.index, index + 1, "the far side hands over to the next move")
        XCTAssertEqual(next?.stage, .getReady)
    }

    func testAMoveWithNoBoundaryNeverSeesAHalf() throws {
        let moves = dearestComposition
        let index = try XCTUnwrap(moves.firstIndex(where: { !$0.isSplit }))
        XCTAssertEqual(Warmup.step(after: (index, .getReady), moves: moves)?.stage, .move,
                       "a move with no halfway boundary runs the whole slot in one stage")
    }

    /// The distinction the block turns on: a move splits because its own steps
    /// name a moment, not because the movement looks two-sided. Torso rotations
    /// and cat-cow alternate CONTINUOUSLY — every rep, every breath — so there
    /// is no single moment to announce, and marching swings both legs by
    /// definition. Named by id, because "how many split" says nothing about
    /// which.
    func testOnlyTheMovesWhoseStepsNameAMomentAreSplit() {
        var sides: Set<String> = []
        var directions: Set<String> = []
        var whole: Set<String> = []
        for session in 1...Warmup.compositionCount {
            for move in Warmup.moves(sessionNumber: session) {
                switch move.halves {
                case .sides:      sides.insert(move.id)
                case .directions: directions.insert(move.id)
                case nil:         whole.insert(move.id)
                }
            }
        }
        XCTAssertEqual(sides, ["single-leg-rdl", "bird-dog"])
        XCTAssertEqual(directions, ["arm-circles", "hip-circles"])
        XCTAssertEqual(whole, ["marching", "torso-rotations", "half-squats", "cat-cow", "y-t-w"])
    }

    /// Sides and directions differ in the WORDS and in nothing else. A test
    /// can ask, because the words are a type rather than a `Text` (SwiftUI
    /// `Text` is not reliably equatable — the flake that rule came from).
    func testTheWordsFollowWhatIsSwitchedAndTheSecondsDoNot() throws {
        let sides = SplitStageWords(halves: .sides)
        let directions = SplitStageWords(halves: .directions)
        XCTAssertNotEqual(sides.switching, directions.switching,
                          "a circle about to be reversed must not be told to switch sides")
        XCTAssertNotEqual(sides.secondHalf, directions.secondHalf)
        XCTAssertNotEqual(sides.everyHalf, directions.everyHalf)
        XCTAssertEqual(sides.switching, String(localized: "Switch sides"))
        XCTAssertEqual(directions.switching,
                       String(localized: "warmup.switchDirection",
                              defaultValue: "Switch direction"))
        let moves = dearestComposition
        let bySide = try XCTUnwrap(moves.first { $0.halves == .sides })
        let byDirection = try XCTUnwrap(moves.first { $0.halves == .directions })
        XCTAssertEqual(Warmup.slotSeconds(of: bySide), Warmup.slotSeconds(of: byDirection),
                       "the two kinds cost the same 15 + 5 + 15")
    }

    func testTheTwoHalvesSplitTheSlotAndThePauseRidesOnTop() throws {
        let move = try XCTUnwrap(dearestComposition.first(where: \.isSplit))
        XCTAssertEqual(Warmup.stageSeconds(.firstHalf, of: move), Warmup.halfSeconds)
        XCTAssertEqual(Warmup.stageSeconds(.secondHalf, of: move), Warmup.halfSeconds)
        XCTAssertEqual(Warmup.stageSeconds(.switchPause, of: move), Cooldown.sideSwitchPauseSec)
        XCTAssertEqual(Warmup.slotSeconds(of: move),
                       Warmup.moveSeconds + Cooldown.sideSwitchPauseSec,
                       "the two halves ARE the slot; only the pause is added to it")
        let whole = try XCTUnwrap(dearestComposition.first { !$0.isSplit })
        XCTAssertEqual(Warmup.slotSeconds(of: whole), Warmup.moveSeconds)
    }

    func testTheWarmupEndsAfterTheFarHalfOfASplitLastMove() throws {
        // A composition can end on a split move, and then `.move` is a stage
        // that never runs: the block has to end on `.secondHalf` instead.
        let moves = try XCTUnwrap((1...Warmup.compositionCount)
            .map(Warmup.moves(sessionNumber:))
            .first { $0.last?.isSplit == true },
            "some composition must end on a split move")
        XCTAssertNil(Warmup.step(after: (moves.count - 1, .secondHalf), moves: moves),
                     "the far half of the last move hands the flow to the work")
    }

    func testTheWarmupSwitchIsABoundaryTheFlowCanSound() throws {
        // The tone is chosen from `entered` (see `tickWarmup`), so the pause
        // has to be NAMED when the first side runs out. And a long absence
        // across the whole move must not report a switch nobody is standing
        // at: `entered` and `stage` disagree, and the flow stays silent.
        let moves = dearestComposition
        let index = try XCTUnwrap(moves.firstIndex(where: \.isSplit))
        let intoPause = Warmup.advance(from: (index, .firstHalf), overshoot: 0, moves: moves)
        XCTAssertEqual(intoPause?.entered, .switchPause)
        XCTAssertEqual(intoPause?.remaining, Cooldown.sideSwitchPauseSec)
        let intoSecond = Warmup.advance(from: (index, .switchPause), overshoot: 0, moves: moves)
        XCTAssertEqual(intoSecond?.entered, .secondHalf)
        XCTAssertEqual(intoSecond?.remaining, Warmup.halfSeconds)
        let landing = Warmup.advance(from: (index, .getReady),
                                     overshoot: Warmup.slotSeconds(of: moves[index]) + 1,
                                     moves: moves)
        XCTAssertEqual(landing?.entered, .firstHalf, "the run opened on the first half")
        XCTAssertEqual(landing?.index, index + 1, "...and came to rest past the whole move")
        XCTAssertEqual(landing?.stage, .getReady)
    }

    // MARK: - What the signal has to be chosen from

    func testAdvanceCanLandOnATransitionItDidNotEnter() {
        // Warm-up: one second past a move's own end, so the run opens on the
        // move and rests inside the next position's transition.
        let warmup = Warmup.advance(from: (0, .getReady),
                                    overshoot: Warmup.moveSeconds + 1,
                                    moves: warmupMoves)
        XCTAssertEqual(warmup?.entered, .move, "the run opened on the move")
        XCTAssertEqual(warmup?.stage, .getReady, "...but came to rest on a transition")
        XCTAssertEqual(warmup?.index, 1)

        // Cool-down: the same shape across a whole per-side position.
        let positions = Cooldown.positions(performed: [.pull])
        XCTAssertTrue(positions[0].perSide, "hip flexors open the block per side")
        let cooldown = Cooldown.advance(
            from: (0, .getReady),
            overshoot: Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec + 2,
            positions: positions)
        XCTAssertEqual(cooldown?.entered, .firstSide, "the run opened on the first side")
        XCTAssertEqual(cooldown?.stage, .getReady, "...but came to rest on a transition")
        XCTAssertEqual(cooldown?.index, 1)
        XCTAssertEqual(cooldown?.remaining,
                       GetReady.seconds + GetReady.setupSupplementSec - 2,
                       "chest wall carries the supplement — the wall has to be walked to")
    }

    // MARK: - The cool-down stage machine

    func testEveryCooldownPositionOpensWithTheTransition() {
        let positions = Cooldown.positions(performed: [.pull])
        XCTAssertEqual(Cooldown.openingStage, .getReady)
        for (index, position) in positions.enumerated() {
            let after = Cooldown.step(after: (index, .getReady), positions: positions)
            XCTAssertEqual(after?.index, index, "\(position.id): the transition stays put")
            XCTAssertEqual(after?.stage, position.perSide ? .firstSide : .single,
                           "\(position.id): the transition hands over to the position itself")
        }
    }

    func testABilateralPositionWalksTransitionThenTheWholeSlot() {
        // squat → forward fold, the first bilateral position of the block.
        let positions = Cooldown.positions(performed: [.squat])
        guard let index = positions.firstIndex(where: { !$0.perSide }) else {
            return XCTFail("the composition must contain a bilateral position")
        }
        XCTAssertEqual(Cooldown.step(after: (index, .getReady), positions: positions)?.stage,
                       .single)
        XCTAssertEqual(Cooldown.stageSeconds(.single, of: positions[index]),
                       Cooldown.positionSeconds)
    }

    func testNoStageIsEmpty() {
        // advance() walks stages while the overshoot covers them; a zero-length
        // stage would spin forever.
        for position in Cooldown.positions(performed: [.pull]) {
            for stage in [Cooldown.Stage.getReady, .single, .firstSide, .switchPause, .secondSide] {
                XCTAssertGreaterThan(Cooldown.stageSeconds(stage, of: position), 0,
                                     "\(position.id).\(stage) has no length")
            }
        }
        XCTAssertGreaterThan(Cooldown.switchPauseSeconds, 0)
        for move in warmupMoves + dearestComposition {
            for stage in [Warmup.Stage.getReady, .move, .firstHalf, .switchPause, .secondHalf] {
                XCTAssertGreaterThan(Warmup.stageSeconds(stage, of: move), 0,
                                     "\(stage) at \(move.id) has no length")
            }
        }
    }
}
