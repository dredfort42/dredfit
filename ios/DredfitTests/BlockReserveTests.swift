//
//  The warm-up and cool-down reserve, and the arithmetic
//  that makes the transition length an ENGINE constraint rather than an app
//  preference.
//
//  `warmupMin + cooldownMin` is the whole budget the engine sets aside for the
//  two blocks. The worst pair leaves 100 s of it over (500 of 600), and every
//  second added to the transition costs twelve — six transitions per block —
//  so past 16 s the reserve breaks, which is a change to the engine.
//
//  SHORTENING it is the direction that does not break. The worst pair is 500 s
//  against 600, so the reserve is not the smallest whole minute that fits —
//  nine would hold it. The owner keeps ten rather than spend an engine change
//  and a minute off every announced duration to reclaim slack nobody is short
//  of. What is asserted below is therefore a floor and a ceiling, not an
//  equality: the blocks may never overrun the reserve, and the reserve may
//  never hold two spare minutes.
//
//  Everything below is computed from the app's own constants and from the real
//  composition rule, never from the spec's numbers restated. The worst case is
//  found by ENUMERATING the sets a session can actually produce rather than by
//  assuming which six positions are dearest: if the pool, the mapping or a hold
//  ever moves, this fails here instead of on somebody's stopwatch.
//
//  And it enumerates the axis the APP has: both composers take a `hiding:`
//  set, and `Warmup.moves(sessionNumber:opening:)` /
//  `Cooldown.positions(performed:)` — the forms without it — are for the tests
//  alone. The standing warm-up costs the same whatever is set aside (every
//  slot is a transition and thirty seconds), but that is exactly the kind of
//  claim the sweep exists to keep true: a set-aside move changes which moves
//  a session draws, and a claim measured without the hiding axis is measured
//  on compositions the app does not draw.
//
//  The last section reads the same composition rule the other way: where a
//  block that is RUNNING picks up when the athlete changes the composition
//  under it — forward, never reopening a move already done.
//

import SwiftUI
import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class BlockReserveTests: XCTestCase {

    // MARK: - What one slot costs

    /// One warm-up move: every stage the block's own machine walks it through,
    /// transition included. Walked rather than written as "transition plus
    /// thirty", so a circle that got its switch pause back — one line in
    /// `GuidedBlock.step` — costs four more seconds here and the reserve
    /// asserts below go red, instead of staying green on a formula that no
    /// longer describes the block. GetReadyTests keeps the hand-written
    /// statement on purpose; two derivations that agree are the point.
    private func cost(_ move: WarmupMove) -> Int {
        var step: (index: Int, stage: GuidedStage)? = (0, .getReady)
        var seconds = 0
        while let current = step {
            seconds += GuidedBlock.warmup.stageSeconds(current.stage, of: move)
            step = GuidedBlock.step(after: current, positions: [move])
        }
        return seconds
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

    /// One opening per distinct lead-in, and none. The composition reads the
    /// opening only through `Warmup.leadIn(for:)`, so this is every opening
    /// there is — derived from the mapping rather than typed, so a pattern
    /// that gains a lead-in of its own joins the sweep by itself.
    private var openings: [Pattern?] {
        var seen: Set<String> = []
        return [nil] + Pattern.allCases.filter { seen.insert(Warmup.leadIn(for: $0)).inserted }
    }

    /// The fourteen ids of the warm-up pool, read off the compositions rather
    /// than typed here: `Warmup.pool` is private, and a hand-written copy would
    /// stop covering the pool the day a move is added to it.
    private var warmupPoolIDs: [String] {
        var ids: [String] = []
        for session in 1...Warmup.rotationPeriod {
            for opening in openings {
                for move in Warmup.moves(sessionNumber: session, opening: opening)
                where !ids.contains(move.id) {
                    ids.append(move.id)
                }
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
    /// is the app's, not a number chosen here — 470 subsets of fourteen.
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

    private func warmupSec(session: Int, opening: Pattern?, hiding hidden: Set<String>) -> Int {
        Warmup.moves(sessionNumber: session, opening: opening, hiding: hidden)
            .map(cost).reduce(0, +)
    }

    /// The dearest warm-up a session can draw with `hidden` set aside: every
    /// session of the rotation against every opening. "What the warm-up
    /// costs" is a claim about EVERY composition, even now that each one is
    /// six equal slots — that equality is what this keeps true.
    private func worstWarmupSec(hiding hidden: Set<String>) -> Int {
        (1...Warmup.rotationPeriod).flatMap { session in
            openings.map { warmupSec(session: session, opening: $0, hiding: hidden) }
        }.max() ?? 0
    }

    /// …over every set the athlete can set aside: the whole shipped space, and
    /// the number the reserve has to hold.
    private func worstWarmupSec() -> Int {
        hiddenSets(of: warmupPoolIDs).map { worstWarmupSec(hiding: $0) }.max() ?? 0
    }

    /// Every composition the app can draw — each set the athlete can set
    /// aside, against every session of the rotation and every opening — with
    /// a name that says which, for the failure message.
    private func forEveryComposition(_ check: (_ moves: [WarmupMove], _ hidden: Set<String>,
                                               _ named: String) -> Void) {
        for hidden in hiddenSets(of: warmupPoolIDs) {
            for session in 1...Warmup.rotationPeriod {
                for opening in openings {
                    let moves = Warmup.moves(sessionNumber: session, opening: opening, hiding: hidden)
                    check(moves, hidden, "session \(session), opening \(opening?.rawValue ?? "none"), "
                          + "set aside \(hidden.sorted())")
                }
            }
        }
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
    /// subsets in two orders is a quarter of a million compositions. The
    /// warm-up, whose only other input is the session number, is enumerated
    /// outright above.
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
        XCTAssertEqual(reserve, 600, "the reserve is 10:00")
        XCTAssertLessThanOrEqual(
            worstWarmupSec() + worstCooldownSec(), reserve,
            "the worst composition of the two blocks overruns the engine's reserve")
    }

    /// A reserve is whole minutes and the blocks are not, so there is no
    /// equality to pin — and with no assert here nothing would watch the two
    /// numbers at all. What is pinned is what the reserve still HAS to be.
    ///
    /// Nine minutes would hold the worst pair. **The owner keeps ten**: giving
    /// the minute back is an engine change — `cooldownMin` 4 → 3 through the
    /// whole reference chain — and it would take a minute off every announced
    /// duration, off the onboarding line and off the store listing, to buy
    /// slack nobody is short of.
    ///
    /// So two properties, and the names say which is which. The floor is
    /// safety and is not negotiable: the blocks must never overrun what the
    /// engine reserves. The ceiling is drift: one spare minute is a decision,
    /// two would mean the reserve had quietly stopped being about the blocks.
    func testTheReserveHoldsTheBlocksWithOneSpareMinuteAtMost() {
        let reserve = (EngineConfig.warmupMin + EngineConfig.cooldownMin) * 60
        let worst = worstWarmupSec() + worstCooldownSec()
        XCTAssertEqual(worst, 500, "the worst pair the app can compose is 228 + 272")
        XCTAssertGreaterThanOrEqual(reserve - worst, 0,
                                    "the blocks overrun what the engine reserves")
        XCTAssertLessThan(reserve - worst, 120,
                          "two whole minutes of slack: the reserve is no longer "
                          + "sized against the blocks it exists for")
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
        forEveryComposition { moves, _, named in
            let announced = Warmup.introMinutes(moves)
            let actual = moves.map(cost).reduce(0, +)
            XCTAssertGreaterThanOrEqual(
                announced * 60, actual,
                "\(named): the offer promises \(announced) min "
                + "for a block that takes \(actual) s")
            // And not absurdly more: rounding up one minute, never two.
            XCTAssertLessThan(announced * 60, actual + 60,
                              "\(named): the offer overstates the block by a minute")
        }
    }

    /// Six slots, each a transition plus the move itself — the whole of a
    /// warm-up before any supplement or switch pause is added.
    private var slotsSec: Int {
        Warmup.moveCount * (GetReady.seconds + Warmup.moveSeconds)
    }

    func testEachBlockCostsWhatTheSpecSays() {
        // EVERY composition, and written as arithmetic over the composition
        // rather than as a literal total, because a total hides the transition
        // length inside it, and changing the transition would break asserts
        // that are only ever about the composition. The slot cost belongs to
        // `GetReady`, and the test asks it.
        //
        // Six equal slots, whatever is set aside and whatever the session opens
        // on: no move pays the trip to the floor, and no circle pays a pause.
        forEveryComposition { moves, _, named in
            XCTAssertEqual(moves.filter(\.needsSetup).count, 0,
                           "\(named): a standing block pays no supplement")
            XCTAssertEqual(moves.map(cost).reduce(0, +), slotsSec, named)
        }
        XCTAssertEqual(worstWarmupSec(hiding: []), 228,
                       "with nothing set aside the warm-up is 228 s")
        XCTAssertEqual(worstWarmupSec(), 228,
                       "and with anything set aside, the same 228 s")
        XCTAssertEqual(worstCooldownSec(), 272, "the worst cool-down the app can compose is 272 s")
        // The dearest six of the pool is the BOUND the reserve is measured
        // against, and a real session reaches it exactly — which is what makes
        // it the worst case and not merely a bound.
        XCTAssertEqual(reachableCooldownSec(), 272,
                       "the dearest cool-down a real session reaches")
        XCTAssertLessThanOrEqual(reachableCooldownSec(), worstCooldownSec(),
                                 "a real session cannot beat the ceiling the reserve "
                                 + "is measured against")
    }

    /// The period the sweeps walk, pinned: a loop bound nothing pins is a loop
    /// that can quietly stop covering the compositions it claims to — any
    /// value of four or more kept every other assertion here green. Twenty is
    /// the least common multiple of the groups (1, 2, 5 and 4), and the
    /// rotation really does come round after it, for every opening.
    func testTheRotationComesRoundAfterTwentySessions() {
        XCTAssertEqual(Warmup.rotationPeriod, 20)
        for session in 1...Warmup.rotationPeriod {
            for opening in openings {
                XCTAssertEqual(
                    Warmup.moves(sessionNumber: session, opening: opening).map(\.id),
                    Warmup.moves(sessionNumber: session + Warmup.rotationPeriod,
                                 opening: opening).map(\.id),
                    "session \(session), opening \(opening?.rawValue ?? "none")")
            }
        }
        let distinct = Set((1...Warmup.rotationPeriod).map {
            Warmup.moves(sessionNumber: $0, opening: nil).map(\.id)
        })
        XCTAssertEqual(distinct.count, Warmup.rotationPeriod,
                       "no shorter period: every session of the twenty composes its own block")
    }

    /// Fourteen in the pool, six on screen, and every move gets its turn — a
    /// movement that never appears is a movement that is not in the app. The
    /// two lead-in-only moves appear only through the opening that calls for
    /// them, which is why the sweep walks the openings too.
    func testEveryMoveInThePoolIsReachable() {
        var seen: Set<String> = []
        for session in 1...Warmup.rotationPeriod {
            for opening in openings {
                let moves = Warmup.moves(sessionNumber: session, opening: opening)
                XCTAssertEqual(moves.count, Warmup.moveCount, "session \(session)")
                XCTAssertEqual(Set(moves.map(\.id)).count, moves.count,
                               "session \(session): no move twice")
                seen.formUnion(moves.map(\.id))
            }
        }
        XCTAssertEqual(seen.count, 14, "all fourteen moves of the pool are reachable")
    }

    /// The block's one specific part: the last move prepares the first
    /// exercise. Every pattern lands on a move of the pool, the four that open
    /// a session today on the move their own work calls for, and a lead-in set
    /// aside gives its slot back to the rotation rather than shortening the
    /// block.
    func testTheLastMoveLeadsIntoTheFirstExercise() {
        let pool = Set(warmupPoolIDs)
        for pattern in Pattern.allCases {
            XCTAssertTrue(pool.contains(Warmup.leadIn(for: pattern)), "\(pattern): no such move")
            for session in 1...Warmup.rotationPeriod {
                XCTAssertEqual(Warmup.moves(sessionNumber: session, opening: pattern).last?.id,
                               Warmup.leadIn(for: pattern), "session \(session), \(pattern)")
            }
        }
        XCTAssertEqual(Warmup.leadIn(for: .squat), "half-squats")
        XCTAssertEqual(Warmup.leadIn(for: .hinge), "hip-hinges")
        XCTAssertEqual(Warmup.leadIn(for: .pushH), "arm-swings")
        XCTAssertEqual(Warmup.leadIn(for: .pull), "reach-and-pull")
        let without = Warmup.moves(sessionNumber: 1, opening: .squat, hiding: ["half-squats"])
        XCTAssertEqual(without.count, Warmup.moveCount)
        XCTAssertFalse(without.map(\.id).contains("half-squats"))
    }

    /// The reason the slots draw from GROUPS: every composition raises the
    /// pulse, moves the shoulders and moves the trunk, unless the athlete has
    /// set aside every move a group has. A single window over one list kept
    /// that only while the list's order was intact, and a set-aside move broke
    /// the order.
    func testEveryGroupIsDrawnUnlessAllOfItIsSetAside() {
        let groups: [(name: String, ids: Set<String>)] = [
            ("raise", ["marching", "side-steps", "heels-to-glutes"]),
            ("upper", ["arm-circles", "arm-swings", "reach-and-pull", "wrist-circles",
                       "overhead-reaches"]),
            ("trunk", ["torso-rotations", "side-bends", "hip-circles", "standing-cat-cow"]),
        ]
        forEveryComposition { moves, hidden, named in
            let ids = Set(moves.map(\.id))
            for group in groups where !group.ids.isSubset(of: hidden) {
                XCTAssertFalse(ids.isDisjoint(with: group.ids), "\(named): no \(group.name) move")
            }
        }
    }

    /// Six on screen whatever is set aside — the `Warmup.honoured` guarantee.
    /// A block of five would still fit the reserve and still be wrong, and a
    /// block of none indexes out of bounds on its first screen, which is why
    /// this is asserted rather than left to the composer's arithmetic.
    func testTheWarmupIsSixMovesWhateverIsSetAside() {
        forEveryComposition { moves, hidden, named in
            XCTAssertEqual(moves.count, Warmup.moveCount, named)
            XCTAssertEqual(Set(moves.map(\.id)).count, moves.count, "\(named): no move twice")
            XCTAssertTrue(moves.allSatisfy { !hidden.contains($0.id) },
                          "\(named): a set-aside move came back")
        }
        // More than the block can afford: a state file from another build, an
        // imported backup or a future cap. `honoured` is where that is survived,
        // so it is asserted and not assumed — and what it must never do is
        // shorten the block.
        let pool = Set(warmupPoolIDs)
        for session in 1...Warmup.rotationPeriod {
            for opening in openings {
                XCTAssertEqual(Warmup.moves(sessionNumber: session, opening: opening,
                                            hiding: pool).count,
                               Warmup.moveCount,
                               "session \(session) with the whole pool set aside")
            }
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

    // MARK: - Where a recomposed block picks up
    //
    // The same composition rule read the other way. A block running when the
    // athlete sets a move aside has to land somewhere in the list that comes
    // back, and `WorkoutSession.rebaseLanding` is the rule both blocks use.
    // The two scenarios below are the ones a clamp of the ordinal gets wrong.

    /// Session 4, opening on a squat, runs [marching, heels to glutes, wrist
    /// circles, overhead reaches, standing cat-cow, half squats]. Setting
    /// overhead reaches aside on slot 3 does not delete a slot: the shoulders'
    /// rotation passes its turn on to arm circles, which the pool lists FIRST,
    /// so arm circles arrive at slot 2 and wrist circles slide to 3. Clamping
    /// the ordinal would therefore close the sheet onto a transition for wrist
    /// circles — a move finished a minute earlier.
    func testHidingTheMoveOnScreenNeverReopensOneAlreadyDone() throws {
        let before = Warmup.moves(sessionNumber: 4, opening: .squat).map(\.id)
        XCTAssertEqual(before, ["marching", "heels-to-glutes", "wrist-circles",
                                "overhead-reaches", "standing-cat-cow", "half-squats"],
                       "the composition this was measured on")
        let after = Warmup.moves(sessionNumber: 4, opening: .squat,
                                 hiding: ["overhead-reaches"]).map(\.id)
        // The passed set is the prefix of the list that WAS running: slots 0…2,
        // the athlete standing on slot 3.
        let passed = Set(before.prefix(3))
        XCTAssertTrue(passed.contains(after[3]),
                      "the ordinal the clamp kept names a move already done")
        let landing = try XCTUnwrap(WorkoutSession.rebaseLanding(in: after, after: passed))
        XCTAssertEqual(after[landing], "standing-cat-cow")
        XCTAssertFalse(passed.contains(after[landing]), "the block reopened a finished move")
    }

    /// The cool-down's twin, and the one the athlete cannot even see coming:
    /// "Bring back" does not dismiss the technique sheet. A cool-down composed
    /// with the wall stretch set aside is [hip flexors, forward fold, lat, wrists,
    /// lying twist, rest pose]; restoring it on slot 5 re-inserts into the
    /// opening and pushes everything after it one slot right, so a clamped
    /// ordinal would name the wrists — already done.
    func testBringingAPositionBackNeverReopensOneAlreadyDone() throws {
        let performed: [Pattern] = [.squat, .pull, .pushH, .coreRot]
        let before = Cooldown.positions(performed: performed, hiding: ["chest-wall"]).map(\.id)
        XCTAssertEqual(before, ["hip-flexors", "forward-fold", "lat-stretch",
                                "wrists", "lying-twist", "rest-pose"])
        let after = Cooldown.positions(performed: performed, hiding: []).map(\.id)
        let passed = Set(before.prefix(4))
        XCTAssertTrue(passed.contains(after[4]),
                      "the ordinal the clamp kept names a position already done")
        let landing = try XCTUnwrap(WorkoutSession.rebaseLanding(in: after, after: passed))
        XCTAssertEqual(after[landing], "rest-pose")
        XCTAssertFalse(passed.contains(after[landing]), "the block reopened a finished stretch")
    }

    /// The rule itself, at its three ends. Forward-only is the invariant: a
    /// landing behind the athlete would be replayed slot by slot by the ordinal
    /// machine that advances from it, and a block whose every slot is behind
    /// them is over rather than repeated.
    func testTheLandingIsForwardOnlyAndEndsTheBlockWhenNothingIsLeft() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(WorkoutSession.rebaseLanding(in: ids, after: []), 0,
                       "nothing behind the athlete: the block opens where it is")
        XCTAssertEqual(WorkoutSession.rebaseLanding(in: ids, after: ["a"]), 1)
        // Measured from the LAST id behind them, not from the first one that is
        // not: "b" sits between two passed slots, and landing on it would put
        // the ordinal machine back through "c".
        XCTAssertNil(WorkoutSession.rebaseLanding(in: ids, after: ["a", "c"]),
                     "every slot is behind the athlete: the block is over")
        XCTAssertEqual(WorkoutSession.rebaseLanding(in: ids, after: ["x"]), 0,
                       "a set-aside id that is not in the list moves nothing")
        XCTAssertNil(WorkoutSession.rebaseLanding(in: [], after: []))
    }

    /// Pinned by value on purpose: these two numbers are spent against a reserve
    /// the ENGINE owns, so neither may drift without the arithmetic above being
    /// re-read.
    func testTheTransitionIsEightSecondsAndTheSupplementIsFour() {
        XCTAssertEqual(GetReady.seconds, 8)
        XCTAssertEqual(GetReady.setupSupplementSec, 4)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: false), 8)
        XCTAssertEqual(GetReady.stageSeconds(needsSetup: true), 12)
    }

    /// The side-switch pause does not follow the transition: it is a pause
    /// inside one position, not travel to another. Four seconds is on trial.
    /// Pinned by value so the revert is a red test and not a shrug: the pause
    /// is judged in use, and a number under trial has to be visible when it
    /// moves.
    func testTheSideSwitchPauseIsOnTrialAtFour() {
        XCTAssertEqual(Cooldown.sideSwitchPauseSec, 4)
        // The warm-up owns no pause of its own: its circles reverse on the
        // move, and a second constant for a gesture it does not make would
        // only wait for someone to wire it back in.
        XCTAssertEqual(GuidedBlock.warmup.stageSeconds(.switchPause, of: Warmup.moves(
            sessionNumber: 1, opening: .squat)[0]), Cooldown.sideSwitchPauseSec)
        XCTAssertEqual(Warmup.halfSeconds, Warmup.moveSeconds / 2)
        XCTAssertEqual(Warmup.halfSeconds, Cooldown.sideSeconds,
                       "both blocks split a 30 s slot the same way")
    }
}
