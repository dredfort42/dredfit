//
//  EngineV213Tests.swift
//  DredfitCoreTests
//
//  Engine v2.13 (spec §24, issues #132/#146): the sanitization wave. The
//  promise of §17.4 — "the plan is valid even with garbage in the state" —
//  had two holes. The reference still read a few containers raw, and this
//  port sanitized only on decode, so a corrupt store file produced unearned
//  deloads, a comeback landing above the scale, and — near Int's edge — a
//  process trap on every plan, in a crash loop the file quarantine could not
//  catch, because the decode itself had succeeded.
//
//  Every expectation here is the reference's own answer to the same input:
//  the two implementations were compared on 2,272 dirty cases with zero
//  divergences before these were written.
//

import XCTest
@testable import DredfitCore

final class EngineV213Tests: XCTestCase {

    /// A state that is valid except for whatever the caller breaks.
    private func seeded(level: Int = 20, hasBar: Bool = false) -> EngineState {
        var s = EngineState.initial
        s.hasBar = hasBar
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    // MARK: - The state heals on every entry (§24.1)

    func testALevelAboveTheScaleDoesNotBuyAnUnearnedDeload() {
        // 999 read as "the old level" made every honest session a shortfall:
        // the streak grew on a successful "plan" and rode into a deload.
        var s = seeded()
        s.levels[.squat] = 999
        let after = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                         result: .plan)
        XCTAssertEqual(after.levels[.squat], EngineConfig.levelMax,
                       "the level is read through the scale, not above it")
        XCTAssertEqual(after.failStreak[.squat], 0, "a successful session is not a shortfall")
    }

    func testEveryLevelLandsInsideTheScale() {
        for garbage in [-9, -1, 48, 999, 999_999, Int.max, Int.min] {
            var s = seeded()
            s.levels[.squat] = garbage
            for state in [Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                               result: .plan),
                          Engine.applyComeback(state: s, gapDays: 30),
                          Engine.applySilentDecay(state: s, gapDays: 10),
                          Engine.applyIllness(state: s)] {
                for p in Pattern.allCases {
                    let l = state.levels[p] ?? -1
                    XCTAssertTrue((0...EngineConfig.levelMax).contains(l),
                                  "level \(l) out of scale for \(p) from \(garbage)")
                }
            }
        }
    }

    func testAComebackFromAnImpossibleLevelLandsOnTheScale() {
        // The audit measured a landing at 98 against the reference's 45.
        var s = seeded()
        s.levels[.squat] = 999
        let after = Engine.applyComeback(state: s, gapDays: 30)
        XCTAssertEqual(after.levels[.squat], EngineConfig.levelMax - 2,
                       "the drop applies to the clamped level")
    }

    func testTheCounterSurvivesItsOwnEdgeInsteadOfTrappingTheProcess() {
        // Int.max * rotationStep used to trap (exit 133) on every plan.
        for counter in [Int.max, Int.max - 1, EngineConfig.countMax + 5, -5, Int.min] {
            var s = seeded()
            s.counter = counter
            let session = Engine.generateSession(s)
            XCTAssertEqual(session.exercises.count, EngineConfig.patternsPerSession,
                           "counter \(counter) still yields a full plan")
            XCTAssertTrue(session.sessionNumber >= 1)
            // And the pair still round-trips into feedback.
            let after = Engine.applyFeedback(state: s, session: session, result: .plan)
            XCTAssertTrue(after.counter >= 1)
        }
    }

    func testANegativeCounterPlansExactlyAsZeroDoes() {
        // The reference sanitizes the rotation read now, so the two agree.
        var dirty = seeded()
        dirty.counter = -3
        let clean = seeded()
        XCTAssertEqual(Engine.generateSession(dirty).exercises.map(\.pattern),
                       Engine.generateSession(clean).exercises.map(\.pattern))
    }

    func testTheBarParityReadsTheSanitizedCounter() {
        var s = seeded(hasBar: true)
        s.counter = -3
        let patterns = Engine.generateSession(s).exercises.map(\.pattern)
        XCTAssertTrue(patterns.contains(.pull))
        XCTAssertFalse(patterns.contains(.pullBar))
    }

    func testTheCreditPauseKeepsOnlyThePullSlotsBranches() {
        // The reference filters this map on every build; the port kept a
        // foreign pattern in it forever.
        var s = seeded(hasBar: true)
        s.creditPaused = [.squat, .calf, .pull]
        let after = Engine.applyIllness(state: s)
        XCTAssertEqual(after.creditPaused, [.pull])
    }

    func testSparseMapsKeepOnlyLiveEntries() {
        var s = seeded()
        s.frozen = [.squat: -3, .hinge: 0, .pull: 2]
        s.sore = [.squat: 0, .calf: 99]
        let after = Engine.applyIllness(state: s)
        XCTAssertNil(after.frozen[.squat], "a non-positive freeze is not a freeze")
        XCTAssertNil(after.frozen[.hinge])
        XCTAssertEqual(after.frozen[.pull], 2)
        XCTAssertNil(after.sore[.squat])
        XCTAssertEqual(after.sore[.calf], EngineConfig.freezeCapAppearances,
                       "a pain episode is clamped to the ladder's ceiling")
    }

    func testTheRunsStayFiniteWithoutLosingTheirMeaning() {
        // A run has no semantic ceiling — the golden fixture reaches a
        // lessRun of 7 against a threshold of 2 — so only the technical one
        // applies, and the valid domain must not notice it.
        var s = seeded()
        s.lessRun = Int.max
        s.returnRun = Int.max
        let after = Engine.applyComeback(state: s, gapDays: 30)
        XCTAssertEqual(after.returnRun, EngineConfig.countMax + 1)
        XCTAssertEqual(after.lessRun, 0, "a break is not a continued run of less")

        var run = seeded()
        for _ in 0..<7 {
            run = Engine.applyFeedback(state: run, session: Engine.generateSession(run),
                                       result: .less)
        }
        XCTAssertEqual(run.lessRun, 7, "the run itself is never trimmed to its threshold")
    }

    func testAStaleFeedbackPairIsStillANoOpAndReturnsTheInputUntouched() {
        var s = seeded()
        s.counter = 5
        let session = Engine.generateSession(s)
        var moved = s
        moved.counter = 9
        XCTAssertEqual(Engine.applyFeedback(state: moved, session: session, result: .plan),
                       moved, "a mismatched pair returns the state as it came in")
    }

    // MARK: - The gap in days is an input too (§24.2)

    func testANegativeOrHugeGapCannotTrapOrOverreach() {
        let s = seeded()
        for gap in [Int.min, -999_999, -1] {
            XCTAssertEqual(Engine.applyComeback(state: s, gapDays: gap), s,
                           "gap \(gap) is not a break")
            XCTAssertEqual(Engine.applySilentDecay(state: s, gapDays: gap), s)
        }
        let far = Engine.applyComeback(state: s, gapDays: Int.max)
        XCTAssertEqual(far.levels[.squat],
                       Engine.applyComeback(state: s, gapDays: EngineConfig.countMax)
                           .levels[.squat],
                       "past the technical ceiling the answer stops moving")
        XCTAssertEqual(far.levels[.squat], 0, "a lifetime away lands at the bottom")
    }

    func testTheNonStackingIdentityHoldsFromADirtyState() {
        // Spec §14.2 on a state that needed healing first.
        var s = seeded()
        s.levels[.squat] = 999
        s.counter = Int.max
        let peeked = Engine.applyComeback(state: Engine.applySilentDecay(state: s, gapDays: 10),
                                          gapDays: 16, alreadyDecayed: true)
        let straight = Engine.applyComeback(state: s, gapDays: 16, alreadyDecayed: false)
        XCTAssertEqual(peeked.levels, straight.levels,
                       "peeking mid-break costs no more, garbage or not")
    }

    // MARK: - Facts are inputs too (§24.3)

    func testAnImpossibleReportedFactSaturatesInsteadOfTrapping() {
        let s = seeded()
        let session = Engine.generateSession(s)
        let p = session.exercises[0].pattern
        let high = Engine.applyFeedback(state: s, session: session, result: .plan,
                                        overrides: [p: Int.max])
        XCTAssertEqual(high.levels[p], (s.levels[p] ?? 0) + EngineConfig.maxUp(
            pattern: p, tier: Level.decode(s.levels[p] ?? 0).tier),
                       "a fact past the scale still climbs only by its own ceiling")
        let low = Engine.applyFeedback(state: s, session: session, result: .plan,
                                       overrides: [p: Int.min])
        XCTAssertEqual(low.levels[p], 0, "a fact below the floor lands on it")
    }

    // MARK: - Decoding a corrupt file (§24.1)

    func testACorruptFileDecodesIntoAStateTheEngineCanRead() throws {
        let json = """
        {"counter":9223372036854775807,
         "levels":["squat",999,"pull",-4,"calf",47],
         "failStreak":["squat",-9223372036854775808,"pull",99],
         "hasBar":true,
         "frozen":["squat",-3,"pull",9223372036854775807],
         "lessRun":-5,
         "creditPaused":["squat","pull","nonsense"],
         "sore":["squat",0,"calf",99],
         "returnRun":-7,
         "illness":9999}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(json.utf8))
        XCTAssertEqual(state.counter, EngineConfig.countMax)
        XCTAssertEqual(state.levels[.squat], EngineConfig.levelMax)
        XCTAssertEqual(state.levels[.pull], 0)
        XCTAssertEqual(state.levels[.hinge], 0, "a missing pattern is a zero, not a hole")
        XCTAssertEqual(state.failStreak[.squat], 0)
        XCTAssertNil(state.frozen[.squat])
        XCTAssertEqual(state.frozen[.pull], EngineConfig.countMax)
        XCTAssertEqual(state.lessRun, 0)
        XCTAssertEqual(state.creditPaused, [.pull], "only the pull slot's branches survive")
        XCTAssertNil(state.sore[.squat])
        XCTAssertEqual(state.sore[.calf], EngineConfig.freezeCapAppearances)
        XCTAssertEqual(state.returnRun, 0)
        XCTAssertEqual(state.illness, EngineConfig.illnessSessions)

        // And the state that came out plans a real session.
        let session = Engine.generateSession(state)
        XCTAssertEqual(session.exercises.count, EngineConfig.patternsPerSession)
    }

    func testSanitizingIsTheIdentityOnAValidState() {
        // The property the golden fixture rests on.
        var s = seeded(level: 17, hasBar: true)
        s.counter = 42
        s.frozen = [.squat: 3]
        s.sore = [.calf: 6]
        // v2.20 (spec §31.3): the valid domain gained a field. A live episode
        // with no countdown beside it is no longer a valid state — the
        // sanitizer fills it in with the full assignment, exactly as the
        // reference does, so that files written before v2.20 get a whole
        // confirmation window. Identity therefore needs both halves present.
        s.soreLeft = [.calf: 6]
        s.creditPaused = [.pullBar]
        s.lessRun = 1
        s.returnRun = 2
        s.illness = 4
        XCTAssertEqual(s.sanitized(), s)
    }
}
