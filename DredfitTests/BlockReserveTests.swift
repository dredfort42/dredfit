//
//  The warm-up and cool-down reserve, and the arithmetic
//  that makes the transition length an ENGINE constraint rather than an app
//  preference.
//
//  `warmupMin + cooldownMin` is the whole budget the engine sets aside for the
//  two blocks, and the worst composition spent it TO THE SECOND until §41.12
//  gave the warm-up its side switch. That is why neither the doubled transition
//  nor that switch could be done in this target alone: ten seconds more and the
//  reserve breaks, which is a change to the engine — and both times it was one.
//  What the reserve is now is the SMALLEST whole minute that fits, which is the
//  exact property the equality became.
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

    /// One warm-up move: its transition plus the slot. A unilateral move is two
    /// halves with the switch pause between them (§41.12), which is what
    /// `slotSeconds` answers — asked of the production function rather than
    /// restated here, for the reason GetReadyTests gives about its cool-down
    /// twin: two spellings of one formula agree only until one is edited.
    private func cost(_ move: WarmupMove) -> Int {
        GetReady.stageSeconds(needsSetup: move.needsSetup) + Warmup.slotSeconds(of: move)
    }

    /// One cool-down position: its transition plus the hold. A per-side hold is
    /// two halves with the switch pause between them.
    private func cost(_ position: CooldownPosition) -> Int {
        let hold = position.perSide
            ? Cooldown.sideSeconds + Cooldown.sideSwitchPauseSec + Cooldown.sideSeconds
            : Cooldown.positionSeconds
        return GetReady.stageSeconds(needsSetup: position.needsSetup) + hold
    }

    /// One composition of the warm-up.
    private func warmupSec(session: Int) -> Int {
        Warmup.moves(sessionNumber: session).map(cost).reduce(0, +)
    }

    /// The dearest warm-up a session can draw. The block composes six moves
    /// out of nine now (§40.1), so "what the warm-up costs" is a claim about
    /// EVERY composition — and since §41.12 they no longer all cost the same:
    /// four moves of the pool have a halfway boundary, the rotation's window of
    /// three draws one or two of them on top of the permanent arm circles, and
    /// each pays a switch pause.
    private func worstWarmupSec() -> Int {
        (1...Warmup.compositionCount).map(warmupSec(session:)).max() ?? 0
    }

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
        XCTAssertEqual(reserve, 600, "§41.12: the reserve is 10:00")
        XCTAssertLessThanOrEqual(
            worstWarmupSec() + worstCooldownSec(), reserve,
            "the worst composition of the two blocks overruns the engine's reserve")
    }

    /// RE-MARKED by §41.12, and deliberately not deleted.
    ///
    /// The claim used to be equality — the reserve spent to the second, which
    /// is what made the next second an ENGINE change. The warm-up's counted
    /// switch cost 15 s, and a reserve is whole minutes: 9:00 no longer fits,
    /// 10:00 fits with 45 s to spare, and equality became unreachable. An unreachable
    /// assert gets deleted, and then nothing watches the two numbers at all —
    /// so what is pinned is the property that IS still exact: the reserve is
    /// the SMALLEST whole minute that fits. Drift in either direction breaks
    /// it, and a whole minute of slack would mean the engine is holding a
    /// minute the blocks no longer need.
    func testTheReserveIsTheSmallestWholeMinuteThatFits() {
        let reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        let worst = worstWarmupSec() + worstCooldownSec()
        XCTAssertEqual(worst, 555, "§41.12: the worst pair of blocks is 555 s")
        XCTAssertGreaterThanOrEqual(reserve - worst, 0,
                                    "the blocks overrun what the engine reserves")
        XCTAssertLessThan(reserve - worst, 60,
                          "a whole minute of slack: the reserve could be given back")
    }

    /// The two halves separately, so a failure says WHICH block moved. The
    /// warm-up's offer screen names a length before the person agrees to it,
    /// and the one thing it must never do is under-promise — a block that
    /// overruns what it said is worse than one that beats it.
    ///
    /// Derived from the same composition the reserve above is, so adding a
    /// move fails here rather than quietly making the screen lie.
    func testTheWarmupOfferNeverPromisesLessThanTheBlockTakes() {
        for session in 1...Warmup.compositionCount {
            let moves = Warmup.moves(sessionNumber: session)
            let announced = Warmup.introMinutes(moves)
            let actual = warmupSec(session: session)
            XCTAssertGreaterThanOrEqual(
                announced * 60, actual,
                "session \(session): the offer promises \(announced) min "
                + "for a block that takes \(actual) s")
            // And not absurdly more: rounding up one minute, never two.
            XCTAssertLessThan(announced * 60, actual + 60,
                              "session \(session): the offer overstates the block by a minute")
        }
    }

    func testEachBlockCostsWhatTheSpecSays() {
        // EVERY composition, not just one. A composition costs the 245 s of
        // §37.7a plus one switch pause per SPLIT move it draws (§41.12) —
        // written as arithmetic over the composition rather than as a table of
        // six numbers, because a table says nothing about WHY they differ.
        for session in 1...Warmup.compositionCount {
            let split = Warmup.moves(sessionNumber: session).filter(\.isSplit).count
            XCTAssertEqual(warmupSec(session: session),
                           245 + split * Cooldown.sideSwitchPauseSec,
                           "§41.12: composition \(session) draws \(split) split moves")
            XCTAssertGreaterThanOrEqual(split, 2,
                                        "arm circles are permanent and cat-cow is not split, "
                                        + "so every composition pays at least the circles")
        }
        XCTAssertEqual(worstWarmupSec(), 260, "§41.12: the dearest warm-up is 260 s")
        XCTAssertEqual(worstCooldownSec(), 295, "§37.7a: the worst cool-down is 295 s")
    }

    /// Four of the nine, and a composition can hold three of them — which is
    /// why the reserve moved by 15 s and not by 5. Named by id: "how many
    /// split" is a fact about WHICH movements they are.
    func testTheSplitMovesAreTheFourThePoolNames() {
        var seen: Set<String> = []
        var worstInOneComposition = 0
        for session in 1...Warmup.compositionCount {
            let split = Warmup.moves(sessionNumber: session).filter(\.isSplit)
            seen.formUnion(split.map(\.id))
            worstInOneComposition = max(worstInOneComposition, split.count)
        }
        XCTAssertEqual(seen, ["single-leg-rdl", "bird-dog", "arm-circles", "hip-circles"])
        XCTAssertEqual(worstInOneComposition, 3,
                       "the permanent circles plus the window of three, and three pauses")
    }

    /// Nine in the pool, six on screen, and every rotating move gets its turn
    /// — a movement that never appears is a movement that is not in the app.
    func testEveryMoveInThePoolIsReachable() {
        var seen: Set<String> = []
        for session in 1...Warmup.compositionCount {
            let moves = Warmup.moves(sessionNumber: session)
            XCTAssertEqual(moves.count, Warmup.moveCount, "session \(session)")
            XCTAssertEqual(Set(moves.map(\.id)).count, moves.count,
                           "session \(session): no move twice")
            seen.formUnion(moves.map(\.id))
        }
        XCTAssertEqual(seen.count, 9, "all nine moves of the pool are reachable")
        XCTAssertTrue(seen.isSuperset(of: ["y-t-w", "bird-dog", "single-leg-rdl"]),
                      "the three §40.1 sent here are in the block")
    }

    /// The transition doubled; the supplement did not.
    func testTheTransitionIsTenSecondsAndTheSupplementIsFive() {
        XCTAssertEqual(GetReady.seconds, 10)
        XCTAssertEqual(GetReady.setupSupplementSec, 5)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: false), 10)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: true), 15)
    }

    /// The side-switch pause did NOT follow the transition to ten. It is a
    /// pause inside one position, not travel to another, and its own arithmetic
    /// counts it as five.
    func testTheSideSwitchPauseStayedAtFive() {
        XCTAssertEqual(Cooldown.sideSwitchPauseSec, 5)
        // And the warm-up reads that same constant rather than owning a second
        // one (§41.12): it is the same gesture in both blocks, and two
        // constants for it would part company the first time either moved.
        XCTAssertEqual(Warmup.switchPauseSeconds, Cooldown.sideSwitchPauseSec)
        XCTAssertEqual(Warmup.halfSeconds, Warmup.moveSeconds / 2)
        XCTAssertEqual(Warmup.halfSeconds, Cooldown.sideSeconds,
                       "both blocks split a 30 s slot the same way")
    }
}
