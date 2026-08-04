//
//  GetReadyTests.swift
//  DredfitTests
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class GetReadyTests: XCTestCase {

    // MARK: - The transition itself

    func testTheTransitionIsTheSameLengthAsTheSideSwitchPause() {
        // One transition, one length: #35 counts the switch inside a
        // position, #52 counts the switch between positions.
        XCTAssertEqual(GetReady.seconds, 5)
        XCTAssertEqual(GetReady.seconds, Cooldown.sideSwitchPauseSec)
        XCTAssertEqual(Cooldown.stageSeconds(.getReady), GetReady.seconds)
        XCTAssertEqual(Warmup.stageSeconds(.getReady), GetReady.seconds)
    }

    func testTheTransitionLeavesRoomForTheCountdownItPlays() {
        // The 3-2-1 has to fit inside it with a beat to spare for reading the
        // name of what is coming — a transition shorter than the ticks would
        // start mid-signal.
        XCTAssertGreaterThan(GetReady.seconds, 3)
    }

    // MARK: - Honest numbers

    /// The decision this feature rests on: the transitions ride on top of the
    /// minutes the engine already reserves for the two blocks, so no estimate
    /// moves and `golden.json` stays untouched. Worst case — every cool-down
    func testBothBlocksFitInsideTheReservedWarmupAndCooldownMinutes() {
        let warmup = Warmup.moves.count * (GetReady.seconds + Warmup.moveSeconds)
        let worstPosition = GetReady.seconds
            + Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec
        let cooldown = Cooldown.positionCount * worstPosition
        let reserved = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60

        XCTAssertEqual(warmup, 210)
        XCTAssertEqual(cooldown, 240)
        XCTAssertLessThanOrEqual(warmup + cooldown, reserved,
                                 "the blocks must not outgrow the minutes the estimate reserves")
    }

    func testARealCompositionLeavesEvenMoreRoom() {
        let performed = Engine.generateSession(.initial).exercises.map(\.pattern)
        let positions = Cooldown.positions(performed: performed)
        let cooldown = positions.reduce(0) { total, position in
            total + GetReady.seconds + (position.perSide
                ? Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec
                : Cooldown.positionSeconds)
        }
        let warmup = Warmup.moves.count * (GetReady.seconds + Warmup.moveSeconds)
        XCTAssertLessThan(warmup + cooldown,
                          (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60)
    }

    // MARK: - The warm-up stage machine

    func testEveryWarmupMoveOpensWithTheTransition() {
        // The first one included: the user has just pressed Start and is
        // still standing by the phone.
        XCTAssertEqual(Warmup.step(after: (0, .getReady))?.stage, .move)
        let next = Warmup.step(after: (0, .move))
        XCTAssertEqual(next?.index, 1)
        XCTAssertEqual(next?.stage, .getReady)
    }

    func testTheWarmupEndsAfterTheLastMove() {
        XCTAssertNil(Warmup.step(after: (Warmup.moves.count - 1, .move)),
                     "the last move hands the flow to the first exercise")
        XCTAssertNotNil(Warmup.step(after: (Warmup.moves.count - 1, .getReady)),
                        "...but its own transition still has a move to announce")
    }

    func testWarmupAdvanceNamesTheStageItEnters() {
        let intoMove = Warmup.advance(from: (0, .getReady), overshoot: 0)
        XCTAssertEqual(intoMove?.entered, .move)
        XCTAssertEqual(intoMove?.remaining, Warmup.moveSeconds)
        let intoTransition = Warmup.advance(from: (0, .move), overshoot: 0)
        XCTAssertEqual(intoTransition?.entered, .getReady)
        XCTAssertEqual(intoTransition?.index, 1)
        XCTAssertEqual(intoTransition?.remaining, GetReady.seconds)
    }

    func testWarmupAdvanceAbsorbsBackgroundedTime() {
        // 7 s past a move's end: the next transition (5) is consumed whole,
        // landing 2 s into the move it announced.
        let landing = Warmup.advance(from: (0, .move), overshoot: 7)
        XCTAssertEqual(landing?.index, 1)
        XCTAssertEqual(landing?.stage, .move)
        XCTAssertEqual(landing?.remaining, Warmup.moveSeconds - 2)
        // An absence past the whole block simply ends it.
        XCTAssertNil(Warmup.advance(from: (0, .move), overshoot: 10_000))
    }

    func testWarmupOvershootLandsOnAWholeMoveBoundary() {
        // A full move-plus-transition of absence advances by exactly one move
        // and lands at the top of the next transition, not mid-anything.
        let cycle = GetReady.seconds + Warmup.moveSeconds
        let landing = Warmup.advance(from: (0, .move), overshoot: cycle)
        XCTAssertEqual(landing?.index, 2)
        XCTAssertEqual(landing?.stage, .getReady)
        XCTAssertEqual(landing?.remaining, GetReady.seconds)
    }

    // MARK: - What the signal has to be chosen from

    func testAdvanceCanLandOnATransitionItDidNotEnter() {
        // Warm-up: one second past a move's own end, so the run opens on the
        // move and rests inside the next position's transition.
        let warmup = Warmup.advance(from: (0, .getReady),
                                    overshoot: Warmup.moveSeconds + 1)
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
        XCTAssertEqual(cooldown?.remaining, GetReady.seconds - 2)
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
        XCTAssertEqual(Cooldown.stageSeconds(.single), Cooldown.positionSeconds)
    }

    func testNoStageIsEmpty() {
        // advance() walks stages while the overshoot covers them; a zero-length
        // stage would spin forever.
        for stage in [Cooldown.Stage.getReady, .single, .firstSide, .switchPause, .secondSide] {
            XCTAssertGreaterThan(Cooldown.stageSeconds(stage), 0, "\(stage) has no length")
        }
        for stage in [Warmup.Stage.getReady, .move] {
            XCTAssertGreaterThan(Warmup.stageSeconds(stage), 0, "\(stage) has no length")
        }
    }
}
