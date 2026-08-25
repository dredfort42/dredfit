//
//  The descent never adds load. Three defects of the
// "do no harm" rung, measured on the reference:
//
//  1. A pain report could make the plan HEAVIER. The unload dropped straight
//     to the previous tier's floor, and where that tier is one-sided the work
//     grew: hinge L24 3×4 = 12 reps → L16 3×5 per leg = 30 (+150%). Taking
// the load off is two-step now — the first step never leaves the tier, so one
// tap can no longer hand anyone an unfamiliar movement. 2. The measure of work
// ignored sides, and the gate read only the product sets × load, so a descent
// could buy reps by dropping a set
//
//  3. Two workouts inside one day froze growth forever: the gap rounded to
// zero, the window never aged, and the weekly budget was spent once for a
// lifetime — 48 levels against 423 over 120 sessions.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV219Tests: XCTestCase {

    private func seeded(_ level: Int, hasBar: Bool = false) -> EngineState {
        var s = EngineState.initial
        s.hasBar = hasBar
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    /// Advance with "plan" sessions until the pattern is in the plan, without
    /// spending one of its appearances.
    private func advance(_ state: EngineState,
                         to pattern: Pattern) -> (EngineState, Session) {
        var s = state
        var w = Engine.generateSession(s)
        while !w.exercises.contains(where: { $0.pattern == pattern }) {
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            w = Engine.generateSession(s)
        }
        return (s, w)
    }

    /// The first step never adds work — swept over every pattern and every
    /// rung, through the measure itself rather than through pinned numbers.
    /// This is the property the pain channel exists for: the trainee said "it
    /// hurts" and must never get more to do.
    func testTheFirstStepNeverAddsWorkAnywhereOnTheGrid() {
        var cells = 0
        for pattern in Pattern.allCases {
            for level in 0...EngineConfig.levelMax {
                cells += 1
                let landed = Level.tierFloor(level)
                let before = Level.work(pattern: pattern, level: level, sub: 0, cut: 0)
                let after = Level.work(pattern: pattern, level: landed, sub: 0, cut: 0)
                XCTAssertEqual(after.tier, before.tier,
                               "\(pattern) L\(level): the first step stays in the tier")
                XCTAssertEqual(after.sides, before.sides,
                               "\(pattern) L\(level): the same variation, the same sides")
                XCTAssertLessThanOrEqual(after.load, before.load,
                                         "\(pattern) L\(level): never more per set")
                XCTAssertLessThanOrEqual(after.total, before.total,
                                         "\(pattern) L\(level): never more work in total")
                XCTAssertTrue(Level.noHarder(pattern: pattern, from: level, to: landed, fromCut: 0, toCut: 0),
                              "\(pattern) L\(level): the gate agrees")
            }
        }
        XCTAssertEqual(cells, Pattern.allCases.count * (EngineConfig.levelMax + 1),
                       "10 patterns × 48 levels")
    }

    // MARK: - The measure and the gate

    func testTheMeasureCountsSides() {
        // hinge tier 4 is the sliding leg curl (both legs), tier 3 the
        // single-leg deadlift — the pair that made the descent heavier.
        let bothLegs = Level.work(pattern: .hinge, level: 24, sub: 0, cut: 0)
        let oneLeg = Level.work(pattern: .hinge, level: 16, sub: 0, cut: 0)
        XCTAssertEqual(bothLegs.sides, 1)
        XCTAssertEqual(oneLeg.sides, 2)
        XCTAssertEqual(bothLegs.total, 12, "3×4 with both legs")
        XCTAssertEqual(oneLeg.total, 30, "3×5 per leg is two and a half times the work")
    }

    /// Inside a tier the gate reads both the dose of a set and the total, so
    /// trading a set for reps no longer passes.
    func testInsideATierTheGateReadsTheDosePerSetToo() {
        XCTAssertFalse(Level.noHarder(pattern: .pushH, from: 32, to: 28, fromCut: 0, toCut: 0),
                       "3×8 asks eight reps a set against the plan's six")
        XCTAssertTrue(Level.noHarder(pattern: .pushH, from: 32, to: 26, fromCut: 0, toCut: 0),
                      "3×6 keeps the dose and drops a set")
    }

    /// The tier-floor exemption stays: across a change of variation a measure
    /// in reps is not valid, and the floor of the lower tier IS the "take the
    /// load off" step provides for.
    func testTheTierFloorExemptionSurvives() {
        XCTAssertTrue(Level.noHarder(pattern: .hinge, from: 24, to: 16, fromCut: 0, toCut: 0),
                      "the second step is allowed: a different, easier movement")
        XCTAssertFalse(Level.noHarder(pattern: .hinge, from: 24, to: 17, fromCut: 0, toCut: 0),
                       "but the middle of the lower tier is not")
    }

    // MARK: - The weekly window ages by fractions of a day

    private func run(sessions: Int, gapDays: Double?) -> Int {
        var s = EngineState.initial
        for _ in 0..<sessions {
            s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                     result: .plan, gapDays: gapDays)
        }
        return Pattern.allCases.reduce(0) { $0 + (s.levels[$1] ?? 0) }
    }

    /// The control run of the wave: 120 sessions of "plan" at 0.4 days apart.
    /// Under the gap rounded to zero and the sum froze at 48 — the whole
    /// weekly budget, spent once and never renewed. Re-marked, 336/423 →
    /// 112/226. The numbers are a digit-for-digit cross-check against
    /// adaptive_engine.js on a path the golden fixtures do not cover, and they
    /// moved because the budget is now counted in SUB-STEPS: three sub-steps a
    /// week is one level for a slow tissue where it used to be three. Both
    /// were recomputed from the reference, not adjusted to the port. The
    /// subject — a fractional gap ages the window at all, so growth does not
    /// freeze for good — is asserted against the one-window budget rather than
    /// against a bare constant.
    func testTwiceADayNoLongerFreezesGrowthForever() {
        let twiceADay = run(sessions: 120, gapDays: 0.4)
        let daily = run(sessions: 120, gapDays: 1)
        XCTAssertEqual(twiceADay, 112, "a fractional gap ages the window")
        XCTAssertEqual(daily, 226, "and a daily rhythm is untouched")
        // A window that never aged would spend one budget for a lifetime: three
        // sub-steps for each slow tissue and six for everything else.
        let slow = Pattern.allCases.filter {
            EngineConfig.isSlowTissue($0) || Pattern.pullSide.contains($0)
        }
        let oneWindow = slow.count * EngineConfig.weeklyRiseSlow
            + (Pattern.allCases.count - slow.count) * EngineConfig.weeklyRiseFast
        XCTAssertGreaterThan(twiceADay, oneWindow,
                             "the window aged more than once — that was the whole defect")
        XCTAssertGreaterThan(daily, twiceADay,
                             "and a longer gap still buys more growth than a shorter one")
    }

    /// A zero gap is always a fault in the source — a session cannot take less
    /// than an hour — so the window ages by the floor rather than standing
    /// still. The floor REPLACES the gap from below; it is never added to it.
    func testTheSessionAgeHasAFloorOfOneHour() {
        var s = EngineState.initial
        s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                 result: .plan, gapDays: 0)
        XCTAssertEqual(s.weekAgeDays, EngineConfig.minSessionAgeDays, accuracy: 1e-12,
                       "a zero gap still ages the window by an hour")
        s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                 result: .plan, gapDays: 0.5)
        XCTAssertEqual(s.weekAgeDays, EngineConfig.minSessionAgeDays + 0.5, accuracy: 1e-12,
                       "and a real gap is used as it is, not stacked on the floor")
    }

    /// A mixed rhythm of fractional gaps, checked against the same run on the
    /// reference: the port and adaptive_engine.js must agree digit for digit
    /// on a path golden does not cover (the fixtures pass no gap at all).
    func testAMixedFractionalRhythmMatchesTheReference() {
        var s = EngineState.initial
        s.hasBar = true
        let gaps = [0.3, 1.7, 0.05]
        for i in 0..<60 {
            s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                     result: .plan, gapDays: gaps[i % 3])
        }
        // Recomputed from the reference — 269 → 92, 17 → 5. Same cause as
        // above: the weekly budget counts sub-steps now.
        let total = Pattern.allCases.reduce(0) { $0 + (s.levels[$1] ?? 0) }
        XCTAssertEqual(total, 92, "reference: Σ levels over 60 sessions")
        XCTAssertEqual(s.levels[.pullBar], 5, "reference: the bar branch")
        XCTAssertEqual(s.sub[.pullBar], 2, "reference: and its sub-step")
        XCTAssertEqual(s.weekAgeDays, 0.05, accuracy: 1e-12, "reference: the window age")
    }

    func testTheWindowExpiresOnFractionsAndClearsTheGain() {
        var s = EngineState.initial
        for _ in 0..<7 {
            s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                     result: .plan, gapDays: 0.9)
        }
        XCTAssertEqual(s.weekAgeDays, 6.3, accuracy: 1e-9, "6.3 days: the window lives")
        XCTAssertEqual(s.weekGain[.pull], EngineConfig.weeklyRiseSlow,
                       "and the slow tissue has spent its whole budget")
        s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                 result: .plan, gapDays: 0.9)
        XCTAssertEqual(s.weekAgeDays, 0, "7.2 days: it turned over")
        XCTAssertEqual(s.weekGain[.pull], 1,
                       "and the budget is fresh — only this session is on it")
    }

    /// No signal, no rule: without a gap the engine stays calendar-blind and
    /// the window never opens.
    func testWithoutASignalTheWindowStaysShut() {
        var s = EngineState.initial
        for _ in 0..<30 {
            s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                     result: .plan)
        }
        XCTAssertEqual(s.weekAgeDays, 0)
        XCTAssertTrue(s.weekGain.isEmpty)
    }

    // MARK: - Serialization

    /// The window age became fractional; a state file that carries the whole
    /// number written by an older build must still decode.
    func testALegacyWholeDayWindowAgeDecodes() throws {
        let legacy = """
        {"counter":4,"levels":["pull",5],"failStreak":["pull",0],"weekAgeDays":3}
        """
        let state = try JSONDecoder().decode(EngineState.self, from: Data(legacy.utf8))
        XCTAssertEqual(state.weekAgeDays, 3)
    }

    func testAFractionalWindowAgeRoundTrips() throws {
        var s = EngineState.initial
        s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                 result: .plan, gapDays: 0.4)
        let back = try JSONDecoder().decode(EngineState.self,
                                            from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.weekAgeDays, 0.4, accuracy: 1e-12)
    }

    /// Garbage in the field is healed, as everywhere else.
    func testANonsenseWindowAgeIsHealed() {
        var s = EngineState.initial
        s.weekAgeDays = .nan
        XCTAssertEqual(s.sanitized().weekAgeDays, 0)
        s.weekAgeDays = -5
        XCTAssertEqual(s.sanitized().weekAgeDays, 0)
        s.weekAgeDays = .infinity
        XCTAssertEqual(s.sanitized().weekAgeDays, 0)
    }

    // SNIPPED: three tests driven by the discomfort report — the two-step
    // unload landing on its floors, the third report that doubled the rest
    // without moving the level, and the control run on `hinge`. All three
    // needed an input that no longer exists.
    //
    // The INVARIANT the wave was written for — a descent never adds work
    // inside a variation — is not lost with them: it is asserted here by
    // `testTheFirstStepNeverAddsWorkAnywhereOnTheGrid`, by the gate tests
    // below, and swept over every downward path (the handles now included) by
    // the reference's block 51(b).
}
