import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class GetReadyTests: XCTestCase {

    /// The block composes six moves out of fourteen, so a stage machine cannot
    /// be asked about "the moves" — it has to be asked about a COMPOSITION.
    /// Session one's, which opens on a squat, throughout; the reserve tests in
    /// BlockReserveTests walk all of them.
    private let warmupMoves = Warmup.moves(sessionNumber: 1, opening: .squat)

    /// Every composition with nothing set aside: each session of the rotation
    /// against every opening the lead-in reads, and none.
    private var everyComposition: [[WarmupMove]] {
        (1...Warmup.rotationPeriod).flatMap { session in
            ([nil] + Pattern.allCases).map { Warmup.moves(sessionNumber: session, opening: $0) }
        }
    }

    /// What one warm-up move costs uninterrupted: the transition, then the
    /// thirty seconds — a reversed circle's two halves ARE the slot.
    /// Hand-rolled on purpose, unlike the cool-down twin below: an
    /// independent statement of the warm-up arithmetic.
    private func cost(of move: WarmupMove) -> Int {
        GetReady.seconds + Warmup.moveSeconds
    }

    // MARK: - The transition itself

    /// The transition and the side-switch pause are two different things: #35
    /// counts the switch inside a position, #52 the switch between positions.
    /// Travelling to another position takes time, turning over inside one does
    /// not — so they part on WHAT they are, not on how long they happen to be,
    /// and the split is pinned in both directions.
    func testTheTransitionAndTheSideSwitchPauseKeepTheirOwnLengths() {
        XCTAssertEqual(GetReady.seconds, 8)
        XCTAssertEqual(Cooldown.sideSwitchPauseSec, 4)   // on trial
        XCTAssertNotEqual(GetReady.seconds, Cooldown.sideSwitchPauseSec,
                          "the transition and the switch pause must stay two lengths")
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: false), GetReady.seconds)
        XCTAssertEqual(GuidedBlock.warmup.stageSeconds(.getReady, of: warmupMoves[0]),
                       GetReady.seconds,
                       "marching starts where the user already stands")
    }

    func testAPositionThatHasToBeGotIntoGetsTheSupplement() {
        // The differentiated pause of issue #83: base plus supplement for a
        // position that changes the starting position or needs a prop.
        XCTAssertEqual(GetReady.setupSupplementSec, 4)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: true),
                       GetReady.seconds + GetReady.setupSupplementSec)
        let positions = Cooldown.positions(performed: [.pull])
        XCTAssertEqual(positions[0].id, "hip-flexors")
        XCTAssertEqual(GuidedBlock.cooldown.stageSeconds(.getReady, of: positions[0]),
                       GetReady.seconds + GetReady.setupSupplementSec,
                       "the block opens by getting down onto one knee")
    }

    func testOnlyTheStandingPositionsKeepTheBaseTransition() {
        // The flag travels with the data, so this is the list issue #83
        // pinned: the warm-up never leaves standing, and in the cool-down only forward fold, the lat stretch and the wrists stay
        // upright with no wall to walk to.
        for moves in everyComposition {
            XCTAssertEqual(moves.filter(\.needsSetup).map(\.id), [],
                           "\(moves.map(\.id)): a warm-up transition paid the supplement")
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
    /// re-deriving `seconds + setupSupplementSec` by hand, as
    /// `BlockReserveTests.cost(_:CooldownPosition)` does too: two spellings of
    /// one formula stay correct only as long as nobody changes the production
    /// one without noticing the copy. Calling the real function makes that
    /// impossible instead of merely unlikely.
    private func cost(of position: CooldownPosition) -> Int {
        let hold = position.perSide
            ? Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec
            : Cooldown.positionSeconds
        return GetReady.stageSeconds(needsSetup: position.needsSetup) + hold
    }

    /// The decision this feature rests on: the transitions — supplements
    /// included (#83) — ride on top of the minutes the engine reserves for
    /// the two blocks. The worst case with nothing set aside is exact: the
    /// dearest warm-up plus the fixed three positions plus the costliest three
    /// the mapping can draw. BlockReserveTests adds the set-aside axis, where
    /// the warm-up stays at 228 s — every slot costs the same.
    ///
    /// The FIT is not exact: a reserve is whole minutes, so it carries slack.
    /// What is guarded is that the slack stays under two minutes — more, and
    /// the engine would be holding minutes the blocks do not use.
    func testBothBlocksFitInsideTheReservedWarmupAndCooldownMinutes() {
        let warmup = everyComposition.map { $0.map(cost(of:)).reduce(0, +) }.max() ?? 0

        // One pattern per pool position; index 2 of a one-pattern composition
        // is the position that pattern maps to.
        let pool = [Pattern.squat, .pull, .pushH, .coreAntiExt, .calf, .lunge]
            .map { Cooldown.positions(performed: [$0])[2] }
        let worstMapped = pool.map(cost(of:)).sorted(by: >).prefix(3).reduce(0, +)
        let anyComposition = Cooldown.positions(performed: [.squat])
        let fixed = cost(of: anyComposition[0]) + cost(of: anyComposition[1])
            + cost(of: anyComposition[5])
        let reserved = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60

        // Lengthening the transition is what makes the reserve an engine
        // constraint; shortening it only ever leaves slack.
        XCTAssertEqual(warmup, 228)
        XCTAssertEqual(fixed + worstMapped, 272)
        XCTAssertLessThanOrEqual(warmup + fixed + worstMapped, reserved,
                                 "the worst case overruns the reserved minutes")
        // Ten minutes is not the smallest whole minute that fits, and the
        // owner keeps it: giving the minute back is `cooldownMin` 4 → 3
        // through the reference chain, and it would take a minute off every
        // announced duration to reclaim slack nobody is short of. What is
        // guarded is drift, not tightness — `BlockReserveTests` holds the same
        // floor and ceiling over the axis the app actually composes on.
        XCTAssertLessThan(reserved - (warmup + fixed + worstMapped), 120,
                          "two whole minutes of slack: the reserve is no longer "
                          + "sized against the blocks it exists for")
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
        XCTAssertEqual(GuidedBlock.step(after: (0, .getReady), positions: warmupMoves)?.stage, .whole)
        let next = GuidedBlock.step(after: (0, .whole), positions: warmupMoves)
        XCTAssertEqual(next?.index, 1)
        XCTAssertEqual(next?.stage, .getReady)
    }

    func testTheWarmupEndsAfterTheLastMove() {
        XCTAssertNil(GuidedBlock.step(after: (warmupMoves.count - 1, .whole), positions: warmupMoves),
                     "the last move hands the flow to the first exercise")
        XCTAssertNotNil(GuidedBlock.step(after: (warmupMoves.count - 1, .getReady),
                                    positions: warmupMoves),
                        "...but its own transition still has a move to announce")
    }

    func testWarmupAdvanceNamesTheStageItEnters() {
        let intoMove = GuidedBlock.warmup.advance(from: (0, .getReady), overshoot: 0, positions: warmupMoves)
        XCTAssertEqual(intoMove?.entered, .whole)
        XCTAssertEqual(intoMove?.remaining, Warmup.moveSeconds)
        let intoTransition = GuidedBlock.warmup.advance(from: (0, .whole), overshoot: 0,
                                            positions: warmupMoves)
        XCTAssertEqual(intoTransition?.entered, .getReady)
        XCTAssertEqual(intoTransition?.index, 1)
        XCTAssertEqual(intoTransition?.remaining, GetReady.seconds)
    }

    func testWarmupAdvanceAbsorbsBackgroundedTime() throws {
        // Past a move's end by the whole next transition plus two seconds: the
        // transition is consumed whole and the landing is 2 s into the move it
        // announced. Written from the constant rather than from a literal,
        // which would silently go wrong the next time the transition moves.
        //
        // WHICH stage that move opens on is asked of the machine, not assumed:
        // a split move opens on its first half, not on the whole slot.
        let opening = try XCTUnwrap(GuidedBlock.step(after: (1, .getReady),
                                                positions: warmupMoves)?.stage)
        let landing = GuidedBlock.warmup.advance(from: (0, .whole), overshoot: GetReady.seconds + 2,
                                     positions: warmupMoves)
        XCTAssertEqual(landing?.index, 1)
        XCTAssertEqual(landing?.stage, opening)
        XCTAssertEqual(landing?.remaining,
                       GuidedBlock.warmup.stageSeconds(opening, of: warmupMoves[1]) - 2)
        // An absence past the whole block simply ends it.
        XCTAssertNil(GuidedBlock.warmup.advance(from: (0, .whole), overshoot: 10_000, positions: warmupMoves))
    }

    func testWarmupOvershootLandsOnAWholeMoveBoundary() {
        // A full move-plus-transition of absence advances by exactly one move
        // and lands at the top of the next transition, not mid-anything. A
        // reversed circle runs the same thirty seconds as a whole move: its
        // halves have nothing between them.
        let cycle = GuidedBlock.warmup.stageSeconds(.getReady, of: warmupMoves[1])
            + Warmup.moveSeconds
        let landing = GuidedBlock.warmup.advance(from: (0, .whole), overshoot: cycle, positions: warmupMoves)
        XCTAssertEqual(landing?.index, 2)
        XCTAssertEqual(landing?.stage, .getReady)
        XCTAssertEqual(landing?.remaining, GetReady.seconds)
    }

    // MARK: - The warm-up's two halves

    /// A circle walks its two halves with NOTHING between them: the switch
    /// pause is for a side switch, which re-sets the body, and a circle
    /// reverses on the move. Both halves stay on the same move — an index
    /// that walked would show the next move's name over the wrong countdown.
    func testAReversedMoveWalksItsTwoHalvesWithNoPause() throws {
        let moves = warmupMoves
        let index = try XCTUnwrap(moves.firstIndex(where: \.reverses),
                                  "session one must draw a circle")
        XCTAssertEqual(GuidedBlock.step(after: (index, .getReady), positions: moves)?.stage, .firstHalf)
        let second = GuidedBlock.step(after: (index, .firstHalf), positions: moves)
        XCTAssertEqual(second?.stage, .secondHalf, "a circle reverses on the move: no switch pause")
        XCTAssertEqual(second?.index, index, "the second half belongs to the same move")
        let next = GuidedBlock.step(after: (index, .secondHalf), positions: moves)
        XCTAssertEqual(next?.index, index + 1, "the far half hands over to the next move")
        XCTAssertEqual(next?.stage, .getReady)
    }

    func testAMoveWithNoBoundaryNeverSeesAHalf() throws {
        let moves = warmupMoves
        let index = try XCTUnwrap(moves.firstIndex(where: { !$0.reverses }))
        XCTAssertEqual(GuidedBlock.step(after: (index, .getReady), positions: moves)?.stage, .whole,
                       "a move with no halfway boundary runs the whole slot in one stage")
    }

    /// The distinction the block turns on: a move splits because its own steps
    /// name a moment, not because the movement looks two-sided. Side steps,
    /// torso rotations, side bends and overhead reaches change side every rep,
    /// so there is no single moment to announce. Named by id, because "how
    /// many split" says nothing about which — and no move splits by SIDE: the
    /// warm-up asks nothing of one leg or one arm at a time.
    func testOnlyTheCirclesAreSplitAndNoneBySide() {
        var reversing: Set<String> = []
        var whole: Set<String> = []
        for move in everyComposition.joined() {
            XCTAssertNotEqual(move.halves, .sides, "\(move.id) splits by side")
            if move.reverses { reversing.insert(move.id) } else { whole.insert(move.id) }
        }
        XCTAssertEqual(reversing, ["arm-circles", "wrist-circles", "hip-circles"])
        XCTAssertEqual(whole, ["marching", "side-steps", "heels-to-glutes", "arm-swings",
                               "reach-and-pull", "overhead-reaches", "torso-rotations",
                               "side-bends", "standing-cat-cow", "hip-hinges", "half-squats"])
    }

    /// Sides and directions differ in the WORDS and in whether the clock stops.
    /// A test can ask about the words because they are a type rather than a
    /// `Text` (SwiftUI `Text` is not reliably equatable — the flake that rule
    /// came from).
    func testTheWordsFollowWhatIsSwitchedAndOnlyASideSwitchPauses() {
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
        XCTAssertTrue(WarmupHalves.sides.pausesAtTheSwitch, "turning over re-sets the body")
        XCTAssertFalse(WarmupHalves.directions.pausesAtTheSwitch, "a circle reverses on the move")
    }

    func testTheTwoHalvesOfACircleAreTheSlot() throws {
        let move = try XCTUnwrap(warmupMoves.first(where: \.reverses))
        XCTAssertEqual(GuidedBlock.warmup.stageSeconds(.firstHalf, of: move), Warmup.halfSeconds)
        XCTAssertEqual(GuidedBlock.warmup.stageSeconds(.secondHalf, of: move), Warmup.halfSeconds)
        XCTAssertEqual(Warmup.halfSeconds * 2, Warmup.moveSeconds,
                       "the two halves ARE the slot, and nothing rides on top of it")
    }

    func testTheWarmupEndsAfterTheFarHalfOfASplitLastMove() throws {
        // A composition can end on a circle — a session with no exercise to
        // lead into, whose trunk slot drew hip circles — and then `.whole` is a
        // stage that never runs: the block has to end on `.secondHalf` instead.
        let moves = try XCTUnwrap(everyComposition.first { $0.last?.reverses == true },
                                  "some composition must end on a circle")
        XCTAssertNil(GuidedBlock.step(after: (moves.count - 1, .secondHalf), positions: moves),
                     "the far half of the last move hands the flow to the work")
    }

    func testTheWarmupSwitchIsABoundaryTheFlowCanSound() throws {
        // The tone is chosen from `entered` (see `WorkoutSession.tick(_:)`), so
        // the second half has to be NAMED when the first runs out — with its
        // whole fifteen seconds, no pause taken out of them. And a long absence
        // across the whole move must not report a switch nobody is standing
        // at: `entered` and `stage` disagree, and the flow stays silent.
        let moves = warmupMoves
        let index = try XCTUnwrap(moves.firstIndex(where: \.reverses))
        let intoSecond = GuidedBlock.warmup.advance(from: (index, .firstHalf), overshoot: 0, positions: moves)
        XCTAssertEqual(intoSecond?.entered, .secondHalf)
        XCTAssertEqual(intoSecond?.remaining, Warmup.halfSeconds)
        let landing = GuidedBlock.warmup.advance(from: (index, .getReady),
                                     overshoot: Warmup.moveSeconds + 1,
                                     positions: moves)
        XCTAssertEqual(landing?.entered, .firstHalf, "the run opened on the first half")
        XCTAssertEqual(landing?.index, index + 1, "...and came to rest past the whole move")
        XCTAssertEqual(landing?.stage, .getReady)
    }

    // MARK: - What the signal has to be chosen from

    func testAdvanceCanLandOnATransitionItDidNotEnter() {
        // Warm-up: one second past a move's own end, so the run opens on the
        // move and rests inside the next position's transition.
        let warmup = GuidedBlock.warmup.advance(from: (0, .getReady),
                                    overshoot: Warmup.moveSeconds + 1,
                                    positions: warmupMoves)
        XCTAssertEqual(warmup?.entered, .whole, "the run opened on the move")
        XCTAssertEqual(warmup?.stage, .getReady, "...but came to rest on a transition")
        XCTAssertEqual(warmup?.index, 1)

        // Cool-down: the same shape across a whole per-side position.
        let positions = Cooldown.positions(performed: [.pull])
        XCTAssertTrue(positions[0].perSide, "hip flexors open the block per side")
        let cooldown = GuidedBlock.cooldown.advance(
            from: (0, .getReady),
            overshoot: Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec + 2,
            positions: positions)
        XCTAssertEqual(cooldown?.entered, .firstHalf, "the run opened on the first side")
        XCTAssertEqual(cooldown?.stage, .getReady, "...but came to rest on a transition")
        XCTAssertEqual(cooldown?.index, 1)
        XCTAssertEqual(cooldown?.remaining,
                       GetReady.seconds + GetReady.setupSupplementSec - 2,
                       "chest wall carries the supplement — the wall has to be walked to")
    }

    // MARK: - The cool-down stage machine

    func testEveryCooldownPositionOpensWithTheTransition() {
        let positions = Cooldown.positions(performed: [.pull])
        for (index, position) in positions.enumerated() {
            let after = GuidedBlock.step(after: (index, .getReady), positions: positions)
            XCTAssertEqual(after?.index, index, "\(position.id): the transition stays put")
            XCTAssertEqual(after?.stage, position.perSide ? .firstHalf : .whole,
                           "\(position.id): the transition hands over to the position itself")
        }
    }

    func testABilateralPositionWalksTransitionThenTheWholeSlot() {
        // squat → forward fold, the first bilateral position of the block.
        let positions = Cooldown.positions(performed: [.squat])
        guard let index = positions.firstIndex(where: { !$0.perSide }) else {
            return XCTFail("the composition must contain a bilateral position")
        }
        XCTAssertEqual(GuidedBlock.step(after: (index, .getReady), positions: positions)?.stage,
                       .whole)
        XCTAssertEqual(GuidedBlock.cooldown.stageSeconds(.whole, of: positions[index]),
                       Cooldown.positionSeconds)
    }

    /// The other half of the rule the warm-up's circles changed: a SIDE switch
    /// still stops the clock for its pause, because turning over re-sets the
    /// body. Both blocks walk one stage machine, so the circle's shortcut must
    /// not leak into the stretch.
    func testASideSwitchStillPauses() throws {
        let positions = Cooldown.positions(performed: [.pull])
        let index = try XCTUnwrap(positions.firstIndex(where: \.perSide))
        XCTAssertEqual(GuidedBlock.step(after: (index, .firstHalf), positions: positions)?.stage,
                       .switchPause)
        XCTAssertEqual(GuidedBlock.step(after: (index, .switchPause), positions: positions)?.stage,
                       .secondHalf)
    }

    func testNoStageIsEmpty() {
        // advance() walks stages while the overshoot covers them; a zero-length
        // stage would spin forever.
        for position in Cooldown.positions(performed: [.pull]) {
            for stage in [GuidedStage.getReady, .whole, .firstHalf, .switchPause, .secondHalf] {
                XCTAssertGreaterThan(GuidedBlock.cooldown.stageSeconds(stage, of: position), 0,
                                     "\(position.id).\(stage) has no length")
            }
        }
        XCTAssertGreaterThan(Cooldown.switchPauseSeconds, 0)
        for move in everyComposition.joined() {
            for stage in [GuidedStage.getReady, .whole, .firstHalf, .switchPause, .secondHalf] {
                XCTAssertGreaterThan(GuidedBlock.warmup.stageSeconds(stage, of: move), 0,
                                     "\(stage) at \(move.id) has no length")
            }
        }
    }
}
