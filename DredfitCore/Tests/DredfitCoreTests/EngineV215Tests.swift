//
//  EngineV215Tests.swift
//  DredfitCoreTests
//
//  Engine v2.15 (spec §26, issues #137/#130): the weak link. On a plateau the
//  one-tap trainee failed most of his sessions, and the §19.1 aim — "the
//  highest level in the session" — reached the weak link zero times out of 62
//  failing appearances: the weak link is by definition the LOWER one, so the
//  delta kept grinding down the movements that were fine. And a from-zero
//  calibration could put half the body on the neighbouring tier's top in a
//  single session, which §19.1 then untangled one step at a time.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV215Tests: XCTestCase {

    private func seeded(_ level: Int, _ over: [Pattern: Int] = [:]) -> EngineState {
        var s = EngineState.initial
        for p in Pattern.allCases { s.levels[p] = level }
        for (p, v) in over { s.levels[p] = v }
        return s
    }

    private func tap(_ state: EngineState, _ result: FeedbackResult) -> EngineState {
        Engine.applyFeedback(state: state, session: Engine.generateSession(state), result: result)
    }

    // MARK: - §26.1 The appearance window

    func testTheWindowCountsAppearancesNotSessions() {
        var state = seeded(20)
        var seen: [Pattern: Int] = [:]
        for _ in 0..<EngineConfig.chronicWindow {
            for ex in Engine.generateSession(state).exercises {
                seen[ex.pattern, default: 0] += 1
            }
            state = tap(state, .less)
        }
        for p in Pattern.allCases {
            XCTAssertEqual(state.chronicHits(p), min(seen[p] ?? 0, EngineConfig.chronicWindow),
                           "\(p): the mask counts its own appearances")
            XCTAssertLessThanOrEqual(state.lessHist[p] ?? 0, EngineState.chronicMaskMax)
        }
    }

    func testANamedLessDoesNotFillTheWindow() throws {
        let state = seeded(20)
        let session = Engine.generateSession(state)
        let target = try XCTUnwrap(session.exercises.first).pattern
        let after = Engine.applyFeedback(state: state, session: session, result: .less,
                                         pinned: [target])
        XCTAssertEqual(after.lessHist[target] ?? 0, 0,
                       "a named less is already addressed — the window is for silence")
    }

    func testSuccessfulAppearancesPushTheWindowOut() {
        var state = seeded(20)
        for _ in 0..<3 { state = tap(state, .less) }
        XCTAssertFalse(state.lessHist.isEmpty)
        for _ in 0..<(2 * EngineConfig.stepsPerTier) { state = tap(state, .plan) }
        XCTAssertTrue(state.lessHist.isEmpty, "the window ages out on its own")
    }

    // MARK: - §26.1 The aim finally reaches the weak link

    func testTheAimReachesTheWeakLinkEvenThoughItIsTheLowest() {
        var caps: [Pattern: Int] = [:]
        for p in Pattern.allCases { caps[p] = 20 }
        caps[.pushV] = 8
        var state = seeded(20)
        var aimHitWeak = 0
        for _ in 0..<100 {
            let session = Engine.generateSession(state)
            let failing = session.exercises.contains { (state.levels[$0.pattern] ?? 0) > (caps[$0.pattern] ?? 0) }
            let before = state.levels[.pushV] ?? 0
            state = Engine.applyFeedback(state: state, session: session,
                                         result: failing ? .less : .plan)
            if session.exercises.contains(where: { $0.pattern == .pushV }),
               (state.levels[.pushV] ?? 0) < before { aimHitWeak += 1 }
        }
        XCTAssertGreaterThan(aimHitWeak, 0, "the aim used to reach it 0 times out of 62")
        XCTAssertLessThanOrEqual(state.levels[.pushV] ?? 0, 9,
                                 "the weak link settles at its own capacity")
        let healthy = Pattern.ordered.filter { $0 != .pushV }
        let worst = healthy.map { state.levels[$0] ?? 0 }.min() ?? 0
        XCTAssertGreaterThanOrEqual(worst, 14,
                                    "the healthy movements stop being the lightning rod")
    }

    func testAChronicAimTakesADoubleStepAndAPlainOneDoesNot() {
        // A plain "less": one movement moves by one.
        let state = seeded(20)
        let session = Engine.generateSession(state)
        let after = Engine.applyFeedback(state: state, session: session, result: .less)
        let moved = session.exercises.filter {
            (after.levels[$0.pattern] ?? 0) < (state.levels[$0.pattern] ?? 0)
        }
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual((state.levels[moved[0].pattern] ?? 0) - (after.levels[moved[0].pattern] ?? 0),
                       -EngineConfig.deltaLess)
    }

    func testTheDoubleStepLandsOnTheMovementThatKeepsFailing() {
        // The signal lives where the programme as a whole is fine and ONE
        // movement keeps failing: sessions carrying it are rated "less",
        // sessions without it are rated "plan" — so the §19.2 run never builds
        // up and the window fills for that movement alone.
        var state = seeded(20)
        var doubleSteps = 0, singleSteps = 0
        for _ in 0..<40 {
            let session = Engine.generateSession(state)
            let carriesWeak = session.exercises.contains { $0.pattern == .pushV }
            let before = state.levels
            state = Engine.applyFeedback(state: state, session: session,
                                         result: carriesWeak ? .less : .plan)
            let drop = (before[.pushV] ?? 0) - (state.levels[.pushV] ?? 0)
            if drop == -EngineConfig.chronicStep { doubleSteps += 1 }
            if drop == -EngineConfig.deltaLess { singleSteps += 1 }
        }
        XCTAssertGreaterThan(doubleSteps, 0, "the chronic aim moves by two")
        XCTAssertGreaterThan(doubleSteps, singleSteps,
                             "once the window is full the double step is the norm")
    }

    func testTheSplitPullSlotIsExcludedSoThePeriodTwoLockStaysOpen() {
        var state = EngineState.initial
        state.hasBar = true
        for k in 0..<96 {
            state = tap(state, k.isMultiple(of: 2) ? .more : .less)
        }
        XCTAssertGreaterThan(state.levels[.pullBar] ?? 0, 0,
                             "v2.10 opened this lock; the chronic signal must not latch it again")
    }

    func testTheDescentWhenEverythingIsTooHardDidNotSlowDown() {
        for (capacity, limit) in [(5, 20), (12, 12)] {
            var state = seeded(20)
            var sessions = 0
            for i in 0..<60 {
                let session = Engine.generateSession(state)
                if !session.exercises.contains(where: { (state.levels[$0.pattern] ?? 0) > capacity }) { break }
                state = Engine.applyFeedback(state: state, session: session, result: .less)
                sessions = i + 1
            }
            XCTAssertLessThanOrEqual(sessions, limit,
                                     "capacity \(capacity): the §19.2 descent must keep its pace")
        }
    }

    // MARK: - §26.2 The humble group landing

    func testAGroupCalibrationLandsOnItsOwnTiersTop() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        var brag: [Pattern: Int] = [:]
        for ex in session.exercises { brag[ex.pattern] = ex.load + 20 }
        let after = Engine.applyFeedback(state: state, session: session, result: .more,
                                         overrides: brag)
        for ex in session.exercises {
            XCTAssertLessThanOrEqual(after.levels[ex.pattern] ?? 0, EngineConfig.stepsPerTier - 1,
                                     "\(ex.pattern) went past its own tier")
        }
    }

    func testASingleCalibrationIsUntouched() throws {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        let ex = try XCTUnwrap(session.exercises.first { !EngineConfig.isSlowTissue($0.pattern) })
        let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [ex.pattern: ex.load + 20])
        XCTAssertEqual(after.levels[ex.pattern], 2 * EngineConfig.stepsPerTier - 1,
                       "one honest calibration still reaches the neighbouring tier's top")
    }

    func testTheOverconfidentNoviceStopsCollectingDeloads() {
        // Session 1 is bragged facts; from then on he answers by capability.
        let caps: [Pattern: Int] = [.squat: 9, .pushH: 7, .hinge: 7, .pull: 6, .pushV: 7,
                                    .lunge: 6, .coreAntiExt: 5, .coreRot: 5, .calf: 6, .pullBar: 0]
        let brag: [Pattern: Int] = [.squat: 30, .pushH: 25, .hinge: 25, .pull: 18,
                                    .pushV: 30, .lunge: 20]
        var state = EngineState.initial
        var deloads = 0
        for i in 0..<24 {
            let session = Engine.generateSession(state)
            let before = state.levels
            if i == 0 {
                var facts: [Pattern: Int] = [:]
                for ex in session.exercises where brag[ex.pattern] != nil {
                    facts[ex.pattern] = brag[ex.pattern]
                }
                state = Engine.applyFeedback(state: state, session: session, result: .more,
                                             overrides: facts)
            } else {
                let over = session.exercises.contains { (state.levels[$0.pattern] ?? 0) > (caps[$0.pattern] ?? 0) + 1 }
                state = Engine.applyFeedback(state: state, session: session,
                                             result: over ? .less : .plan)
            }
            for p in Pattern.allCases where (before[p] ?? 0) - (state.levels[p] ?? 0) >= 3 { deloads += 1 }
        }
        XCTAssertEqual(deloads, 0, "the hangover used to cost six deloads")
    }

    // MARK: - Serialization

    func testTheWindowSurvivesADecayAndIsClearedByAComeback() {
        var state = seeded(20)
        for _ in 0..<3 { state = tap(state, .less) }
        XCTAssertFalse(Engine.applySilentDecay(state: state, gapDays: 10).lessHist.isEmpty,
                       "a silent decay barely moves the levels and keeps the window")
        XCTAssertTrue(Engine.applyComeback(state: state, gapDays: 30).lessHist.isEmpty,
                      "a comeback rebuilds the levels — the window goes with them")
    }

    func testACorruptOrLegacyWindowDecodesCleanly() throws {
        let legacy = """
        {"counter":3,"levels":["squat",5],"failStreak":["squat",0]}
        """
        let old = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertTrue(old.lessHist.isEmpty, "a file written before this decodes to an empty window")

        let dirty = """
        {"counter":3,"levels":["squat",5],"failStreak":["squat",0],
         "lessHist":["squat",999,"pull",-3,"calf",2]}
        """
        let healed = try JSONDecoder().decode(EngineState.self, from: Data(dirty.utf8))
        XCTAssertEqual(healed.lessHist[.squat], EngineState.chronicMaskMax)
        XCTAssertNil(healed.lessHist[.pull])
        XCTAssertEqual(healed.lessHist[.calf], 2)
    }
}
