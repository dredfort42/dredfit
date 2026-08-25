//
//  The skip that happens DURING the workout.
//
//  The wave took away both handles that stood BEFORE the session and moved the
//  decision inside it. The `cut` axis did not move; the gesture that writes it
//  did, and so did the MOMENT — which turned out to be part of the contract.
//

import XCTest
@testable import DredfitCore

// AppKit's QuickDraw ships a `Pattern` too, and it wins in a signature.
private typealias Pattern = DredfitCore.Pattern

final class EngineV227Tests: XCTestCase {

    private func seeded(_ level: Int, bar: Bool = true) -> EngineState {
        var s = EngineState.initial
        for p in Pattern.allCases { s.levels[p] = level }
        s.hasBar = bar
        return s
    }

    /// Rotation does not show every movement every session, so "the next
    /// showing" is the nearest session that contains the movement at all.
    private func nextShown(_ state: EngineState, _ p: Pattern) -> SessionExercise? {
        var probe = state
        for _ in 0...EngineConfig.stepsPerTier {
            if let ex = Engine.generateSession(probe).exercises.first(where: { $0.pattern == p }) {
                return ex
            }
            probe.counter += 1
        }
        return nil
    }

    // MARK: - Rule 1: the order

    /// Feedback first, then the cut — and the reverse order loses the skip.
    ///
    /// BOTH directions are asserted, and the second is the point. A test that
    /// only knows the right order stays green when a caller swaps them, which
    /// is precisely the regression this rule exists to prevent: on a session
    /// the person completed, `applyFeedback` calls `riseBy`, `riseBy` hands a
    /// set back instead of raising the level, and the cut written in advance
    /// is eaten by the very event that should have returned it later.
    ///
    /// If the engine ever makes the order irrelevant, this test must go RED
    /// and force the rule to be rewritten — not stay quietly green.
    func testTheSkipMustLandAfterTheFeedbackAndIsLostBeforeIt() {
        var cells = 0
        for level in 0...EngineConfig.levelMax {
            guard Level.cutMax(level: level) > 0 else { continue }
            for bar in [false, true] {
                for p in Pattern.allCases {
                    let base = seeded(level, bar: bar)
                    guard Engine.generateSession(base).exercises.contains(where: { $0.pattern == p })
                    else { continue }
                    cells += 1

                    // RIGHT: through the entry point that owns the order.
                    let right = Engine.applyFeedback(
                        state: base, session: Engine.generateSession(base), result: .plan,
                        overrides: [:], skipped: [], setsSkipped: [p: 1], gapDays: 7.0 / 3.0)
                    XCTAssertEqual(right.cutOf(p), 1,
                                   "L\(level) bar=\(bar) \(p): the right order lost the skip")

                    // WRONG: the cut written in advance, by hand.
                    let early = Engine.setCut(state: base, pattern: p, cut: base.cutOf(p) + 1)
                    let wrong = Engine.applyFeedback(
                        state: early, session: Engine.generateSession(early), result: .plan,
                        overrides: [:], skipped: [], gapDays: 7.0 / 3.0)
                    XCTAssertEqual(wrong.cutOf(p), 0,
                                   "L\(level) bar=\(bar) \(p): the wrong order SUDDENLY kept the "
                                   + "skip — §38.2 rule 1 no longer describes the engine")
                }
            }
        }
        XCTAssertGreaterThan(cells, 500, "the order sweep covered \(cells) cells")
    }

    /// The loss happens on SUCCESSFUL sessions and not on honest-hard ones —
    /// which is why the regression survives review. The session a developer
    /// reaches for by hand is the one where the order is harmless.
    func testTheOrderIsHarmlessOnlyWhenTheSessionWasHard() {
        for result in [FeedbackResult.plan, .more, .less] {
            var cells = 0, lost = 0
            for level in 0...EngineConfig.levelMax {
                guard Level.cutMax(level: level) > 0 else { continue }
                for p in Pattern.allCases {
                    var base = seeded(level)
                    guard Engine.generateSession(base).exercises.contains(where: { $0.pattern == p })
                    else { continue }
                    cells += 1
                    base.lessRun = EngineConfig.lessRunToGlobal
                    let early = Engine.setCut(state: base, pattern: p, cut: base.cutOf(p) + 1)
                    let after = Engine.applyFeedback(
                        state: early, session: Engine.generateSession(early), result: result,
                        overrides: [:], skipped: [], gapDays: 7.0 / 3.0)
                    if after.cutOf(p) == 0 { lost += 1 }
                }
            }
            XCTAssertEqual(lost, result == .less ? 0 : cells,
                           "on \(result) the wrong order lost \(lost) of \(cells)")
        }
    }

    /// The two worked examples from the spec, plans included.
    func testTheSpecsTwoExamplesReproduce() throws {
        for (level, before, after) in [(24, "3×4", "2×4"), (40, "5×8", "4×8")] {
            let base = seeded(level)
            let shown = try XCTUnwrap(nextShown(base, .squat))
            XCTAssertEqual("\(shown.sets)×\(shown.load)", before, "L\(level) as shown")

            let right = Engine.applyFeedback(
                state: base, session: Engine.generateSession(base), result: .plan,
                overrides: [:], skipped: [], setsSkipped: [.squat: 1], gapDays: 7.0 / 3.0)
            XCTAssertEqual(right.cutOf(.squat), 1, "L\(level) right order cut")
            let rShown = try XCTUnwrap(nextShown(right, .squat))
            XCTAssertEqual("\(rShown.sets)×\(rShown.load)", after, "L\(level) right order showing")

            let early = Engine.setCut(state: base, pattern: .squat, cut: 1)
            let wrong = Engine.applyFeedback(
                state: early, session: Engine.generateSession(early), result: .plan,
                overrides: [:], skipped: [], gapDays: 7.0 / 3.0)
            XCTAssertEqual(wrong.cutOf(.squat), 0, "L\(level) wrong order cut")
            let wShown = try XCTUnwrap(nextShown(wrong, .squat))
            XCTAssertEqual("\(wShown.sets)×\(wShown.load)", before,
                           "L\(level) wrong order: the skip was not lost after all")
        }
    }

    // MARK: - Rule 2: at the floor

    /// On the floor a skipped set is not a cut and not a missed dose.
    ///
    /// Both halves are asserted. That the skip moves nothing is the rule's
    /// CLAIM. That a fact of 0 would cost a whole tier is its REASON, and
    /// without it the rule reads as arbitrary: if 0 reps ever stopped costing
    /// a tier, rule 2 would have to be rewritten rather than quietly kept.
    func testOnTheFloorASkipMovesNeitherLevelNorCut() {
        var cells = 0, worstDrop = 0
        for level in 0...EngineConfig.levelMax {
            let top = Level.cutMax(level: level)
            guard top > 0 else { continue }
            for p in Pattern.allCases {
                var base = seeded(level)
                for q in Pattern.allCases {
                    base = Engine.setCut(state: base, pattern: q, cut: top)
                }
                let w = Engine.generateSession(base)
                guard let ex = w.exercises.first(where: { $0.pattern == p }) else { continue }
                cells += 1
                XCTAssertEqual(ex.sets, EngineConfig.setsFloor,
                               "L\(level) \(p): at the cut's stop the plan is not on the floor")

                let skipped = Engine.applyFeedback(state: base, session: w, result: .plan,
                                                   overrides: [:], skipped: [p],
                                                   gapDays: 7.0 / 3.0)
                XCTAssertEqual(skipped.levels[p], base.levels[p],
                               "L\(level) \(p): a skip on the floor moved the level")
                XCTAssertEqual(skipped.cutOf(p), base.cutOf(p),
                               "L\(level) \(p): a skip on the floor moved the cut")
                XCTAssertEqual(skipped.sub[p] ?? 0, base.sub[p] ?? 0,
                               "L\(level) \(p): a skip on the floor moved the sub-step")

                let zeroed = Engine.applyFeedback(state: base, session: w, result: .plan,
                                                  overrides: [p: 0], skipped: [],
                                                  gapDays: 7.0 / 3.0)
                worstDrop = max(worstDrop, (base.levels[p] ?? 0) - (zeroed.levels[p] ?? 0))
            }
        }
        XCTAssertGreaterThan(cells, 200, "the floor sweep covered \(cells) cells")
        XCTAssertGreaterThanOrEqual(worstDrop, EngineConfig.stepsPerTier,
                                    "a dose of 0 no longer costs even a tier (worst drop "
                                    + "\(worstDrop)) — the reason for rule 2 is gone")
    }

    /// The spec's worked example: on the floor at L24, a fact of 0 costs eight
    /// levels and a skipped exercise costs nothing.
    func testTheFloorExampleFromTheSpec() throws {
        var base = seeded(24)
        let top = Level.cutMax(level: 24)
        for q in Pattern.allCases { base = Engine.setCut(state: base, pattern: q, cut: top) }
        let w = Engine.generateSession(base)
        let ex = try XCTUnwrap(w.exercises.first(where: { $0.pattern == .squat }))
        XCTAssertEqual([ex.sets, ex.load], [2, 4], "on the floor at L24 the plan is 2×4")

        XCTAssertEqual(Engine.applyFeedback(state: base, session: w, result: .plan,
                                            overrides: [.squat: 0], skipped: [],
                                            gapDays: 7.0 / 3.0).levels[.squat], 16,
                       "a dose of 0 on the floor at L24 no longer lands on L16")
        XCTAssertEqual(Engine.applyFeedback(state: base, session: w, result: .plan,
                                            overrides: [:], skipped: [.squat],
                                            gapDays: 7.0 / 3.0).levels[.squat], 24,
                       "a skipped exercise on the floor moved the level")
    }

    // MARK: - Rule 3: the whole exercise

    /// "Skip the remaining sets": one tap instead of every set of a movement.
    ///
    /// The column pinned here is the one the spec's argument rests on and the
    /// one that reproduces — how many MOVEMENTS have to be skipped to fit into
    /// 45 minutes. The per-set column depends on the order the person
    /// takes sets off in and is not a single number; what IS true under any
    /// order is asserted instead: per-set costs strictly more taps.
    func testSkippingAWholeExerciseIsWhatMakesTheSessionFit() {
        let target = 45.0
        let dur = { (s: EngineState) in Engine.generateSession(s).estimatedTotalMin }
        for (level, full, exTaps) in [(24, 38.0, 0), (34, 55.3, 3), (40, 79.7, 4), (47, 94.3, 6)] {
            let base = seeded(level)
            let order = Engine.generateSession(base).exercises.map(\.pattern)
            XCTAssertEqual(dur(base), full, accuracy: 0.05, "L\(level) full plan")

            var state = base, taps = 0
            for p in order {
                if dur(state) <= target { break }
                let top = Level.cutMax(level: state.levels[p] ?? 0)
                if state.cutOf(p) >= top { continue }
                state = Engine.setCut(state: state, pattern: p, cut: top)
                taps += 1
            }
            XCTAssertEqual(taps, exTaps,
                           "L\(level): \(taps) exercise skips to reach \(Int(target)) min, "
                           + "the spec says \(exTaps) of \(order.count)")

            guard exTaps > 0 else { continue }
            var one = base, oneTaps = 0
            while dur(one) > target && oneTaps < 200 {
                var moved = false
                for p in order {
                    if dur(one) <= target { break }
                    let top = Level.cutMax(level: one.levels[p] ?? 0)
                    if one.cutOf(p) >= top { continue }
                    one = Engine.setCut(state: one, pattern: p, cut: one.cutOf(p) + 1)
                    oneTaps += 1; moved = true
                }
                if !moved { break }
            }
            XCTAssertGreaterThan(oneTaps, exTaps,
                                 "L\(level): \(oneTaps) per-set taps against \(exTaps) per "
                                 + "exercise — rule 3 saves nothing")
        }
    }

    /// The bottom of the axis: at L47 every movement skipped is 39.5 minutes,
    /// the number the spec announces, and everything stands on the floor.
    func testTheFloorOfTheWholeSessionIsTheAnnouncedOne() {
        var state = seeded(47)
        for p in Pattern.allCases {
            state = Engine.setCut(state: state, pattern: p,
                                  cut: Level.cutMax(level: state.levels[p] ?? 0))
        }
        XCTAssertEqual(Engine.generateSession(state).estimatedTotalMin, 39.5, accuracy: 0.05)
        for ex in Engine.generateSession(state).exercises {
            XCTAssertEqual(ex.sets, EngineConfig.setsFloor, "\(ex.pattern) is not on the floor")
        }
    }
}
