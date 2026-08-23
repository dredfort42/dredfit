//
//  EngineV222Tests.swift
//  DredfitCoreTests
//
//  Engine v2.22 (spec §33): the sub-step, and the cancellation of the
//  hold-this-level input. Mirrors block 26 of the reference verifier.
//
//  One rung of a level used to add its dose to ALL the sets at once — a median
//  of +11 % more work per growth event, up to +25 % on reps. A sub-step splits
//  the rung across the sets, so the plan parks on the trainee's capacity and an
//  overshoot costs one rep in one set instead of a whole level. That is also
//  what made the second entry into the freeze redundant.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV222Tests: XCTestCase {

    private func seeded(_ level: Int, counter: Int = 0, hasBar: Bool = false) -> EngineState {
        var s = EngineState.initial
        s.counter = counter
        s.hasBar = hasBar
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    private func tap(_ state: EngineState, _ result: FeedbackResult = .plan,
                     overrides: [Pattern: Int] = [:], skipped: Set<Pattern> = []
                     ) -> EngineState {
        Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                             result: result, overrides: overrides, skipped: skipped)
    }

    // MARK: - (a) Migration: at sub = 0 the plan is v2.21's

    /// The one claim of the wave that cannot be derived from today's engine —
    /// it compares against the numbers of the PREVIOUS encoding. Those numbers
    /// are not invented here: the plan at `sub == 0` must equal what the very
    /// same encoding gives with no sub-step at all, so the sweep recomputes it.
    func testAtSubZeroThePlanIsBitForBitTheOldOne() {
        var cells = 0
        for level in 0...EngineConfig.levelMax {
            for counter in 0..<8 {
                for hasBar in [false, true] {
                    let state = seeded(level, counter: counter, hasBar: hasBar)
                    for ex in Engine.generateSession(state).exercises {
                        cells += 1
                        let d = Level.decode(state.levels[ex.pattern] ?? 0)
                        let entry = ExerciseLibrary.entry(for: ex.pattern)
                        let expected = entry.unit(forTier: d.tier) == .reps ? d.reps : d.hold
                        XCTAssertEqual(ex.load, expected,
                                       "L\(level)/\(counter) \(ex.pattern): the base is v2.21's dose")
                        XCTAssertNil(ex.loads,
                                     "L\(level)/\(counter) \(ex.pattern): a uniform plan says nothing")
                        XCTAssertEqual(ex.perSetLoads, Array(repeating: expected, count: ex.sets),
                                       "L\(level)/\(counter) \(ex.pattern): every set on the dose")
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(cells, 480, "the sweep covered \(cells) plan cells")
    }

    /// A state file written before the field existed reads as all zeros.
    func testAStateWithoutTheFieldDecodesToAUniformPlan() throws {
        let legacy = """
        {"counter":3,"levels":["squat",12,"pull",12],"failStreak":[],"hasBar":false}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertTrue(state.sub.isEmpty, "no field means no sub-steps")
        for ex in Engine.generateSession(state).exercises {
            XCTAssertNil(ex.loads, "\(ex.pattern): the plan is uniform")
        }
    }

    // MARK: - (b) Monotonicity along the growth path

    /// `(L,0) → (L,1) → … → (L+1,0)`: the work rises strictly, and no single
    /// sub-step costs more than a whole level used to.
    func testTheGrowthPathRisesStrictlyAndNeverHarderThanALevel() {
        for p in Pattern.allCases {
            for level in 0..<EngineConfig.levelMax where !Level.subDisabled(at: level) {
                let sets = Level.decode(level).sets
                let levelStep = Level.work(pattern: p, level: level + 1, sub: 0, cut: 0).total
                    - Level.work(pattern: p, level: level, sub: 0, cut: 0).total
                var previous = Level.work(pattern: p, level: level, sub: 0, cut: 0).total
                for k in 1...sets {
                    let at = Level.rise(level: level, sub: 0, by: k)
                    let current = Level.work(pattern: p, level: at.level, sub: at.sub, cut: 0).total
                    XCTAssertGreaterThan(current, previous,
                                         "\(p) L\(level): sub-step \(k) must be strictly heavier")
                    if levelStep > 0 {
                        XCTAssertLessThanOrEqual(current - previous, levelStep,
                                                 "\(p) L\(level): a sub-step is never a whole level")
                    }
                    previous = current
                }
                let full = Level.rise(level: level, sub: 0, by: sets)
                XCTAssertEqual(full.level, level + 1, "\(p) L\(level): sets(L) sub-steps make a level")
                XCTAssertEqual(full.sub, 0)
            }
        }
    }

    /// The acceptance numbers: the worst relative step of ONE growth event is
    /// at most 9 % on reps and 6 % on statics. Compared as integer fractions —
    /// a percentage in floating point would depend on the platform (§32.1).
    func testTheWorstGrowthEventStaysInsideTheAcceptanceBounds() {
        for p in Pattern.allCases {
            for level in 0...EngineConfig.levelMax where !Level.subDisabled(at: level) {
                for sub in 0..<Level.decode(level).sets {
                    let from = Level.work(pattern: p, level: level, sub: sub, cut: 0)
                    let to = Level.rise(level: level, sub: sub, by: 1)
                    let step = Level.work(pattern: p, level: to.level, sub: to.sub, cut: 0).total - from.total
                    let bound = from.unit == .reps ? 9 : 6
                    XCTAssertLessThanOrEqual(step * 100, from.total * bound,
                                             "\(p) L\(level).\(sub): step \(step) of \(from.total)")
                }
            }
        }
    }

    // MARK: - (c) The tier boundary carries no mixed doses

    func testTheTopRungOfEveryTierIsAlwaysUniform() {
        for p in Pattern.allCases {
            for level in stride(from: EngineConfig.stepsPerTier - 1,
                                through: EngineConfig.levelMax,
                                by: EngineConfig.stepsPerTier) {
                XCTAssertTrue(Level.subDisabled(at: level), "L\(level) is a top rung")
                XCTAssertEqual(Level.subSteps(at: level), 1,
                               "L\(level): one growth event leaves for L+1")
                XCTAssertEqual(Level.subDelta(pattern: p, level: level), 0,
                               "\(p) L\(level): no sub-step increment exists")
                for sub in 0...EngineConfig.setsMax {
                    XCTAssertNil(Level.perSetLoads(pattern: p, level: level, sub: sub,
                                                   sets: Level.decode(level).sets),
                                 "\(p) L\(level) sub \(sub): the plan must stay uniform")
                }
            }
        }
    }

    /// Wherever a sub-step IS enabled, rung `L+1` is the same tier, the same
    /// band and the same unit — that is what makes it legal to mix in one
    /// exercise at all.
    func testASubStepNeverCrossesAVariation() {
        for p in Pattern.allCases {
            for level in 0..<EngineConfig.levelMax where !Level.subDisabled(at: level) {
                let a = Level.decode(level), b = Level.decode(level + 1)
                XCTAssertEqual(a.tier, b.tier, "\(p) L\(level): same tier")
                XCTAssertEqual(a.sets, b.sets, "\(p) L\(level): same band")
                XCTAssertEqual(Level.work(pattern: p, level: level, sub: 0, cut: 0).unit,
                               Level.work(pattern: p, level: level + 1, sub: 0, cut: 0).unit,
                               "\(p) L\(level): same unit")
            }
        }
    }

    /// Even a hand-edited state cannot make a top rung uneven.
    func testGarbageOnATopRungIsHealedToAUniformPlan() {
        var state = seeded(EngineConfig.stepsPerTier - 1)
        for p in Pattern.allCases { state.sub[p] = 2 }
        for ex in Engine.generateSession(state).exercises {
            XCTAssertNil(ex.loads, "\(ex.pattern): a top rung stays uniform")
        }
    }

    // MARK: - (d) Sanitizing

    func testGarbageInTheSubStepReadsAsZero() {
        for junk in [-1, -99, Int.min] {
            var state = seeded(12)
            state.sub[.pull] = junk
            let pull = Engine.generateSession(state).exercises.first { $0.pattern == .pull }
            XCTAssertNil(pull?.loads, "junk \(junk) reads as zero")
        }
    }

    func testASubStepAboveTheBandClampsToTheBand() {
        for level in 0...EngineConfig.levelMax where !Level.subDisabled(at: level) {
            var state = seeded(level)
            state.sub[.pull] = 99
            let pull = Engine.generateSession(state).exercises.first { $0.pattern == .pull }
            let loads = try? XCTUnwrap(pull?.loads)
            XCTAssertEqual(loads?.count, pull?.sets, "L\(level): one entry per set")
            let heavier = loads?.filter { $0 > (pull?.load ?? 0) }.count ?? -1
            XCTAssertEqual(heavier, min(Level.decode(level).sets - 1, (pull?.sets ?? 1) - 1),
                           "L\(level): clamped to sets-1")
            XCTAssertEqual(loads?.last, pull?.load, "L\(level): the last set carries the base")
        }
    }

    /// Sparseness is part of the contract: a zero is never stored, so a state
    /// that descended is indistinguishable from one that never rose.
    func testAZeroSubStepIsNeverStored() {
        var state = seeded(10)
        state.sub[.pull] = 0
        state.sub[.squat] = 0
        let after = tap(state, .less)
        XCTAssertTrue(after.sub.values.allSatisfy { $0 > 0 },
                      "no zero ever reaches the stored map")
    }

    func testASubStepSurvivesACodableRoundTrip() throws {
        let grown = tap(seeded(10))
        XCTAssertFalse(grown.sub.isEmpty, "the fixture must actually carry a sub-step")
        let data = try JSONEncoder().encode(grown)
        let back = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(back.sub, grown.sub, "the sub-step round-trips")
        XCTAssertEqual(Engine.generateSession(back), Engine.generateSession(grown))
    }

    // MARK: - (e) The cross-credit counts sub-steps

    /// A difference of LEVELS would read zero in two cases out of three, and
    /// the credit would silently zero itself out — handing the pull slot back
    /// the half speed §20.1 was written to fix.
    func testBothBranchesOfTheSlotGainEquallyWithTheBar() {
        for level in [0, 4, 10, 20, 30, 36, 44] {
            var state = seeded(level, hasBar: true)
            let entry = (pull: Level.ordinal(state.position(.pull)),
                         bar: Level.ordinal(state.position(.pullBar)))
            for _ in 0..<8 { state = tap(state) }
            let gainedPull = Level.ordinal(state.position(.pull)) - entry.pull
            let gainedBar = Level.ordinal(state.position(.pullBar)) - entry.bar
            XCTAssertEqual(gainedPull, gainedBar,
                           "L\(level): the branches keep level with each other")
            if level < EngineConfig.levelMax {
                XCTAssertGreaterThan(gainedPull, 0, "L\(level): the slot grows at all")
            }
        }
    }

    func testTheCreditIsMirroredFromEitherSideOfTheSlot() {
        for counter in [0, 1] {
            let state = seeded(12, counter: counter, hasBar: true)
            let before = (pull: Level.ordinal(state.position(.pull)),
                          bar: Level.ordinal(state.position(.pullBar)))
            let after = tap(state)
            XCTAssertEqual(Level.ordinal(after.position(.pull)) - before.pull,
                           Level.ordinal(after.position(.pullBar)) - before.bar,
                           "counter \(counter): the gain is mirrored")
        }
    }

    // MARK: - (f) The hold-this-level input no longer exists

    /// The state has no key for it, and neither does the plan snapshot. The
    /// argument is gone from the signature too, which the compiler enforces:
    /// this file would not build if `pinned:` were still accepted.
    func testTheCancelledInputLeavesNoTraceInTheState() throws {
        let state = tap(seeded(10))
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(state), encoding: .utf8))
        XCTAssertFalse(json.lowercased().contains("pinned"),
                       "the encoded state carries no cancelled key")
        let session = Engine.generateSession(state)
        let plan = try XCTUnwrap(String(data: try JSONEncoder().encode(session), encoding: .utf8))
        XCTAssertFalse(plan.lowercased().contains("pinned"),
                       "the encoded plan carries no cancelled key")
    }

    // MARK: - The plan a person sees

    /// The acceptance ladder: `squat` from L0 goes 8-8-8 → 9-8-8 → 9-9-8 →
    /// 3×9 (which IS 9-9-9, one level up).
    func testTheSquatLadderFromZeroMatchesTheAcceptanceNumbers() {
        var seen: [String] = []
        var state = EngineState.initial
        for _ in 0..<12 where seen.count < 4 {
            let session = Engine.generateSession(state)
            if let squat = session.exercises.first(where: { $0.pattern == .squat }) {
                seen.append(squat.loads.map { $0.map(String.init).joined(separator: "-") }
                    ?? "\(squat.sets)×\(squat.load)")
            }
            state = Engine.applyFeedback(state: state, session: session, result: .plan)
        }
        XCTAssertEqual(seen, ["3×8", "9-8-8", "9-9-8", "3×9"],
                       "the plan grows one set at a time")
    }

    /// A session snapshot written before the field existed still decodes — the
    /// journal of build 1.9 depends on it.
    func testAPlanSnapshotWithoutPerSetLoadsStillDecodes() throws {
        let legacy = """
        {"pattern":"squat","name":"Squat","tier":1,"unit":"reps","load":8,
         "perSide":false,"sets":3,"restSetSec":60,"restExerciseSec":60}
        """
        let ex = try JSONDecoder().decode(SessionExercise.self, from: Data(legacy.utf8))
        XCTAssertNil(ex.loads, "no key means a uniform plan")
        XCTAssertEqual(ex.perSetLoads, [8, 8, 8])
        XCTAssertEqual(ex.plannedLoad(set: 2), 8)
        XCTAssertEqual(ex.plannedVolume, 24)
    }

    /// And an uneven plan reads per set, in descending order.
    func testAnUnevenPlanReadsPerSet() throws {
        var state = seeded(10)
        state.sub[.pull] = 2
        let pull = try XCTUnwrap(Engine.generateSession(state).exercises
            .first { $0.pattern == .pull })
        let loads = try XCTUnwrap(pull.loads)
        XCTAssertEqual(loads.count, pull.sets)
        XCTAssertEqual(loads.sorted(by: >), loads, "the heavier sets come first")
        XCTAssertEqual(pull.load, loads.min(), "`load` is the plan's minimum")
        XCTAssertEqual(pull.plannedVolume, loads.reduce(0, +))
        XCTAssertTrue(pull.display.contains("-"), "the display spells the sets out")
    }

    /// A hand-edited record claiming `Int.max` sets must not be able to make
    /// the per-set walk allocate. This crashed the app the first time the
    /// property was written: `Array(repeating:count:)` took the record's claim
    /// at face value, which is the very trap `SetFacts.allSets` carries a
    /// comment about. The walk is bounded by the SCALE.
    func testAHostileSetCountCannotMakeThePerSetWalkAllocate() throws {
        let hostile = try JSONDecoder().decode(SessionExercise.self, from: Data("""
        {"pattern":"squat","name":"x","tier":1,"unit":"reps","load":15,
         "perSide":false,"sets":9223372036854775807,
         "restSetSec":60,"restExerciseSec":60}
        """.utf8))
        XCTAssertEqual(hostile.sets, Int.max, "the record really is unclamped")
        XCTAssertEqual(hostile.perSetLoads.count, EngineConfig.setsMax,
                       "the walk stops at the scale's ceiling")
        XCTAssertEqual(hostile.plannedLoad(set: Int.max), 15,
                       "and an absurd index still answers the plan")
        XCTAssertEqual(hostile.plannedVolume, 15 * EngineConfig.setsMax)
    }

    /// The duration estimate counts the sub-steps' addition — otherwise it
    /// would understate an uneven plan by exactly that.
    func testTheDurationEstimateSeesTheUnevenPlan() {
        var uneven = seeded(10)
        uneven.sub[.pull] = 2
        let flat = Engine.generateSession(seeded(10))
        let bumped = Engine.generateSession(uneven)
        XCTAssertGreaterThan(bumped.estimatedTotalMin, flat.estimatedTotalMin,
                             "heavier sets make a longer session")
    }

    // MARK: - Descents stay in whole levels

    func testEveryDescentZeroesTheSubStep() throws {
        var grown = seeded(20)
        grown.sub[.pull] = 2
        // v2.23 (spec §34.1): the RATING is now the one descent that does not
        // zero the sub-step — it gives back exactly one, walking the growth
        // path backwards, because that is the whole point of the wave. Every
        // descent that moves a LEVEL still zeroes it, and the five cases below
        // are unchanged. The run is already going, so the delta is
        // session-wide (§19.2) — an unnamed "less" is otherwise targeted and
        // would simply leave `pull` holding, sub-step included.
        grown.lessRun = EngineConfig.lessRunToGlobal
        assertDescended(tap(grown, .less), .pull, from: grown.position(.pull), by: 1,
                        "a 'less' gives back one sub-step instead of zeroing it")
        // A fact below the base dose.
        let session = Engine.generateSession(grown)
        let pull = try XCTUnwrap(session.exercises.first { $0.pattern == .pull })
        let below = Engine.applyFeedback(state: grown, session: session, result: .plan,
                                         overrides: [.pull: max(0, pull.load - 3)])
        XCTAssertEqual(below.sub[.pull] ?? 0, 0, "a fact below the base zeroes it")
        // v2.26 (§37.4): the pain report was one of the paths that zeroed the
        // sub-step; it is gone. The handle "give me an easier variation" now
        // does it, and for a reason the report never had — the variation
        // changed, so there is nothing to carry the old position on (§30.4).
        XCTAssertEqual(Engine.easierVariation(state: grown, pattern: .pull).sub[.pull] ?? 0, 0,
                       "the easier-variation handle zeroes it")
        // A break, either kind.
        XCTAssertTrue(Engine.applyComeback(state: grown, gapDays: 30).sub.isEmpty,
                      "a comeback zeroes every one")
        // Re-marked for v2.25 (spec §36.7): a decay drops the sub-steps and
        // THEN walks one step of the growth path from there, so what it leaves
        // is that step's own sub-step, not an empty map. The subject — every
        // descent gives up what the trainee did not earn — is asserted as the
        // composition of the two, which is stricter than "empty": it pins
        // where the step landed as well.
        let decayed = Engine.applySilentDecay(state: grown, gapDays: 9)
        for p in Pattern.allCases {
            assertPosition(decayed, p,
                           Level.fallBy(level: 20, sub: 0, cut: 0, by: 1,
                                        floor: EngineConfig.setsFloor),
                           "a silent decay drops the sub-step and steps back once (\(p))")
        }
    }

    /// Giving up sub-steps without losing a level is not a shortfall — the
    /// streak must not start counting toward a deload for it.
    func testDroppingSubStepsAloneIsNotAShortfall() throws {
        // v2.23 (spec §34.2): the claim belongs to the EXACT-FACT path, which
        // is where §33.5 put it — the streak there reads the level. It used to
        // be shown on the rating path because both paths read the level then;
        // now the rating path counts the INTENT (the second half of this test),
        // and the fact path is the one that still holds the original claim.
        var state = seeded(0)
        state.sub[.pull] = 2
        let session = Engine.generateSession(state)
        let pull = try XCTUnwrap(session.exercises.first { $0.pattern == .pull })
        let byFact = Engine.applyFeedback(state: state, session: session, result: .plan,
                                          overrides: [.pull: max(0, pull.load - 3)])
        XCTAssertEqual(byFact.levels[.pull], 0, "there is nowhere below zero to go")
        XCTAssertEqual(byFact.sub[.pull] ?? 0, 0, "the sub-steps go")
        XCTAssertEqual(byFact.failStreak[.pull], 0, "but it is not an underperformance")

        // The rating path, by contrast, counts the intent — and must, or on a
        // block floor "hard" would be an inert tap: no streak, no deload, no
        // way out of a variation that is beyond its owner (§34.2).
        state.lessRun = EngineConfig.lessRunToGlobal    // session-wide delta (§19.2)
        let byRating = tap(state, .less)
        XCTAssertEqual(byRating.levels[.pull], 0, "the level still cannot go below zero")
        XCTAssertEqual(byRating.sub[.pull] ?? 0, 1, "one sub-step is given back")
        XCTAssertEqual(byRating.failStreak[.pull], 1, "and the intent to descend counts")
    }

    // MARK: - The gate takes pairs

    /// A descent from `(L, sub>0)` to `(L, 0)` is legal and no harder by
    /// construction: the base dose is the same number and the total falls.
    func testSheddingSubStepsAlwaysPassesTheGate() {
        for p in Pattern.allCases {
            for level in 0...EngineConfig.levelMax where !Level.subDisabled(at: level) {
                for sub in 1..<Level.decode(level).sets {
                    XCTAssertTrue(Level.noHarder(pattern: p, from: level, to: level,
                                                 fromSub: sub, toSub: 0, fromCut: 0, toCut: 0),
                                  "\(p) L\(level).\(sub) → L\(level).0 must pass")
                    XCTAssertLessThan(Level.work(pattern: p, level: level, sub: 0, cut: 0).total,
                                      Level.work(pattern: p, level: level, sub: sub, cut: 0).total,
                                      "\(p) L\(level): shedding sub-steps is less work")
                }
            }
        }
    }

    /// At `sub == 0` on both sides the gate is the v2.21 gate, unchanged.
    func testTheGateIsUnchangedAtSubZero() {
        for p in Pattern.allCases {
            for from in 0...EngineConfig.levelMax {
                for to in 0...EngineConfig.levelMax {
                    XCTAssertEqual(Level.noHarder(pattern: p, from: from, to: to, fromCut: 0, toCut: 0),
                                   Level.noHarder(pattern: p, from: from, to: to,
                                                  fromSub: 0, toSub: 0, fromCut: 0, toCut: 0),
                                   "\(p) \(from) → \(to)")
                }
            }
        }
    }

    // MARK: - The weekly window is free for an honest rhythm (§28.5)

    /// The property §28.5 was built on survives the change of unit verbatim:
    /// three "plan" sessions a week are three sub-steps, exactly the slow
    /// budget, where three sessions used to be three levels.
    func testTheHonestThreeAWeekRhythmStillCostsNothing() {
        func run(gapDays: Double?) -> [Pattern: Int] {
            var s = EngineState.initial
            for _ in 0..<36 {
                s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                         result: .plan, gapDays: gapDays)
            }
            return Pattern.allCases.reduce(into: [:]) { acc, p in
                acc[p] = Level.ordinal(s.position(p))
            }
        }
        XCTAssertEqual(run(gapDays: 7.0 / 3.0), run(gapDays: nil),
                       "with the signal and without it — the same positions")
    }

    // SNIPPED v2.26 (§37.0): two tests that stood on mechanisms this wave
    // removes — a legacy freeze expiring on schedule, and the uniform plan the
    // "I was sick" lens showed. Neither has a field to read any more.
    //
    // The sub-step itself — what this suite is about — is untouched.
}
