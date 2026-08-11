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

    func testTheBaseTransitionIsTheSameLengthAsTheSideSwitchPause() {
        // One base length: #35 counts the switch inside a position, #52
        // counts the switch between positions. #83 split the transition in
        // two, but the base is still the identity — the side-switch pause
        // never carries the supplement, nobody changes support mid-position.
        XCTAssertEqual(GetReady.seconds, 5)
        XCTAssertEqual(GetReady.seconds, Cooldown.sideSwitchPauseSec)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: false), GetReady.seconds)
        XCTAssertEqual(Warmup.stageSeconds(.getReady, index: 0), GetReady.seconds,
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
        XCTAssertEqual(Warmup.moves.filter(\.needsSetup).map(\.id), ["cat-cow"])
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
    private func cost(of position: CooldownPosition) -> Int {
        GetReady.seconds
            + (position.needsSetup ? GetReady.setupSupplementSec : 0)
            + (position.perSide
                ? Cooldown.sideSeconds * 2 + Cooldown.sideSwitchPauseSec
                : Cooldown.positionSeconds)
    }

    /// The decision this feature rests on: the transitions — supplements
    /// included since #83 — ride on top of the minutes the engine already
    /// reserves for the two blocks, so no estimate moves and `golden.json`
    /// stays untouched. The worst case is exact, not a bound: the fixed
    /// three positions plus the costliest three the mapping can draw land on
    /// the reserve to the second, which is why the supplement is five and
    /// not six.
    func testBothBlocksFitInsideTheReservedWarmupAndCooldownMinutes() {
        let warmup = Warmup.moves.reduce(0) { total, move in
            total + GetReady.seconds
                + (move.needsSetup ? GetReady.setupSupplementSec : 0)
                + Warmup.moveSeconds
        }

        // One pattern per pool position; index 2 of a one-pattern composition
        // is the position that pattern maps to (spec §4).
        let pool = [Pattern.squat, .pull, .pushH, .coreAntiExt, .calf, .lunge]
            .map { Cooldown.positions(performed: [$0])[2] }
        let worstMapped = pool.map(cost(of:)).sorted(by: >).prefix(3).reduce(0, +)
        let anyComposition = Cooldown.positions(performed: [.squat])
        let fixed = cost(of: anyComposition[0]) + cost(of: anyComposition[1])
            + cost(of: anyComposition[5])
        let reserved = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60

        XCTAssertEqual(warmup, 215)
        XCTAssertEqual(fixed + worstMapped, 265)
        XCTAssertEqual(warmup + fixed + worstMapped, reserved,
                       "the worst case fills the reserved minutes exactly — "
                         + "any longer supplement is an engine change")
    }

    func testARealCompositionLeavesRoom() {
        let performed = Engine.generateSession(.initial).exercises.map(\.pattern)
        let cooldown = Cooldown.positions(performed: performed)
            .reduce(0) { $0 + cost(of: $1) }
        let warmup = Warmup.moves.reduce(0) { total, move in
            total + GetReady.seconds
                + (move.needsSetup ? GetReady.setupSupplementSec : 0)
                + Warmup.moveSeconds
        }
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

    func testTheSupplementedTransitionStretchesTheWayIntoCatCow() {
        // The one warm-up supplement (issue #83): the transition into cat-cow
        // covers getting down onto all fours, and advance() absorbs it at its
        // longer length — 12 s past the fifth move's end is the whole 10 s
        // transition plus 2 s of the move itself.
        let catCow = Warmup.moves.count - 1
        XCTAssertEqual(Warmup.stageSeconds(.getReady, index: catCow),
                       GetReady.seconds + GetReady.setupSupplementSec)
        let landing = Warmup.advance(from: (catCow - 1, .move), overshoot: 12)
        XCTAssertEqual(landing?.index, catCow)
        XCTAssertEqual(landing?.stage, .move)
        XCTAssertEqual(landing?.remaining, Warmup.moveSeconds - 2)
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
        for index in Warmup.moves.indices {
            for stage in [Warmup.Stage.getReady, .move] {
                XCTAssertGreaterThan(Warmup.stageSeconds(stage, index: index), 0,
                                     "\(stage) at \(index) has no length")
            }
        }
    }
}
