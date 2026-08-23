//
//  EngineV25Tests.swift
//  DredfitCoreTests
//
//  The safety wave: the per-pattern, per-tier growth ceiling and the
//  discomfort input that freezes a pattern. Mirrors the corresponding blocks
//  in the reference verifier — anything asserted here is asserted there too.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV25Tests: XCTestCase {

    /// A state where every pattern sits at the same level, so one session
    /// exercises six patterns at once.
    private func seeded(level: Int, counter: Int = 0) -> EngineState {
        var state = EngineState.initial
        state.counter = counter
        for p in Pattern.allCases { state.levels[p] = level }
        return state
    }

    /// v2.9: this file is about the growth-cap table and the freeze, so an
    /// unnamed "less" is taken under a run — session-wide delta (spec §19.2).
    private func after(_ state: EngineState, _ result: FeedbackResult,
                       overrides: [Pattern: Int] = [:]) -> EngineState {
        Engine.applyFeedback(state: result == .less ? state.underLessRun : state,
                             session: Engine.generateSession(state),
                             result: result, overrides: overrides)
    }

    // MARK: - The table (mechanism)

    /// Every cell the table does not declare falls back to the default, and
    /// the lookup covers the whole level lattice — including the set bands,
    /// which are tier 4 by encoding.
    func testMissingCellsFallBackToTheDefault() {
        for p in Pattern.allCases {
            for level in 0...EngineConfig.levelMax {
                let tier = Level.decode(level).tier
                let declared = EngineConfig.maxUpByPatternTier[p]?[tier]
                XCTAssertEqual(EngineConfig.maxUp(pattern: p, tier: tier),
                               declared ?? EngineConfig.maxUpPerSession,
                               "\(p.rawValue) tier \(tier): cap must follow the table")
            }
        }
    }

    /// The shipped values, cell by cell: calves at every tier, the vertical
    /// push from tier 3, the pull from tier 2 (the fixed slot makes it the
    /// most frequent pattern — issue #76), tier 4 for everyone, two
    /// everywhere else. The reference verifier checks the same table against
    /// the spec.
    func testTheShippedCeilingMatchesTheDeclaredRule() {
        for p in Pattern.allCases {
            for tier in 1...EngineConfig.tiers {
                // v2.10 (spec §20.1): the bar branch joins the pull's cells —
                // the cross-credit gives it the slot's full speed, so the
                // frequency argument of #76 reaches it too.
                let slow = p == .calf
                    || (p == .pushV && tier >= 3)
                    || (Pattern.pullSide.contains(p) && tier >= 2)
                    || tier == EngineConfig.tiers
                XCTAssertEqual(EngineConfig.maxUp(pattern: p, tier: tier), slow ? 1 : 2,
                               "\(p.rawValue) tier \(tier)")
            }
        }
    }

    /// The pull's cells are the one frequency argument in the table: the
    /// fixed slot gives it eight appearances where a rotating pattern gets
    /// five, so from the first real row on it is held to a step. Tier 1 is
    /// scapular activation, not a row, and deliberately keeps the default;
    /// the bar branch used to sit at four appearances in eight and went
    /// uncapped — until v2.10 (spec §20.1) gave the slot back its full speed
    /// through the cross-credit, which makes the same argument apply to it.
    func testThePullIsHeldToAStepFromTierTwo() {
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 1), 2, "tier 1 keeps the default")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 2), 1, "the inverted row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pull, tier: 3), 1, "the feet-elevated row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 2), 1, "the bar branch is capped alongside the row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 3), 1, "the bar branch is capped alongside the row")
        XCTAssertEqual(EngineConfig.maxUp(pattern: .pullBar, tier: 1), 2, "the hang keeps the default")

        // "More" at a tier-2 level takes one step, not two; "on plan" is
        // never capped, so the pull still moves every session.
        // v2.22 (spec §33): the cell counts SUB-STEPS, so all three land on
        // positions rather than on levels. The subject is untouched.
        assertPosition(after(seeded(level: 10), .more), .pull,
                       Level.rise(level: 10, sub: 0, by: 1), "the collateral +2 is gone")
        assertPosition(after(seeded(level: 10), .plan), .pull,
                       Level.rise(level: 10, sub: 0, by: 1),
                       "one step per session survives the cap")
        assertPosition(after(seeded(level: 4), .more), .pull,
                       Level.rise(level: 4, sub: 0, by: 2), "tier 1 still climbs by two")
    }

    /// The set bands are covered by the tier-4 cell rather than a special case.
    func testSetBandsAreTierFour() {
        for level in [24, 31, 32, 39, 40, 47] {
            XCTAssertEqual(Level.decode(level).tier, 4, "level \(level) is tier 4")
        }
    }

    // MARK: - The ceiling in applyFeedback

    /// "More" climbs by the cell, never past it, at every level.
    /// v2.22 (spec §33): re-marked. The cell counts SUB-STEPS — a "2" means two
    /// sub-steps, not two levels — so the expectation is derived from the same
    /// helper the engine uses. The subject (the cell governs the climb) stands.
    func testMoreClimbsByTheCell() {
        for level in 0...EngineConfig.levelMax {
            let state = seeded(level: level)
            let next = after(state, .more)
            for ex in Engine.generateSession(state).exercises {
                let cap = EngineConfig.maxUp(pattern: ex.pattern,
                                             tier: Level.decode(level).tier)
                assertPosition(next, ex.pattern,
                               Level.rise(level: level, sub: 0,
                                          by: min(EngineConfig.deltaMore, cap)),
                               "\(ex.pattern.rawValue) from \(level) with cap \(cap)")
            }
        }
    }

    /// A pointed fact far above the plan is clamped by the same cell.
    /// v2.22 (spec §33): in SUB-STEPS.
    func testAFactIsClampedByTheCell() {
        for level in 1...EngineConfig.levelMax {
            let state = seeded(level: level)
            let cap = EngineConfig.maxUp(pattern: .pull, tier: Level.decode(level).tier)
            let next = after(state, .plan, overrides: [.pull: 99])
            assertPosition(next, .pull, Level.rise(level: level, sub: 0, by: cap),
                           "an enormous fact from \(level) is capped at +\(cap) sub-steps")
        }
    }

    /// Calibration outranks the ceiling: from zero there is no achieved level
    /// to grow from, only the honest fact of the first workout.
    func testCalibrationFromZeroIgnoresTheCeiling() {
        let state = EngineState.initial
        let next = after(state, .plan, overrides: [.pull: 20])
        XCTAssertEqual(next.levels[.pull], 12,
                       "a fact of 20 reps from zero still calibrates straight to 12")
    }

    /// Downward moves are never capped, and the deload still fires on the
    /// third shortfall in a row.
    func testTheCeilingNeverActsDownwards() {
        var state = seeded(level: 10)
        var lastEntry = state.position(.pull)
        for _ in 0..<3 {
            lastEntry = state.position(.pull)
            state = after(state, .less)
        }
        // v2.23 (spec §34): the subject — the ceiling never bounds a descent,
        // and the deload still fires on the third shortfall — is untouched;
        // both figures changed unit. The old 4 was 10 − 1 − 1 − 1 − 3, three
        // level-wise "less" plus an ungated deload, and it landed `pull` on
        // tier 1 × 12 reps where the plan had asked for 3×7 — the deload made
        // the work 71 % heavier. Now the roll-back goes through the gate.
        assertPosition(state, .pull, expectedDeload(.pull, from: lastEntry),
                       "one sub-step, one sub-step, then the gated deload")
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: 10, to: state.levels[.pull]!, fromCut: 0, toCut: 0),
                      "a deload on top of a ceiling-1 cell may not make the plan heavier")
        XCTAssertEqual(state.failStreak[.pull], 0, "the deload resets the streak")
    }

    /// "On plan" is a step, whatever the cell allows.
    func testOnPlanIsAlwaysOneStep() {
        let next = after(seeded(level: 3), .plan)
        for ex in Engine.generateSession(seeded(level: 3)).exercises {
            // v2.22 (spec §33): one step is one SUB-STEP.
            assertPosition(next, ex.pattern, Level.rise(level: 3, sub: 0, by: 1),
                           "\(ex.pattern.rawValue)")
        }
    }

    // MARK: - Discomfort and the freeze

    private func report(_ state: EngineState, _ result: FeedbackResult,
                        discomfort: Set<Pattern> = [], skipped: Set<Pattern> = [],
                        overrides: [Pattern: Int] = [:]) -> EngineState {
        let base = result == .less && discomfort.isEmpty ? state.underLessRun : state
        return Engine.applyFeedback(state: base, session: Engine.generateSession(state),
                                    result: result, overrides: overrides,
                                    skipped: skipped, discomfort: discomfort)
    }

    /// v2.11 (spec §21.1), re-marked for v2.19 (spec §30.6) and again for
    /// v2.25 (spec §36.5): the report voids the session for the pattern AND
    /// takes the load off — as a CUT OF SETS at a level that does not move.
    /// The streak resets, the episode opens.
    func testDiscomfortLeavesTheSessionAloneAndFreezes() {
        var state = seeded(level: 12)
        state.failStreak[.pull] = 1
        let next = report(state, .more, discomfort: [.pull])

        XCTAssertEqual(next.levels[.pull], 12, "the level stands")
        XCTAssertEqual(next.cutOf(.pull),
                       Level.cutMax(level: 12, floor: EngineConfig.setsFloor),
                       "the sets come off down to the shared floor")
        XCTAssertEqual(next.failStreak[.pull], 0, "the unload resets the streak")
        XCTAssertEqual(next.freezeRemaining(.pull), Engine.painStair(seen: 1))
        XCTAssertEqual(next.sore[.pull], Engine.painStair(seen: 1), "the episode opens")
        XCTAssertEqual(next.counter, state.counter + 1, "the workout still happened")
        assertPosition(next, .squat, expectedPosition(state, .squat, delta: EngineConfig.deltaMore),
                       "a neighbour still climbs")
    }

    /// Frozen, the pattern holds its unloaded level for exactly N appearances
    /// — and then WAITS (v2.11, spec §21.2): taps never resume growth, only a
    /// fact at or above the plan does. `pull` is in every session, so
    /// appearances are sessions here.
    /// Re-marked for v2.25 (spec §36.5): the counters run in PARALLEL, so the
    /// appearance that burns the freeze closes the episode as well. The old
    /// sequence — freeze first, countdown afterwards — held a person on ONE
    /// set for 38 appearances after three reports, 12.7 weeks at three
    /// sessions a week. The subject of the block survives whole: the freeze
    /// holds for exactly N appearances, taps never resume growth, and the
    /// position does not move for any of them.
    func testTheFreezeHoldsForExactlyThreeAppearances() {
        var state = report(seeded(level: 20), .plan, discomfort: [.pull])
        let held = Position(level: 20, sub: 0,
                            cut: Level.cutMax(level: 20, floor: EngineConfig.setsFloor))
        assertPosition(state, .pull, held)
        let assigned = Engine.painStair(seen: 1)
        for left in stride(from: assigned, to: 0, by: -1) {
            XCTAssertEqual(state.freezeRemaining(.pull), left)
            XCTAssertEqual(state.soreLeft[.pull], left,
                           "the countdown runs alongside the freeze, not after it")
            state = report(state, .more)
            assertPosition(state, .pull, held, "no growth while frozen")
        }
        XCTAssertEqual(state.freezeRemaining(.pull), 0, "the freeze has run out")
        XCTAssertNil(state.sore[.pull],
                     "and the same appearance closed the episode — the counters are parallel")
        state = report(state, .more)
        // v2.25 (§36.3): growth returns a SET first, not a dose.
        assertPosition(state, .pull,
                       Level.riseBy(level: held.level, sub: held.sub, cut: held.cut,
                                    by: EngineConfig.deltaPlan, allowSetsBack: true),
                       "the first growth event after the episode gives a set back")
    }

    /// Honesty is never overridden: a fact still takes the level down, while
    /// one above the plan is clamped — and under the freeze it does not
    /// confirm either (v2.11: the assigned rest is served in full).
    func testAFactStillMovesAFrozenPatternDown() {
        // v2.25 (§36.5): the landing is a cut of sets at a standing level;
        // the block is about the fact, so it reads the landing rather than a
        // pinned number.
        let frozen = report(seeded(level: 20), .plan, discomfort: [.pull])
        let landed = Position(level: 20, sub: 0,
                              cut: Level.cutMax(level: 20, floor: EngineConfig.setsFloor))
        assertPosition(frozen, .pull, landed)
        let down = report(frozen, .plan, overrides: [.pull: 3])
        XCTAssertLessThan(down.levels[.pull]!, landed.level, "a fact below the plan still lands")
        // v2.25 (§36.4): the gate reads the TRIPLE — otherwise it would compare
        // a full plan with a trimmed one and call the lighter one heavier.
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: landed.level,
                                     to: down.levels[.pull]!, fromSub: landed.sub,
                                     toSub: down.sub[.pull] ?? 0,
                                     fromCut: landed.cut, toCut: down.cutOf(.pull)),
                      "and lands no harder than the plan it fell short of")
        let up = report(frozen, .plan, overrides: [.pull: 99])
        assertPosition(up, .pull, landed, "a fact above the plan cannot grow it")
        XCTAssertEqual(up.sore[.pull], Engine.painStair(seen: 1),
                       "a fact during the freeze does not confirm")
    }

    /// No double punishment: the unload resets the streak, and under the
    /// freeze — and the waiting after it — the streak stands, so the deload
    /// is unreachable until the episode is confirmed (v2.11, spec §21.2).
    func testAFreezeCannotDeload() {
        var state = seeded(level: 20)
        state.failStreak[.pull] = 2
        state = report(state, .less, discomfort: [.pull])
        // v2.25 (§36.5): the landing moved again — a cut of sets at a standing
        // level. The arithmetic below did not.
        var landed = Position(level: 20, sub: 0,
                              cut: Level.cutMax(level: 20, floor: EngineConfig.setsFloor))
        assertPosition(state, .pull, landed, "the report takes the load off")
        XCTAssertEqual(state.failStreak[.pull], 0, "and resets the streak")

        // v2.23 (spec §34.1) · v2.25 (spec §36.3): under a live episode "hard"
        // no longer stands still — the sets handle gives it a step down in
        // every one of the 480 cells, and under a live episode that step
        // reaches the PAIN floor (§36.9). The subject of the block is
        // untouched and now carries one more fact: the deload is unreachable
        // not merely because the streak is frozen, but because under a freeze
        // not even the INTENT is counted (§34.2) — while the position keeps
        // moving honestly downward the whole time.
        let assigned = Engine.painStair(seen: 1)
        for _ in 0..<assigned {
            state = report(state, .less)
            landed = Level.fallBy(level: landed.level, sub: landed.sub, cut: landed.cut,
                                  by: 1, floor: EngineConfig.setsFloorPain)
            assertPosition(state, .pull, landed,
                           "a shortfall under a freeze steps down, it does not deload")
            XCTAssertEqual(state.failStreak[.pull], 0, "the streak stays put")
        }
        XCTAssertNil(state.sore[.pull], "the parallel counters closed the episode")
        // Past the episode the streak starts counting again, and it takes the
        // full `failsToDeload` shortfalls to reach a deload — never fewer.
        for _ in 0..<(EngineConfig.failsToDeload - 1) {
            state = report(state, .less)
            XCTAssertNotEqual(state.failStreak[.pull], 0, "the streak counts again")
        }
    }

    /// v2.11 (spec §21.2 p.2): a repeat report doubles the rest up the
    /// 3 → 6 → 12 ladder instead of refreshing it, and never drops twice.
    /// Re-marked for v2.25 (spec §36.5): the ladder is read off `painSeen` —
    /// the movement's HISTORY — rather than off whether an episode is open,
    /// and the second report lands on the PAIN floor of sets instead of the
    /// previous tier's floor. The old landing left the plan heavier than it
    /// was before the pain in 53 cells of 480.
    func testARepeatReportDoublesTheRest() {
        var state = report(seeded(level: 20), .plan, discomfort: [.pull])
        XCTAssertEqual(state.painSeen[.pull], 1, "the memory of pain counts reports")
        state = report(state, .plan)
        XCTAssertEqual(state.freezeRemaining(.pull), Engine.painStair(seen: 1) - 1)
        state = report(state, .plan, discomfort: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), 6, "3 → 6")
        XCTAssertEqual(state.painSeen[.pull], 2)
        // v2.25 (§36.5): the second report is the pain floor of SETS, and the
        // level does not move at all.
        assertPosition(state, .pull,
                       Position(level: 20, sub: 0,
                                cut: Level.cutMax(level: 20, floor: EngineConfig.setsFloorPain)),
                       "the second report lands on the pain floor of sets")
        state = report(state, .plan, discomfort: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeCapAppearances, "6 → 12")
        state = report(state, .plan, discomfort: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeCapAppearances,
                       "the ladder tops out")
        // The depth of the CUT does not read the history: past the pain floor
        // nothing cuts deeper, only the rest gets longer (§36.5).
        XCTAssertEqual(state.cutOf(.pull),
                       Level.cutMax(level: 20, floor: EngineConfig.setsFloorPain),
                       "no report cuts below the pain floor")
    }

    /// A skip freezes the counter with everything else — the pattern was not
    /// trained, so the appearance does not count.
    func testASkipDoesNotSpendAnAppearance() {
        var state = report(seeded(level: 12), .plan, discomfort: [.pull])
        let before = state.freezeRemaining(.pull)
        state = report(state, .plan, skipped: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), before)
        assertPosition(state, .pull,
                       Position(level: 12, sub: 0,
                                cut: Level.cutMax(level: 12, floor: EngineConfig.setsFloor)),
                       "held at the unloaded position")
    }

    /// Named in both, discomfort wins: the unload is stronger than the fact,
    /// and the freeze carries information a silent skip does not.
    func testDiscomfortOutranksASkipAndAFact() {
        let state = report(seeded(level: 12), .more, discomfort: [.pull],
                           skipped: [.pull], overrides: [.pull: 99])
        assertPosition(state, .pull,
                       Position(level: 12, sub: 0,
                                cut: Level.cutMax(level: 12, floor: EngineConfig.setsFloor)))
        XCTAssertEqual(state.freezeRemaining(.pull), Engine.painStair(seen: 1))
    }

    /// A pattern that is not in the session is a no-op, as with skips.
    func testDiscomfortOutsideTheSessionIsANoOp() {
        let state = seeded(level: 12)
        let inSession = Set(Engine.generateSession(state).exercises.map(\.pattern))
        let outside = Pattern.allCases.first { !inSession.contains($0) }!
        XCTAssertEqual(report(state, .plan, discomfort: [outside]).freezeRemaining(outside), 0)
    }

    /// A break lowers the levels but must not thaw a freeze — nor close a
    /// pain episode (v2.11, spec §21.2 p.8).
    func testBreaksDoNotThawTheFreeze() {
        let frozen = report(seeded(level: 20), .plan, discomfort: [.pull])
        // v2.25 (§36.5): the report takes sets off, the level stands.
        let landed = Position(level: 20, sub: 0,
                              cut: Level.cutMax(level: 20, floor: EngineConfig.setsFloor))
        assertPosition(frozen, .pull, landed)
        let left = frozen.freezeRemaining(.pull)

        let decayed = Engine.applySilentDecay(state: frozen, gapDays: 10)
        XCTAssertEqual(decayed.freezeRemaining(.pull), left, "silent decay keeps the freeze")
        XCTAssertEqual(decayed.sore[.pull], Engine.painStair(seen: 1), "and the episode")
        // v2.25 (§36.7): a decay is a DESCENT and walks one step of the growth
        // path — on a block floor it takes a SET and leaves the level alone.
        assertPosition(decayed, .pull,
                       Level.fallBy(level: landed.level, sub: landed.sub, cut: landed.cut,
                                    by: 1, floor: EngineConfig.setsFloor),
                       "and still takes the step")

        let back = Engine.applyComeback(state: decayed, gapDays: 16, alreadyDecayed: true)
        XCTAssertEqual(back.freezeRemaining(.pull), left, "the comeback keeps it too")
        XCTAssertEqual(back.sore[.pull], Engine.painStair(seen: 1), "episode included")
        // v2.12 (spec §22.1): the landing crosses a tier boundary, so rep
        // continuity decides where it lands. Re-marked for v2.19 (§30.6) and
        // again for v2.25: the block is about a break not thawing a freeze, so
        // it asserts the property — down, and no harder — rather than a pinned
        // number, and it reads the whole triple both times.
        XCTAssertLessThan(Level.posOrd(back.position(.pull)),
                          Level.posOrd(decayed.position(.pull)),
                          "the tier crossing still goes down")
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: decayed.levels[.pull]!,
                                     to: back.levels[.pull]!,
                                     fromSub: decayed.sub[.pull] ?? 0,
                                     toSub: back.sub[.pull] ?? 0,
                                     fromCut: decayed.cutOf(.pull), toCut: back.cutOf(.pull)),
                      "and never asks for more work than before the break")
        XCTAssertEqual(Engine.applyComeback(state: frozen, gapDays: 16).levels[.pull],
                       back.levels[.pull], "the two paths still agree on the level")
        XCTAssertEqual(report(back, .more).levels[.pull], back.levels[.pull],
                       "and it is still frozen")
    }

    // MARK: - Serialization

    /// A state file written before the freeze existed decodes to "nothing
    /// frozen" rather than failing.
    func testLegacyStateDecodesWithoutTheFreezeField() throws {
        let legacy = """
        {"counter":3,"levels":["pull",5,"squat",4],"failStreak":["pull",1],"hasBar":true}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertTrue(state.frozen.isEmpty)
        XCTAssertEqual(state.levels[.pull], 5)
        XCTAssertEqual(state.hasBar, true)
    }

    /// And a state with a freeze round-trips.
    func testFreezeRoundTripsThroughTheStateFile() throws {
        let frozen = report(seeded(level: 12), .plan, discomfort: [.pull])
        let data = try JSONEncoder().encode(frozen)
        let back = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(back, frozen)
        XCTAssertEqual(back.freezeRemaining(.pull), EngineConfig.freezeAppearances)
    }
}
