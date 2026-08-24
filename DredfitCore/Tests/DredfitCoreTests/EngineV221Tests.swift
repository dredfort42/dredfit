//
//  DredfitCoreTests
//
//  Hold steps go relative.
//
//  `holdStepSec = 5` was the same five seconds everywhere on the scale. On a
//  base of 10 s — the floor of tier 4 — that is +50 % for ONE rung, and under
// the ceiling of two rungs up to +67 % in a single session:
//  `coreAntiExt` L8→10 turned a 3×15 s plank into 3×25 s. No source writes
//  progression as an absolute increment; ACSM 2009 (Med Sci Sports Exerc
//  41(3):687–708) says "a 2–10 % increase in load". This is the "do no harm"
//  rung of the ladder, so the step became a share of the dose you stand on.
//
//  Three things are pinned here: the ladders themselves (literal tables, so
//  the rounding mode of a platform never enters the encoding), the inversion
//  by table lookup with ties settling DOWN, and the window of "the plan was
//  met" being one REAL rung wide rather than five seconds.
//
//  One thing deliberately deviates from the wave's brief: past the ladder's
//  edge the inversion does NOT clamp to rung 0 / rung 7. Clamping was tried
// and measured — it re-breaks monotonicity at the top rung of every
//  tier and every band (plank L7, plan 39 s: a fact of 42 gave level 8 while
// an honest 43 gave 7), which is the exact defect #139 and exist for.
//  The edge a result settles on is the edge of the SCALE, not of a tier.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV221Tests: XCTestCase {

    /// One (pattern, level) cell whose unit is seconds, with the level already
    /// decoded — the shape every sweep below walks.
    private struct HoldCell {
        let pattern: Pattern
        let level: Int
        let plan: LevelDecoded

        /// The ladder the plan's dose came off, and the rung it stands on.
        var ladder: [Int] { Level.ladder(tier: plan.tier, sets: plan.sets) }
        var rung: Int { level % EngineConfig.stepsPerTier }
    }

    /// Every such cell: `coreAntiExt` and `coreRot` on the whole scale,
    /// `pullBar` on tier 1 alone (the hang).
    private var holdCells: [HoldCell] {
        var cells: [HoldCell] = []
        for pattern in Pattern.allCases {
            let lib = ExerciseLibrary.entry(for: pattern)
            for level in 0...EngineConfig.levelMax {
                let d = Level.decode(level)
                if lib.unit(forTier: d.tier) == .hold {
                    cells.append(HoldCell(pattern: pattern, level: level, plan: d))
                }
            }
        }
        return cells
    }

    private struct NamedLadder {
        let name: String
        let rungs: [Int]
    }

    private var tierLadders: [NamedLadder] {
        (1...EngineConfig.tiers)
            .map { NamedLadder(name: "tier \($0)", rungs: EngineConfig.holdLadder[$0] ?? []) }
    }

    private var bandLadders: [NamedLadder] {
        EngineConfig.holdLadderBand.keys.sorted()
            .map { NamedLadder(name: "band \($0)", rungs: EngineConfig.holdLadderBand[$0] ?? []) }
    }

    private func seeded(_ level: Int, _ overrides: [Pattern: Int] = [:],
                        hasBar: Bool = false) -> EngineState {
        var s = EngineState.initial
        s.hasBar = hasBar
        for p in Pattern.allCases { s.levels[p] = level }
        for (p, l) in overrides { s.levels[p] = l }
        return s
    }

    private struct Staged {
        let state: EngineState
        let workout: Session
        let exercise: SessionExercise
    }

    /// The first session of the rotation carries no static movement at all —
    /// plank, side plank and the hang arrive from the second onwards. Any
    /// sweep that stands on `counter = 0` never sees a hold.
    private func staged(_ pattern: Pattern, at level: Int) -> Staged? {
        var seed = pattern == .pull
            ? seeded(0, [.pull: level])
            : seeded(0, [pattern: level, .pull: EngineConfig.levelMax])
        seed.hasBar = pattern == .pullBar
        for counter in 0..<EngineConfig.stepsPerTier {
            seed.counter = counter
            let workout = Engine.generateSession(seed)
            if let ex = workout.exercises.first(where: { $0.pattern == pattern }) {
                return Staged(state: seed, workout: workout, exercise: ex)
            }
        }
        return nil
    }

    // MARK: - (a) The ladders themselves

    func testEveryLadderIsStrictlyIncreasing() {
        for ladder in tierLadders + bandLadders {
            XCTAssertEqual(ladder.rungs.count, EngineConfig.stepsPerTier, "\(ladder.name) count")
            for i in 0..<(ladder.rungs.count - 1) {
                XCTAssertGreaterThan(ladder.rungs[i + 1], ladder.rungs[i], "\(ladder.name) rung \(i)")
            }
        }
    }

    /// The worst rung inside a tier is exactly 2/15 — tiers 2 and 3, 15 → 17 s,
    /// 13.33 %. The bound is a FRACTION rather than a floating-point percent:
    /// the comparison is integral and platform-independent, like the tables.
    func testARungInsideATierCostsAtMostTwoFifteenths() {
        for ladder in tierLadders {
            let rungs = ladder.rungs
            for i in 0..<(rungs.count - 1) {
                XCTAssertLessThanOrEqual((rungs[i + 1] - rungs[i]) * 15, rungs[i] * 2,
                                         "\(ladder.name) rung \(i): \(rungs[i]) → \(rungs[i + 1])")
            }
        }
    }

    /// The set bands do not follow the relative formula — their step is a
    /// whole 3 s — so the band-4 door (20 → 23 s) is 3/20 = 15 %, the widest
    /// rung on the whole scale. It sits where the ceiling is one rung,
    /// so nothing takes more than it in a session.
    func testARungInsideABandCostsAtMostThreeTwentieths() {
        for ladder in bandLadders {
            let rungs = ladder.rungs
            for i in 0..<(rungs.count - 1) {
                XCTAssertLessThanOrEqual((rungs[i + 1] - rungs[i]) * 20, rungs[i] * 3,
                                         "\(ladder.name) rung \(i): \(rungs[i]) → \(rungs[i + 1])")
            }
        }
    }

    /// Two rungs are only ever taken where the cell hands them out. On
    /// tier 4 and in every band the ceiling is one, so the band-4 30 % over two
    /// rungs is unreachable in a session by construction.
    func testASessionUnderACapOfTwoCostsAtMostFourFifteenths() {
        var checked = 0
        for cell in holdCells {
            let cap = EngineConfig.maxUp(pattern: cell.pattern, tier: cell.plan.tier)
            let rungs = cell.ladder
            guard cap >= 2, let i = rungs.firstIndex(of: cell.plan.hold), i + cap < rungs.count
            else { continue }
            XCTAssertLessThanOrEqual((rungs[i + 2] - rungs[i]) * 15, rungs[i] * 4,
                                     "\(cell.pattern) tier \(cell.plan.tier) rung \(i)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "the cap-of-two sweep must actually run")
    }

    /// The defect the wave exists for: the old fixed 5 s on tier 4's floor.
    func testTierFourNoLongerJumpsByHalfItsDose() {
        let tier4 = EngineConfig.holdLadder[4] ?? []
        XCTAssertEqual(tier4[1] - tier4[0], 1, "one rung of tier 4 costs 1 s, not 5 (+50 %)")
        XCTAssertLessThanOrEqual((tier4[2] - tier4[0]) * 100, tier4[0] * 27,
                                 "two rungs of tier 4 cost at most 27 % (was +67 %)")
    }

    /// The tables reproduce from their derivation, half rounded up. The
    /// rounding is done on INTEGERS here too — inside the engine there must be
    /// no rounding mode at all, which is why the tables are literal.
    func testTheLaddersReproduceFromTheirDerivation() {
        for tier in 1...EngineConfig.tiers {
            let ladder = EngineConfig.holdLadder[tier] ?? []
            for i in 0..<(ladder.count - 1) {
                let want = ladder[i] + max(1, (2 * ladder[i] + 10) / 20)
                XCTAssertEqual(ladder[i + 1], want, "tier \(tier) rung \(i)")
            }
        }
        // The tier starts survive from; only the step moved.
        XCTAssertEqual([1, 2, 3, 4].map { EngineConfig.holdLadder[$0]?.first }, [20, 15, 15, 10])
        // The tops shrank — that is the part a person actually feels.
        XCTAssertEqual([1, 2, 3, 4].map { EngineConfig.holdLadder[$0]?.last }, [39, 31, 31, 19])
    }

    /// The band ladders are derived, not written twice: editing a band stays a
    /// change of NUMBER rather than of structure.
    func testTheBandLaddersDeriveFromTheirStartAndStep() {
        for band in EngineConfig.holdLadderBand.keys.sorted() {
            let start = EngineConfig.holdStartBand[band]
            let step = EngineConfig.holdStepBand[band]
            for i in 0..<EngineConfig.stepsPerTier {
                XCTAssertEqual(EngineConfig.holdLadderBand[band]?[i], start! + i * step!,
                               "band \(band) rung \(i)")
            }
        }
        XCTAssertEqual(EngineConfig.holdStartBand, [4: 20, 5: 24], "band starts dropped to 20/24")
        XCTAssertEqual(EngineConfig.holdStepBand, [4: 3, 5: 3], "the band step stayed 3 s")
        XCTAssertEqual(Level.ladder(tier: EngineConfig.tiers, sets: 4),
                       EngineConfig.holdLadderBand[4], "a band outranks its tier")
        XCTAssertEqual(Level.ladder(tier: EngineConfig.tiers, sets: EngineConfig.setsBase),
                       EngineConfig.holdLadder[EngineConfig.tiers], "base sets stay the tier's")
    }

    // MARK: - (b) The L31 → L32 door

    /// The band no longer tears the continuity of the static dose. Tier 4 tops
    /// out at 19 s and band 4 opens at 20: the dose PER SET stays put (+5 %),
    /// and the total grows because a fourth set arrives.
    func testEnteringTheSetBandNoLongerDoublesTheStaticWork() {
        func staticSum(_ level: Int) -> Int {
            let d = Level.decode(level)
            return d.sets * d.hold
        }
        XCTAssertEqual(staticSum(31), 57)
        XCTAssertEqual(staticSum(32), 80)
        XCTAssertLessThanOrEqual(staticSum(32) * 100, staticSum(31) * 145,
                                 "the band-4 door costs at most 45 % of static work")
        // The old 25 s start would have made it 57 → 100 s, +75 % for ONE
        // level: it was measured off tier 4's former top of 45 s.
        XCTAssertGreaterThan(4 * 25 * 100, staticSum(31) * 145,
                             "a 25 s band start really did miss the bound — 20 is not arbitrary")
        XCTAssertEqual(Level.decode(32).hold - Level.decode(31).hold, 1, "19 → 20 s per set")
        // The second band door stays an unload, as it always was.
        XCTAssertLessThan(staticSum(40), staticSum(39))
        XCTAssertGreaterThanOrEqual(staticSum(40) * 100, staticSum(39) * 70)
        // Tier transitions stay unloads too.
        for level in [8, 16, 24] {
            XCTAssertLessThan(staticSum(level), staticSum(level - 1), "tier door at L\(level)")
        }
    }

    // MARK: - (c) The inversion is table-exact

    func testAFactEqualToARungInvertsToExactlyThatLevel() {
        var cells = 0
        for cell in holdCells {
            let dose = cell.ladder[cell.rung]
            XCTAssertEqual(cell.plan.hold, dose, "\(cell.pattern) L\(cell.level) dose is a rung")
            XCTAssertEqual(
                Level.fromActual(pattern: cell.pattern, tier: cell.plan.tier,
                                 sets: cell.plan.sets, actual: dose),
                cell.level, "\(cell.pattern) L\(cell.level): \(dose) s must invert back")
            cells += 1
        }
        // 104 cells: two patterns across all 48 levels, plus the hang's eight.
        XCTAssertEqual(cells, 2 * (EngineConfig.levelMax + 1) + EngineConfig.stepsPerTier)
    }

    // MARK: - (d) Ties settle DOWN

    func testATieBetweenTwoRungsSettlesOnTheLowerOne() {
        for cell in holdCells {
            let rungs = cell.ladder, here = cell.rung
            guard here + 1 < rungs.count else { continue }
            let gap = rungs[here + 1] - rungs[here]
            func inverted(_ actual: Int) -> Int {
                Level.fromActual(pattern: cell.pattern, tier: cell.plan.tier,
                                 sets: cell.plan.sets, actual: actual)
            }
            if gap.isMultiple(of: 2) {
                XCTAssertEqual(inverted(rungs[here] + gap / 2), cell.level,
                               "\(cell.pattern) L\(cell.level): dead centre must settle down")
            }
            XCTAssertEqual(inverted(rungs[here] + gap / 2 + 1), cell.level + 1,
                           "\(cell.pattern) L\(cell.level): past centre is the next rung")
            XCTAssertLessThanOrEqual(inverted(rungs[here] - 1), cell.level,
                                     "\(cell.pattern) L\(cell.level): a second short never grows")
        }
    }

    // MARK: - (e) The corridor's edges stay finite and in range

    func testTheInputCorridorEdgesStayOnTheScale() {
        for cell in holdCells {
            for actual in [0, 1, 5, 90, 900] {
                let got = Level.fromActual(pattern: cell.pattern, tier: cell.plan.tier,
                                           sets: cell.plan.sets, actual: actual)
                XCTAssertTrue((0...EngineConfig.levelMax).contains(got),
                              "\(cell.pattern) L\(cell.level), fact \(actual) s → \(got)")
            }
        }
    }

    func testACorridorEdgeReportedThroughFeedbackStaysOnTheScale() throws {
        for pattern in [Pattern.coreAntiExt, .coreRot, .pullBar] {
            for level in [0, 7, 14, 21, 28, 35, 42, 47] {
                guard let run = staged(pattern, at: level) else { continue }
                for actual in [5, 90] {
                    let got = Engine.applyFeedback(state: run.state, session: run.workout,
                                                   result: .plan,
                                                   overrides: [pattern: actual]).levels[pattern] ?? -1
                    XCTAssertTrue((0...EngineConfig.levelMax).contains(got),
                                  "\(pattern) L\(level), report \(actual) s → \(got)")
                }
            }
        }
    }

    // MARK: - (f) The window is one real rung

    func testTheMetPlanWindowIsTheLocalRungOfTheLadder() {
        for cell in holdCells {
            let rungs = cell.ladder, here = cell.rung
            let want = here + 1 < rungs.count
                ? rungs[here + 1] - rungs[here]
                : rungs[here] - rungs[here - 1]
            let got = Level.step(of: .hold, tier: cell.plan.tier,
                                 sets: cell.plan.sets, load: cell.plan.hold)
            XCTAssertEqual(got, want, "\(cell.pattern) L\(cell.level) window")
            XCTAssertTrue((1...4).contains(got), "\(cell.pattern) L\(cell.level): a rung is 1...4 s")
        }
        XCTAssertEqual(Level.step(of: .reps, tier: 1, sets: EngineConfig.setsBase, load: 8), 1,
                       "for reps the step is still one and the window is the old equality")
    }

    /// The property #139 is about, on the ladder and on the statics the old
    /// sweep never reached: the level must never fall as the honest fact grows.
    /// This is the check that fails if the inversion clamps at a tier's edge.
    func testTheLevelStaysMonotoneInTheFactAcrossTheStatics() throws {
        for pattern in [Pattern.coreAntiExt, .coreRot, .pullBar] {
            for level in 0...EngineConfig.levelMax {
                guard let run = staged(pattern, at: level),
                      run.exercise.unit == LoadUnit.hold else { continue }
                var previous = -1
                for actual in 0...(run.exercise.load + 15) {
                    let got = Engine.applyFeedback(state: run.state, session: run.workout,
                                                   result: .plan,
                                                   overrides: [pattern: actual]).levels[pattern] ?? 0
                    XCTAssertGreaterThanOrEqual(
                        got, previous,
                        "\(pattern) L\(level) plan \(run.exercise.load)s: fact \(actual) fell back")
                    previous = got
                }
            }
        }
    }

    // MARK: - The rounding this wave uncovered in the port

    /// `estimatedTotalMin` used to be `(x * 10).rounded() / 10`, which is not
    /// what the reference's `toFixed(1)` does. Odd second counts in the statics
    /// made the difference reachable and lit up eighteen golden steps at once.
    func testTheDurationRoundsExactlyAsTheReferenceDoes() {
        // 2079 s / 60 is 34.649999999999999 as a double — under 34.65, so the
        // nearest tenth is 34.6. Scaling by ten first rounds it up to 346.5.
        XCTAssertEqual(Engine.roundedToTenths(2079.0 / 60), 34.6)
        // 2115 s / 60 is exactly 35.25 — a real tie, and toFixed takes the
        // larger number. Round-half-to-even would take 35.2.
        XCTAssertEqual(Engine.roundedToTenths(2115.0 / 60), 35.3)
        XCTAssertEqual(Engine.roundedToTenths(2205.0 / 60), 36.8)   // exactly 36.75
        XCTAssertEqual(Engine.roundedToTenths(1980.0 / 60), 33.0)   // exactly 33
        XCTAssertEqual(Engine.roundedToTenths(1990.0 / 60), 33.2)   // 33.1666…
    }

    // MARK: - (g) No dead constants left behind

    /// `holdStepSec` and `holdStart` are gone; the app-side corridor snaps
    /// holds to a whole second, because on a five-second grid only 13 of the
    /// scale's 48 rungs can be typed at all.
    func testTheLaddersAreTheOnlySourceOfAStaticDose() {
        for level in 0...EngineConfig.levelMax {
            let d = Level.decode(level)
            XCTAssertEqual(d.hold,
                           Level.ladder(tier: d.tier, sets: d.sets)[level % EngineConfig.stepsPerTier],
                           "L=\(level)")
        }
    }
}
