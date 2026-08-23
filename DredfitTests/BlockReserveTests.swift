//
//  BlockReserveTests.swift
//  DredfitTests
//
//  v2.26 (spec §37.7a): the warm-up and cool-down reserve, and the arithmetic
//  that makes the transition length an ENGINE constraint rather than an app
//  preference.
//
//  `warmupMin + cooldownMin` is the whole budget the engine sets aside for the
//  two blocks, and the worst composition spends it TO THE SECOND. That is why
//  doubling the transition could not be done in this target alone: one second
//  more and the reserve breaks, which is a change to the engine — and v2.26 is
//  that change.
//
//  Everything below is computed from the app's own constants and from the real
//  composition rule, never from the spec's numbers restated. The worst case is
//  found by ENUMERATING the cool-down sets a session can actually produce
//  rather than by assuming which six positions are dearest: if the pool, the
//  mapping or a hold ever moves, this fails here instead of on somebody's
//  stopwatch.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class BlockReserveTests: XCTestCase {

    /// One warm-up move: its transition plus the move itself.
    private func cost(_ move: WarmupMove) -> Int {
        GetReady.stageSeconds(needsSetup: move.needsSetup) + Warmup.moveSeconds
    }

    /// One cool-down position: its transition plus the hold. A per-side hold is
    /// two halves with the switch pause between them.
    private func cost(_ position: CooldownPosition) -> Int {
        let hold = position.perSide
            ? Cooldown.sideSeconds + Cooldown.sideSwitchPauseSec + Cooldown.sideSeconds
            : Cooldown.positionSeconds
        return GetReady.stageSeconds(needsSetup: position.needsSetup) + hold
    }

    private var warmupSec: Int { Warmup.moves.map(cost).reduce(0, +) }

    /// The dearest cool-down a session can actually draw. Every subset of the
    /// movements is walked, in both orders — the composition maps `performed`
    /// in order and tops up from the pool, so order is part of the input.
    private func worstCooldownSec() -> Int {
        var worst = 0
        let all = Pattern.allCases
        for mask in 0..<(1 << all.count) {
            let performed = all.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            guard !performed.isEmpty else { continue }
            for ordered in [performed, performed.reversed()] {
                let sec = Cooldown.positions(performed: Array(ordered)).map(cost).reduce(0, +)
                worst = max(worst, sec)
            }
        }
        return worst
    }

    func testTheWorstCompositionFitsTheEngineReserve() {
        let reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        XCTAssertEqual(reserve, 540, "§37.7a: the reserve is 9:00")
        XCTAssertLessThanOrEqual(
            warmupSec + worstCooldownSec(), reserve,
            "the worst composition of the two blocks overruns the engine's reserve")
    }

    /// And it is spent EXACTLY — the property that makes the next second a
    /// change to the engine rather than to this target. Were this ever to pass
    /// with room to spare, the reserve and the blocks would have drifted apart
    /// and the announced duration would be quietly wrong the other way.
    func testTheReserveIsSpentToTheSecond() {
        let reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        XCTAssertEqual(warmupSec + worstCooldownSec(), reserve,
                       "§37.7a: the reserve is spent exactly, with nothing to spare")
    }

    /// The two halves separately, so a failure says WHICH block moved.
    func testEachBlockCostsWhatTheSpecSays() {
        XCTAssertEqual(warmupSec, 245, "§37.7a: the warm-up's composition is 245 s")
        XCTAssertEqual(worstCooldownSec(), 295, "§37.7a: the worst cool-down is 295 s")
    }

    /// The transition doubled; the supplement did not (§37.7a).
    func testTheTransitionIsTenSecondsAndTheSupplementIsFive() {
        XCTAssertEqual(GetReady.seconds, 10)
        XCTAssertEqual(GetReady.setupSupplementSec, 5)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: false), 10)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: true), 15)
    }

    /// The side-switch pause did NOT follow the transition to ten. It is a
    /// pause inside one position, not travel to another, and §37.7a's own
    /// arithmetic counts it as five.
    func testTheSideSwitchPauseStayedAtFive() {
        XCTAssertEqual(Cooldown.sideSwitchPauseSec, 5)
    }
}
