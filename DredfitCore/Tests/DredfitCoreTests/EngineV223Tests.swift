//
//  DredfitCoreTests
//
//  Engine v2.23 (spec §34): "hard" steps back the way it came. Mirrors block
//  49 of the reference verifier.
//
//  The rating path was the last descent without a gate. It went by whole
//  levels and crossed a tier boundary freely, landing in the MIDDLE of the
//  tier below, where the dose is higher: `coreAntiExt` 24 → 23 meant 3×10 s →
//  3×31 s, `hinge` 24 → 23 meant 3×4 → 3×12 across both legs. The deload was
//  the second such path: three levels back with no check at all. Both are
//  closed here — and the exact-fact path is pinned to prove it did not move.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV223Tests: XCTestCase {

    private func seeded(_ level: Int, sub: Int = 0, counter: Int = 0,
                        hasBar: Bool = false) -> EngineState {
        var s = EngineState.initial
        s.counter = counter
        s.hasBar = hasBar
        for p in Pattern.allCases {
            s.levels[p] = level
            if sub > 0 { s.sub[p] = sub }
        }
        return s
    }

    /// A run of unnamed "less" ratings is already going, so the session delta
    /// is handed to everyone (spec §19.2) — that is how the DESCENT gets
    /// tested rather than the aim of §19.1, which has its own suite.
    private var allPositions: [Position] {
        (0...EngineConfig.levelMax).flatMap { level in
            (0..<Level.subSteps(at: level)).map { Position(level: level, sub: $0) }
        }
    }

    // MARK: - (a) The sweep: a rating never adds work and never changes variation

    /// Every position on the scale × 10 patterns × both steps (a plain "less"
    /// and the chronic double one). What is asserted is not a number but a
    /// property: the §25.3 gate on the result, the tier, band and unit left
    /// alone, work strictly down everywhere except a block floor, where the
    /// position is required to stand.
    func testTheEvaluativeDescentNeverAddsWorkAnywhereOnTheScale() {
        for entry in allPositions {
            for count in [-EngineConfig.deltaLess, -EngineConfig.chronicStep] {
                let to = Level.descend(level: entry.level, sub: entry.sub, by: count)
                let from = Level.decode(entry.level), landed = Level.decode(to.level)
                XCTAssertEqual(landed.tier, from.tier,
                               "\(entry.level).\(entry.sub) by \(count): the tier changed")
                XCTAssertEqual(landed.sets, from.sets,
                               "\(entry.level).\(entry.sub) by \(count): the band changed")
                XCTAssertEqual(Level.bandFloor(to.level), Level.bandFloor(entry.level),
                               "\(entry.level).\(entry.sub) by \(count): it left its block")
                XCTAssertEqual(Level.ordinal(to),
                               max(Level.ordinal(entry) - count,
                                   Level.ordinal(level: Level.bandFloor(entry.level), sub: 0)),
                               "\(entry.level).\(entry.sub): not exactly \(count) sub-steps back")
                for p in Pattern.allCases {
                    let a = Level.work(pattern: p, level: entry.level, sub: entry.sub, cut: 0)
                    let b = Level.work(pattern: p, level: to.level, sub: to.sub, cut: 0)
                    XCTAssertTrue(Level.noHarder(pattern: p, from: entry.level, to: to.level,
                                                 fromSub: entry.sub, toSub: to.sub, fromCut: 0, toCut: 0),
                                  "\(p) \(entry.level).\(entry.sub) → \(to.level).\(to.sub) is heavier")
                    XCTAssertEqual(b.unit, a.unit, "\(p): the unit changed under a descent")
                    XCTAssertEqual(b.sides, a.sides, "\(p): the sides changed under a descent")
                    if Level.ordinal(to) < Level.ordinal(entry) {
                        XCTAssertLessThan(b.total, a.total,
                                          "\(p) \(entry.level).\(entry.sub): no work came off")
                    } else {
                        XCTAssertEqual(entry.level, Level.bandFloor(entry.level),
                                       "\(p) \(entry.level).\(entry.sub): standing off a block floor")
                    }
                }
            }
        }
    }

    /// The same sweep through the ENGINE rather than the helper: the session
    /// delta has to walk exactly this rule. Every phase of the rotation is
    /// covered, so all ten patterns take part.
    func testTheEngineDescendsByTheRuleOnEveryPositionAndPattern() {
        for entry in allPositions {
            for counter in 0..<(2 * EngineConfig.stepsPerTier) {
                var state = seeded(entry.level, sub: entry.sub, counter: counter,
                                   hasBar: counter % 2 == 1)
                state = state.underLessRun
                let session = Engine.generateSession(state)
                let after = Engine.applyFeedback(state: state, session: session, result: .less)
                for ex in session.exercises {
                    assertDescended(after, ex.pattern, from: entry, by: -EngineConfig.deltaLess,
                                    "\(ex.pattern) from \(entry.level).\(entry.sub)")
                    // §34.2: the streak counts the INTENT — on a block floor
                    // the position stands and the counter still moves, or the
                    // deload there would be out of reach.
                    XCTAssertEqual(after.failStreak[ex.pattern], 1,
                                   "\(ex.pattern) at \(entry.level).\(entry.sub): the intent did not count")
                }
            }
        }
    }

    // MARK: - (b) On a block floor three "hard" ratings deload, through the gate

    func testOnABlockFloorThreeHardRatingsDeloadAndTheDeloadIsNotHeavier() {
        for floor in stride(from: 0, through: EngineConfig.levelMax, by: EngineConfig.stepsPerTier) {
            var state = seeded(floor, hasBar: true)
            // Counted in APPEARANCES, not sessions: a rotating pattern stands
            // in five sessions out of eight, so "three sessions running" is
            // not the same thing as three shortfalls (the reason §26.1 counts
            // its window in appearances too).
            var seen = Dictionary(uniqueKeysWithValues: Pattern.allCases.map { ($0, 0) })
            // v2.25 (spec §36.3): on a block floor a "less" takes a SET, so
            // the expected position is tracked through the run instead of
            // being pinned to the floor. The subject of the block is untouched
            // and gains a fact: the level never crosses the block floor even
            // though the position keeps moving.
            var want = Dictionary(uniqueKeysWithValues:
                Pattern.allCases.map { ($0, Position(level: floor, sub: 0, cut: 0)) })
            var deloaded: Set<Pattern> = []
            var guardCount = 0
            while deloaded.count < Pattern.allCases.count && guardCount < 4 * EngineConfig.stepsPerTier {
                guardCount += 1
                let session = Engine.generateSession(state)
                state = Engine.applyFeedback(state: state.underLessRun, session: session,
                                             result: .less)
                for ex in session.exercises where !deloaded.contains(ex.pattern) {
                    let p = ex.pattern
                    seen[p]! += 1
                    let before = want[p]!
                    let stepped = Level.fallBy(level: before.level, sub: before.sub,
                                               cut: before.cut, by: 1,
                                               floor: EngineConfig.setsFloor)
                    if seen[p]! < EngineConfig.failsToDeload {
                        want[p] = stepped
                        assertPosition(state, p, stepped,
                                       "floor \(floor): hard #\(seen[p]!) moved \(p) off the rule")
                        XCTAssertEqual(stepped.level, floor,
                                       "floor \(floor): hard #\(seen[p]!) crossed the block floor of \(p)")
                        XCTAssertEqual(state.failStreak[p], seen[p]!,
                                       "floor \(floor): the streak of \(p) after hard #\(seen[p]!)")
                    } else {
                        want[p] = expectedDeload(p, from: before, stepped: stepped)
                        assertPosition(state, p, want[p]!,
                                       "floor \(floor): the deload of \(p) missed the rule")
                        XCTAssertTrue(Level.noHarder(pattern: p, from: before.level,
                                                     to: state.levels[p]!, fromSub: before.sub,
                                                     toSub: state.sub[p] ?? 0,
                                                     fromCut: before.cut, toCut: state.cutOf(p)),
                                      "floor \(floor): the deload of \(p) made the plan heavier")
                        XCTAssertEqual(state.failStreak[p], 0,
                                       "floor \(floor): the deload of \(p) left the streak")
                        if floor > 0 {
                            XCTAssertLessThan(state.levels[p]!, floor,
                                              "floor \(floor): the deload of \(p) led nowhere")
                            let landedIn = Level.decode(state.levels[p]!)
                            XCTAssertTrue(landedIn.tier < Level.decode(floor).tier
                                          || landedIn.sets < Level.decode(floor).sets,
                                          "floor \(floor): the deload of \(p) stayed in the same variation")
                        } else {
                            XCTAssertEqual(state.levels[p], 0,
                                           "at the very bottom a deload has nowhere to lead")
                        }
                        deloaded.insert(p)
                    }
                }
            }
            XCTAssertEqual(deloaded.count, Pattern.allCases.count,
                           "floor \(floor): only \(deloaded.count) patterns reached a deload")
        }
    }

    /// The acceptance run: `coreAntiExt` from level 24, the floor of tier 4.
    /// "Hard" does not move it — the old step 24 → 23 read as 3×10 s → 3×31 s
    /// — and three of them land it on the floor of tier 3 without adding work.
    func testTheAcceptanceRunOnCoreAntiExtension() {
        let p = Pattern.coreAntiExt
        let top = 3 * EngineConfig.stepsPerTier                     // 24
        var state = seeded(top)
        var hits = 0, guardCount = 0
        while hits < EngineConfig.failsToDeload && guardCount < 4 * EngineConfig.stepsPerTier {
            guardCount += 1
            let session = Engine.generateSession(state)
            let inSession = session.exercises.contains { $0.pattern == p }
            state = Engine.applyFeedback(state: state.underLessRun, session: session, result: .less)
            guard inSession else { continue }
            hits += 1
            if hits < EngineConfig.failsToDeload {
                // v2.25 (spec §36.3): L24 is a tier floor, so the LEVEL still
                // does not move — but the sets handle gives the rating a step
                // there, which is the whole point of the wave: before it, a
                // "hard" on a block floor was an inert tap.
                XCTAssertEqual(state.levels[p], top,
                               "L24 is a tier floor: hard #\(hits) must not move the level")
                // Band 3 has exactly one set to give above the shared floor,
                // so the second "hard" finds the bottom of the variation and
                // the position stands — which is what still builds the streak
                // toward the deload (§34.2).
                XCTAssertEqual(state.cutOf(p),
                               min(hits, Level.cutMax(level: top, floor: EngineConfig.setsFloor)),
                               "and hard #\(hits) takes a set while the band has one to give")
                XCTAssertEqual(state.failStreak[p], hits, "the streak is \(hits)")
            }
        }
        XCTAssertEqual(state.levels[p], Level.tierFloor(top - 1),
                       "three hard ratings land on the floor of tier 3")
        // "No more work" is read by the GATE here, not by a sum of seconds:
        // L16 is the floor of tier 3, the smallest dose an easier variation
        // has, and a measure in seconds across a change of variation is not
        // valid (§30.2/§30.4). The sum does go 30 → 45 s — the same landing the
        // second step of taking the load off gives (§30.6), where that price
        // is named and accepted.
        XCTAssertTrue(Level.noHarder(pattern: p, from: top, to: state.levels[p]!, fromCut: 0, toCut: 0),
                      "the deload is not heavier by the gate")
        XCTAssertEqual(state.levels[p], Level.tierFloor(state.levels[p]!),
                       "the landing is the smallest dose of its own variation")
        // And the step the wave closed: the old level-wise 24 → 23 asked for
        // three times the work here, six times on `hinge`.
        XCTAssertGreaterThan(Level.work(pattern: p, level: top - 1, sub: 0, cut: 0).total,
                             Level.work(pattern: p, level: top, sub: 0, cut: 0).total * 3,
                             "the old level-wise step really did treble the work")
        XCTAssertGreaterThan(Level.work(pattern: .hinge, level: top - 1, sub: 0, cut: 0).total,
                             Level.work(pattern: .hinge, level: top, sub: 0, cut: 0).total * 5,
                             "on hinge the same step cost six times as much")
    }

    /// The second acceptance run: `squat` at (12, 2) gives back the sub-step
    /// of one set. The level and the variation stand.
    func testTheAcceptanceRunOnSquatInsideABlock() throws {
        let state = seeded(12, sub: 2).underLessRun
        let session = Engine.generateSession(state)
        XCTAssertTrue(session.exercises.contains { $0.pattern == .squat }, "squat is in the session")
        let after = Engine.applyFeedback(state: state, session: session, result: .less)
        assertPosition(after, .squat, Position(level: 12, sub: 1), "squat (12,2) → (12,1)")
    }

    // MARK: - (c) The exact-fact path did not move

    /// The v2.22 formula is written out here in full and swept against the
    /// engine over (position × fact): the athlete's honesty does not fall
    /// under §34.1 (§15.2 p.2), and its path is still invert-to-a-level, pass
    /// the §25.3 gate, zero the sub-step.
    func testThePointFactPathIsBitForBitV222() throws {
        func factPositionV222(_ p: Pattern, _ ex: SessionExercise, actual: Int,
                              oldL: Int, oldSub: Int) -> Position {
            let sets = Level.decode(oldL).sets
            let cap = EngineConfig.maxUp(pattern: p, tier: Level.decode(oldL).tier)
            let oldOrdinal = Level.ordinal(level: oldL, sub: oldSub)
            let factL = Level.fromActual(pattern: p, tier: ex.tier, sets: sets, actual: actual)
            let window = Level.step(of: ex.unit, tier: ex.tier, sets: sets, load: ex.load)
            if actual >= ex.load && actual < ex.load + window {
                return Level.rise(level: oldL, sub: oldSub, by: min(EngineConfig.deltaPlan, cap))
            }
            if oldL == 0 {
                let zeroCeil = EngineConfig.isSlowTissue(p)
                    ? EngineConfig.stepsPerTier - 1 : 2 * EngineConfig.stepsPerTier - 1
                return Position(level: min(max(factL, 0), zeroCeil), sub: 0)
            }
            let factOrdinal = Level.ordinal(level: factL, sub: 0)
            if factOrdinal > oldOrdinal {
                return Level.position(atOrdinal: min(factOrdinal, oldOrdinal + cap))
            }
            return Position(level: Level.descendNoHarder(pattern: p, from: oldL,
                                                         factLevel: factL, fromSub: oldSub, fromCut: 0),
                            sub: 0)
        }

        for entry in allPositions {
            let state = seeded(entry.level, sub: entry.sub,
                               counter: entry.level % (2 * EngineConfig.stepsPerTier))
            let session = Engine.generateSession(state)
            for ex in session.exercises {
                let p = ex.pattern
                for actual in [0, max(0, ex.load - 2), ex.load, ex.load + 1, ex.load + 20] {
                    // One movement per call: the humble group landing (§26.2)
                    // is a property of a session and is not the subject here.
                    let after = Engine.applyFeedback(state: state, session: session,
                                                     result: .plan, overrides: [p: actual])
                    let want = factPositionV222(p, ex, actual: actual,
                                                oldL: entry.level, oldSub: entry.sub)
                    assertPosition(after, p, want,
                                   "the fact path moved — \(p) \(entry.level).\(entry.sub), fact \(actual)")
                    // §33.5 word for word: on this path the streak reads the
                    // LEVEL, not the position.
                    XCTAssertEqual(after.failStreak[p], want.level < entry.level ? 1 : 0,
                                   "the streak of \(p) on the fact path changed (\(entry.level).\(entry.sub), fact \(actual))")
                }
            }
        }
    }

    /// A deload on the fact path counts from the honest landing, never from
    /// `oldL`: it may not put the plan back above the number its owner named.
    func testADeloadOnTheFactPathCountsFromTheHonestLanding() throws {
        for level in (2 * EngineConfig.stepsPerTier)...EngineConfig.levelMax {
            var state = seeded(level)
            for p in Pattern.allCases { state.failStreak[p] = EngineConfig.failsToDeload - 1 }
            let session = Engine.generateSession(state)
            guard let ex = session.exercises.first(where: { $0.pattern == .pull }) else { continue }
            let actual = max(0, ex.load - 1)
            let factL = Level.fromActual(pattern: .pull, tier: ex.tier,
                                         sets: Level.decode(level).sets, actual: actual)
            let landed = Level.descendNoHarder(pattern: .pull, from: level, factLevel: factL, fromCut: 0)
            guard landed < level else { continue }        // the fact led nowhere down
            let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                             overrides: [.pull: actual])
            assertPosition(after, .pull,
                           expectedDeload(.pull, from: Position(level: level, sub: 0), base: landed),
                           "L=\(level): the deload counts from the landing \(landed)")
            XCTAssertLessThanOrEqual(after.levels[.pull] ?? 0, landed,
                                     "L=\(level): the deload rose above the honest landing")
            XCTAssertTrue(Level.noHarder(pattern: .pull, from: level, to: after.levels[.pull]!, fromCut: 0, toCut: 0),
                          "L=\(level): the deload on the fact path made the plan heavier")
        }
    }
}
