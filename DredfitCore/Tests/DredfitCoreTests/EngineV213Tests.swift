//
// Engine (issues #132, #146): the sanitization wave. The promise of — "the
// plan is valid even with garbage in the state" — had two holes. The reference
// still read a few containers raw, and this port sanitized only on decode, so
// a corrupt store file produced unearned deloads, a comeback landing above the
// scale, and — near Int's edge — a process trap on every plan, in a crash loop
// the file quarantine could not catch, because the decode itself had
// succeeded.
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

    // MARK: - The state heals on every entry

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
                          Engine.applySilentDecay(state: s, gapDays: 10)] {
                for p in Pattern.allCases {
                    let l = state.levels[p] ?? -1
                    XCTAssertTrue((0...EngineConfig.levelMax).contains(l),
                                  "level \(l) out of scale for \(p) from \(garbage)")
                }
            }
            // The three HANDLES are deliberately NOT in the list above, and
            // this is the difference in kind rather than a gap. The three
            // state builders rebuild every field through the sanitizer; a
            // handle is a NARROW EDITOR of one axis and passes the rest
            // through as it found them, garbage included. The reference does
            // exactly the same — verified call for call by the differential —
            // and a port that "fixed" it here would diverge.
            //
            // What a handle DOES promise is asserted instead, and in full: it
            // never throws, and the plan built from its result is valid, so
            // the garbage carried through is healed at generation like any
            // other.
            // Two rows for the session-wide handle are gone
            // with its export. The claim they carried — a narrow editor never
            // throws and never drops the plan under the floor on any shape of
            // garbage — is unchanged, because that handle WAS a loop over the
            // two `setCut` rows still here.
            for state in [Engine.setCut(state: s, pattern: .squat, cut: 1),
                          Engine.setCut(state: s, pattern: .squat, cut: garbage),
                          Engine.easierVariation(state: s, pattern: .squat)] {
                let session = Engine.generateSession(state)
                XCTAssertEqual(session.exercises.count, EngineConfig.patternsPerSession,
                               "a handle's result must still plan a full session (\(garbage))")
                for ex in session.exercises {
                    XCTAssertGreaterThanOrEqual(ex.sets, EngineConfig.setsFloor,
                                                "a handle went below the floor (\(garbage))")
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
        // `applyIllness` was the entry point used here purely because it
        // healed its input and changed almost nothing else. It is gone;
        // `recordShown` is the surviving entry with the same property.
        let after = Engine.recordShown(state: s, session: Engine.generateSession(s))
        XCTAssertEqual(after.creditPaused, [.pull])
    }

    /// Re-marked, not weakened. The claim is unchanged — a sparse map keeps
    /// only live entries and clamps them — but `frozen` and `sore` no longer
    /// exist. `setsHold` is the surviving counter of the same SHAPE (sparse,
    /// per-pattern, positive-only, clamped to its own ceiling), so the same
    /// three assertions are made on it.
    func testSparseMapsKeepOnlyLiveEntries() {
        var s = seeded()
        s.setsHold = [.squat: -3, .hinge: 0, .pull: 2]
        s.weekGain = [.calf: 99]
        let after = Engine.recordShown(state: s, session: Engine.generateSession(s))
        XCTAssertNil(after.setsHold[.squat], "a non-positive hold is not a hold")
        XCTAssertNil(after.setsHold[.hinge])
        XCTAssertEqual(after.setsHold[.pull], 2)
        XCTAssertEqual(after.weekGain[.calf], min(99, EngineConfig.countMax),
                       "a gain is clamped to its own ceiling")
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

    // MARK: - The gap in days is an input too

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
        // on a state that needed healing first.
        var s = seeded()
        s.levels[.squat] = 999
        s.counter = Int.max
        let peeked = Engine.applyComeback(state: Engine.applySilentDecay(state: s, gapDays: 10),
                                          gapDays: 16, alreadyDecayed: true)
        let straight = Engine.applyComeback(state: s, gapDays: 16, alreadyDecayed: false)
        XCTAssertEqual(peeked.levels, straight.levels,
                       "peeking mid-break costs no more, garbage or not")
    }

    // MARK: - Facts are inputs too

    func testAnImpossibleReportedFactSaturatesInsteadOfTrapping() {
        let s = seeded()
        let session = Engine.generateSession(s)
        let p = session.exercises[0].pattern
        let high = Engine.applyFeedback(state: s, session: session, result: .plan,
                                        overrides: [p: Int.max])
        assertPosition(high, p, Level.rise(level: s.levels[p] ?? 0, sub: s.sub[p] ?? 0,
                                           by: EngineConfig.maxUp(
                                               pattern: p,
                                               tier: Level.decode(s.levels[p] ?? 0).tier)),
                       "a fact past the scale still climbs only by its own ceiling")
        let low = Engine.applyFeedback(state: s, session: session, result: .plan,
                                       overrides: [p: Int.min])
        XCTAssertEqual(low.levels[p], 0, "a fact below the floor lands on it")
    }

    // MARK: - Decoding a corrupt file

    func testACorruptFileDecodesIntoAStateTheEngineCanRead() throws {
        // The corrupt file still carries the SEVEN removed keys — that is what
        // a file written by an older build looks like — and the decoder is
        // expected to ignore them rather than choke. The garbage in the live
        // fields is healed exactly as before.
        let json = """
        {"counter":9223372036854775807,
         "levels":["squat",999,"pull",-4,"calf",47],
         "failStreak":["squat",-9223372036854775808,"pull",99],
         "hasBar":true,
         "frozen":["squat",-3,"pull",9223372036854775807],
         "lessRun":-5,
         "creditPaused":["squat","pull","nonsense"],
         "sore":["squat",0,"calf",99],
         "soreLeft":["calf",4],
         "painSeen":["calf",7],
         "timeBudgetMin":45,
         "shownBudget":30,
         "setsHold":["squat",-3,"pull",9223372036854775807],
         "returnRun":-7,
         "illness":9999}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(json.utf8))
        XCTAssertEqual(state.counter, EngineConfig.countMax)
        XCTAssertEqual(state.levels[.squat], EngineConfig.levelMax)
        XCTAssertEqual(state.levels[.pull], 0)
        XCTAssertEqual(state.levels[.hinge], 0, "a missing pattern is a zero, not a hole")
        XCTAssertEqual(state.failStreak[.squat], 0)
        XCTAssertNil(state.setsHold[.squat], "a non-positive hold is dropped")
        XCTAssertEqual(state.setsHold[.pull], EngineConfig.setsBackHold,
                       "and a huge one clamps to its ceiling")
        XCTAssertEqual(state.lessRun, 0)
        XCTAssertEqual(state.creditPaused, [.pull], "only the pull slot's branches survive")
        XCTAssertEqual(state.returnRun, 0)

        // And the state that came out plans a real session.
        let session = Engine.generateSession(state)
        XCTAssertEqual(session.exercises.count, EngineConfig.patternsPerSession)
    }

    func testSanitizingIsTheIdentityOnAValidState() {
        // The property the golden fixture rests on.
        var s = seeded(level: 17, hasBar: true)
        s.counter = 42
        s.setsHold = [.squat: EngineConfig.setsBackHold]
        s.creditPaused = [.pullBar]
        s.lessRun = 1
        s.returnRun = 2
        XCTAssertEqual(s.sanitized(), s)
    }
}
