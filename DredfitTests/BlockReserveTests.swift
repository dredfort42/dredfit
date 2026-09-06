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
//  found by ENUMERATING the sets a session can actually produce rather than by
//  assuming which six positions are dearest: if the pool, the mapping or a hold
//  ever moves, this fails here instead of on somebody's stopwatch.
//
//  And it enumerates the axis the APP has. Finding 49 gave both composers a
//  `hiding:` set and left `Warmup.moves(sessionNumber:)` /
//  `Cooldown.positions(performed:)` for the tests alone — which walked exactly
//  those, so the reserve was measured on compositions the app can no longer
//  draw. A move set aside widens the rotation's window, and the widened window
//  draws a fourth split move: the shipped worst warm-up is 265 s where the
//  no-hiding walk found 260, and the pair is 560 s where this file asserted 555
//  (review 06.09.2026). Nothing overran — but the gate whose whole job is to
//  make the next second an engine change was blind to the axis that spends
//  seconds.
//
//  The last section reads the same composition rule the other way: where a
//  block that is RUNNING picks up when the athlete changes the composition
//  under it. That landing shipped as a clamp of the ordinal and with no test at
//  all, and it reopened moves already done.
//

import SwiftUI
import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class BlockReserveTests: XCTestCase {

    // MARK: - What one slot costs

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

    // MARK: - The pools, and what can be set aside

    /// The nine ids of the warm-up pool, read off the compositions rather than
    /// typed here: `Warmup.pool` is private, and a hand-written copy would stop
    /// covering the pool the day a move is added to it.
    private var warmupPoolIDs: [String] {
        var ids: [String] = []
        for session in 1...Warmup.compositionCount {
            for move in Warmup.moves(sessionNumber: session) where !ids.contains(move.id) {
                ids.append(move.id)
            }
        }
        return ids
    }

    /// The nine positions of the cool-down pool, likewise — one movement at a
    /// time, because a single pattern draws the two fixed positions, its own
    /// and two top-ups, so the union over the ten reaches every one.
    private var cooldownPool: [CooldownPosition] {
        var pool: [CooldownPosition] = []
        for pattern in Pattern.allCases {
            for position in Cooldown.positions(performed: [pattern])
            where !pool.contains(where: { $0.id == position.id }) {
                pool.append(position)
            }
        }
        return pool
    }

    /// Every set the athlete can actually put in `hiddenBlockMoveIDs`. The cap
    /// is the app's, not a number chosen here — 130 subsets of nine.
    private func hiddenSets(of ids: [String]) -> [Set<String>] {
        (0...AppStore.maxHiddenBlockMoves).flatMap { subsets(of: ids, sized: $0) }
    }

    private func subsets(of ids: [String], sized size: Int) -> [Set<String>] {
        guard size > 0 else { return [Set<String>()] }
        guard ids.count >= size else { return [] }
        var out: [Set<String>] = []
        for (offset, id) in ids.enumerated() {
            for rest in subsets(of: Array(ids[(offset + 1)...]), sized: size - 1) {
                out.append(rest.union([id]))
            }
        }
        return out
    }

    // MARK: - The warm-up

    private func warmupSec(session: Int, hiding hidden: Set<String>) -> Int {
        Warmup.moves(sessionNumber: session, hiding: hidden).map(cost).reduce(0, +)
    }

    /// The dearest warm-up a session can draw with `hidden` set aside. The block
    /// composes six moves out of nine (§40.1), so "what the warm-up costs" is a
    /// claim about EVERY composition — and since §41.12 they no longer all cost
    /// the same: four moves of the pool have a halfway boundary, the rotation's
    /// window draws some of them on top of the permanent arm circles, and each
    /// pays a switch pause.
    private func worstWarmupSec(hiding hidden: Set<String>) -> Int {
        (1...Warmup.compositionCount).map { warmupSec(session: $0, hiding: hidden) }.max() ?? 0
    }

    /// …over every set the athlete can set aside: 130 subsets against six
    /// sessions. Small, and it is the whole shipped space — this is the number
    /// the reserve has to hold.
    private func worstWarmupSec() -> Int {
        hiddenSets(of: warmupPoolIDs).map { worstWarmupSec(hiding: $0) }.max() ?? 0
    }

    // MARK: - The cool-down

    /// The dearest six the pool holds — a CEILING, and a tight one.
    ///
    /// Every composition is exactly six DISTINCT positions of the nine whatever
    /// is set aside (`testEveryCompositionIsSixOfThePool` pins that), so nothing
    /// the composer can draw costs more than the six dearest; and
    /// `reachableCooldownSec()` shows a real session reaching it, which is what
    /// makes this the worst case and not merely a bound.
    ///
    /// A ceiling rather than a cross product for cost alone: the cool-down's
    /// other input is the workout, and 130 hidden sets against 1024 movement
    /// subsets in two orders is a quarter of a million compositions in a test
    /// that used to build 126. The warm-up, whose only other input is the
    /// session number, is still enumerated outright above.
    private func worstCooldownSec() -> Int {
        cooldownPool.map(cost).sorted(by: >).prefix(Cooldown.positionCount).reduce(0, +)
    }

    /// What a session can actually draw with nothing set aside — every subset of
    /// the movements, in both orders, because the composition maps `performed`
    /// in order and tops up from the pool, so order is part of the input.
    private func reachableCooldownSec() -> Int {
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

    /// The inputs the six-of-the-pool check walks: one movement (the maximum
    /// top-up, where the fixed frame and the pool order do all the work), and
    /// the whole session in both orders (the minimum). The cost of the block is
    /// pinned by the ceiling above; what these have to show is that the
    /// composer still fills six slots however much is set aside.
    private var cooldownInputs: [[Pattern]] {
        Pattern.allCases.map { [$0] } + [Pattern.allCases, Array(Pattern.allCases.reversed())]
    }

    // MARK: - The reserve

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
    /// 10:00 fits with 40 s to spare, and equality became unreachable. An
    /// unreachable assert gets deleted, and then nothing watches the two numbers
    /// at all — so what is pinned is the property that IS still exact: the
    /// reserve is the SMALLEST whole minute that fits. Drift in either direction
    /// breaks it, and a whole minute of slack would mean the engine is holding a
    /// minute the blocks no longer need.
    ///
    /// 555 → 560 (review 06.09.2026): the 555 was measured on the no-hiding
    /// overloads, and the app stopped calling those when finding 49 landed.
    func testTheReserveIsTheSmallestWholeMinuteThatFits() {
        let reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        let worst = worstWarmupSec() + worstCooldownSec()
        XCTAssertEqual(worst, 560, "the worst pair the app can compose is 265 + 295")
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
    /// Derived from the same composition the reserve above is, and over the same
    /// hiding axis: the offer screen reads `warmupMoves`, which is the hidden set
    /// applied, so a promise checked without it is a promise checked on another
    /// block.
    func testTheWarmupOfferNeverPromisesLessThanTheBlockTakes() {
        for hidden in hiddenSets(of: warmupPoolIDs) {
            for session in 1...Warmup.compositionCount {
                let moves = Warmup.moves(sessionNumber: session, hiding: hidden)
                let announced = Warmup.introMinutes(moves)
                let actual = moves.map(cost).reduce(0, +)
                let named = "session \(session), set aside \(hidden.sorted())"
                XCTAssertGreaterThanOrEqual(
                    announced * 60, actual,
                    "\(named): the offer promises \(announced) min "
                    + "for a block that takes \(actual) s")
                // And not absurdly more: rounding up one minute, never two.
                XCTAssertLessThan(announced * 60, actual + 60,
                                  "\(named): the offer overstates the block by a minute")
            }
        }
    }

    func testEachBlockCostsWhatTheSpecSays() {
        // EVERY composition, not just one. With nothing set aside a composition
        // costs the 245 s of §37.7a plus one switch pause per SPLIT move it
        // draws (§41.12) — written as arithmetic over the composition rather
        // than as a table of six numbers, because a table says nothing about WHY
        // they differ.
        for session in 1...Warmup.compositionCount {
            let split = Warmup.moves(sessionNumber: session).filter(\.isSplit).count
            XCTAssertEqual(warmupSec(session: session, hiding: []),
                           245 + split * Cooldown.sideSwitchPauseSec,
                           "§41.12: composition \(session) draws \(split) split moves")
            XCTAssertGreaterThanOrEqual(split, 2,
                                        "arm circles are permanent and cat-cow is not split, "
                                        + "so every composition pays at least the circles")
        }
        // Once a move can be set aside the 245 splits in two: 240 for six slots
        // and their transitions, and the 5 s trip down to the floor only when
        // the composition HAS a floor move — three of the nine are on the floor,
        // and hiding all three is inside the cap.
        for hidden in hiddenSets(of: warmupPoolIDs) {
            for session in 1...Warmup.compositionCount {
                let moves = Warmup.moves(sessionNumber: session, hiding: hidden)
                let split = moves.filter(\.isSplit).count
                let setup = moves.filter(\.needsSetup).count
                let named = "session \(session), set aside \(hidden.sorted())"
                XCTAssertEqual(setup, moves.contains(where: \.onFloor) ? 1 : 0,
                               "\(named): only the FIRST floor move pays the supplement")
                XCTAssertEqual(warmupSec(session: session, hiding: hidden),
                               240 + setup * GetReady.setupSupplementSec
                                   + split * Cooldown.sideSwitchPauseSec,
                               "\(named): \(split) split moves, \(setup) trip to the floor")
            }
        }
        XCTAssertEqual(worstWarmupSec(hiding: []), 260,
                       "§41.12: with nothing set aside the dearest warm-up is 260 s")
        XCTAssertEqual(worstWarmupSec(), 265,
                       "the dearest warm-up the APP can compose is 265 s — a set-aside move "
                       + "widens the rotation's window onto a fourth split move")
        XCTAssertEqual(worstCooldownSec(), 295, "§37.7a: the worst cool-down is 295 s")
        XCTAssertEqual(reachableCooldownSec(), worstCooldownSec(),
                       "a real session reaches the dearest six of the pool, so the ceiling "
                       + "the reserve is measured against is the worst case and not a bound")
    }

    /// Four of the nine, and the rotation's own window can hold three — which is
    /// why the reserve moved by 15 s and not by 5. Named by id: "how many split"
    /// is a fact about WHICH movements they are.
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
        // A set-aside move widens that window, and a widened window draws all
        // FOUR. This is where the 265 s worst case comes from, and it is the
        // whole reason the reserve is measured on the hiding axis.
        let widest = hiddenSets(of: warmupPoolIDs).flatMap { hidden in
            (1...Warmup.compositionCount).map {
                Warmup.moves(sessionNumber: $0, hiding: hidden).filter(\.isSplit).count
            }
        }.max()
        XCTAssertEqual(widest, 4, "with a move set aside a composition draws every split move")
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

    /// Six on screen whatever is set aside — the `Warmup.honoured` guarantee.
    /// A block of five would still fit the reserve and still be wrong, and a
    /// block of none indexes out of bounds on its first screen, which is why
    /// this is asserted rather than left to the composer's arithmetic.
    func testTheWarmupIsSixMovesWhateverIsSetAside() {
        let pool = warmupPoolIDs
        for hidden in hiddenSets(of: pool) {
            for session in 1...Warmup.compositionCount {
                let moves = Warmup.moves(sessionNumber: session, hiding: hidden)
                let named = "session \(session), set aside \(hidden.sorted())"
                XCTAssertEqual(moves.count, Warmup.moveCount, named)
                XCTAssertEqual(Set(moves.map(\.id)).count, moves.count, "\(named): no move twice")
                XCTAssertTrue(moves.allSatisfy { !hidden.contains($0.id) },
                              "\(named): a set-aside move came back")
            }
        }
        // More than the block can afford: a state file from another build, an
        // imported backup or a future cap. `honoured` is where that is survived,
        // so it is asserted and not assumed — and what it must never do is
        // shorten the block.
        for session in 1...Warmup.compositionCount {
            XCTAssertEqual(Warmup.moves(sessionNumber: session, hiding: Set(pool)).count,
                           Warmup.moveCount,
                           "session \(session) with the whole pool set aside")
        }
    }

    /// The claim `worstCooldownSec()` rests on: whatever is set aside, the block
    /// is six distinct positions OF THE POOL, so the dearest six of the pool is
    /// a ceiling on what it can cost.
    func testEveryCompositionIsSixOfThePool() {
        let pool = cooldownPool
        let ids = pool.map(\.id)
        XCTAssertEqual(ids.count, 9, "nine in the cool-down pool")
        for hidden in hiddenSets(of: ids) {
            for performed in cooldownInputs {
                let composed = Cooldown.positions(performed: performed, hiding: hidden)
                let named = "\(performed.count) movements, set aside \(hidden.sorted())"
                XCTAssertEqual(composed.count, Cooldown.positionCount, named)
                XCTAssertEqual(Set(composed.map(\.id)).count, composed.count,
                               "\(named): no position twice")
                XCTAssertTrue(Set(ids).isSuperset(of: composed.map(\.id)),
                              "\(named): a position from outside the pool")
                XCTAssertTrue(composed.allSatisfy { !hidden.contains($0.id) },
                              "\(named): a set-aside position came back")
            }
        }
        // The same overflow the warm-up survives, for the same reason.
        XCTAssertEqual(Cooldown.positions(performed: Pattern.allCases, hiding: Set(ids)).count,
                       Cooldown.positionCount,
                       "the whole pool set aside still composes a block")
    }

    // MARK: - Where a recomposed block picks up (review 06.09.2026)
    //
    // The same composition rule read the other way. A block running when the
    // athlete sets a move aside has to land somewhere in the list that comes
    // back, and `WorkoutFlowView.rebaseLanding` is the rule both blocks use.
    // It shipped as a clamp of the ordinal with no test of any kind — the two
    // scenarios below are the ones that clamp got wrong.

    /// Session 4 runs [marching, arm circles, single-leg RDL, cat-cow, bird dog,
    /// Y-T-W]. Setting bird dog aside on slot 5 does not delete a slot: the
    /// rotation re-derives, torso rotations arrives at slot 3 and cat-cow slides
    /// to 5. Clamping the ordinal therefore closed the sheet onto a transition
    /// for cat-cow — a move finished a minute earlier — and torso rotations,
    /// which nobody had seen, was never run.
    func testHidingTheMoveOnScreenNeverReopensOneAlreadyDone() throws {
        let before = Warmup.moves(sessionNumber: 4).map(\.id)
        XCTAssertEqual(before, ["marching", "arm-circles", "single-leg-rdl",
                                "cat-cow", "bird-dog", "y-t-w"],
                       "the composition this was measured on")
        let after = Warmup.moves(sessionNumber: 4, hiding: ["bird-dog"]).map(\.id)
        // The passed set is the prefix of the list that WAS running: slots 0…3,
        // the athlete standing on slot 4.
        let passed = Set(before.prefix(4))
        XCTAssertTrue(passed.contains(after[4]),
                      "the ordinal the clamp kept names a move already done")
        let landing = try XCTUnwrap(WorkoutFlowView.rebaseLanding(in: after, after: passed))
        XCTAssertEqual(after[landing], "y-t-w")
        XCTAssertFalse(passed.contains(after[landing]), "the block reopened a finished move")
    }

    /// The cool-down's twin, and the one the athlete cannot even see coming:
    /// "Bring back" does not dismiss the technique sheet. A cool-down composed
    /// with the wall stretch set aside is [hip flexors, forward fold, lat, wrists,
    /// lying twist, rest pose]; restoring it on slot 5 re-inserts into the
    /// opening and pushes everything after it one slot right, so the clamped
    /// ordinal named the wrists — already done.
    func testBringingAPositionBackNeverReopensOneAlreadyDone() throws {
        let performed: [Pattern] = [.squat, .pull, .pushH, .coreRot]
        let before = Cooldown.positions(performed: performed, hiding: ["chest-wall"]).map(\.id)
        XCTAssertEqual(before, ["hip-flexors", "forward-fold", "lat-stretch",
                                "wrists", "lying-twist", "rest-pose"])
        let after = Cooldown.positions(performed: performed, hiding: []).map(\.id)
        let passed = Set(before.prefix(4))
        XCTAssertTrue(passed.contains(after[4]),
                      "the ordinal the clamp kept names a position already done")
        let landing = try XCTUnwrap(WorkoutFlowView.rebaseLanding(in: after, after: passed))
        XCTAssertEqual(after[landing], "rest-pose")
        XCTAssertFalse(passed.contains(after[landing]), "the block reopened a finished stretch")
    }

    /// The rule itself, at its three ends. Forward-only is the invariant: a
    /// landing behind the athlete would be replayed slot by slot by the ordinal
    /// machine that advances from it, and a block whose every slot is behind
    /// them is over rather than repeated.
    func testTheLandingIsForwardOnlyAndEndsTheBlockWhenNothingIsLeft() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(WorkoutFlowView.rebaseLanding(in: ids, after: []), 0,
                       "nothing behind the athlete: the block opens where it is")
        XCTAssertEqual(WorkoutFlowView.rebaseLanding(in: ids, after: ["a"]), 1)
        // Measured from the LAST id behind them, not from the first one that is
        // not: "b" sits between two passed slots, and landing on it would put
        // the ordinal machine back through "c".
        XCTAssertNil(WorkoutFlowView.rebaseLanding(in: ids, after: ["a", "c"]),
                     "every slot is behind the athlete: the block is over")
        XCTAssertEqual(WorkoutFlowView.rebaseLanding(in: ids, after: ["x"]), 0,
                       "a set-aside id that is not in the list moves nothing")
        XCTAssertNil(WorkoutFlowView.rebaseLanding(in: [], after: []))
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
