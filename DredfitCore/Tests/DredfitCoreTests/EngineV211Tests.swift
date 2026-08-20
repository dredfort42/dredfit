//
//  EngineV211Tests.swift
//  DredfitCoreTests
//
//  Engine v2.11 (spec §21, issues #124/#125): a pain report takes the load
//  off — the level lands at the bottom of the previous tier — and the freeze
//  it arms expires into waiting, not into growth: only an explicit fact at or
//  above the plan confirms recovery. Repeated reports double the rest up the
//  3 → 6 → 12 ladder, and the cross-credit never grows a frozen or sore
//  receiving branch.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV211Tests: XCTestCase {

    private func seeded(_ levels: [Pattern: Int] = [:], counter: Int = 0,
                        hasBar: Bool = false, base: Int = 20) -> EngineState {
        var s = EngineState.initial
        s.hasBar = hasBar
        s.counter = counter
        for p in Pattern.allCases { s.levels[p] = levels[p] ?? base }
        return s
    }

    /// Run plan sessions until the pattern has appeared `count` times.
    private func burnAppearances(_ state: EngineState, of pattern: Pattern,
                                 count: Int) -> EngineState {
        var s = state
        var burned = 0
        while burned < count {
            let w = Engine.generateSession(s)
            let present = w.exercises.contains { $0.pattern == pattern }
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            if present { burned += 1 }
        }
        return s
    }

    /// Advance until the pattern is in the plan, without spending one of its
    /// appearances.
    private func advanceToAppearance(_ state: EngineState,
                                     of pattern: Pattern) -> (EngineState, Session) {
        var s = state
        var w = Engine.generateSession(s)
        while !w.exercises.contains(where: { $0.pattern == pattern }) {
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            w = Engine.generateSession(s)
        }
        return (s, w)
    }

    // MARK: - §21.1 the unload

    func testUnloadLandsAtTheBottomOfThePreviousTier() {
        XCTAssertEqual(Level.unload(5), 0)     // tier 1 → the floor
        XCTAssertEqual(Level.unload(12), 0)    // tier 2 → the floor
        XCTAssertEqual(Level.unload(20), 8)    // tier 3 → bottom of tier 2
        XCTAssertEqual(Level.unload(28), 16)   // tier 4 → bottom of tier 3
        XCTAssertEqual(Level.unload(35), 16)   // band 4 is tier 4 by encoding
        XCTAssertEqual(Level.unload(47), 16)   // and so is band 5
    }

    /// v2.19 (spec §30.6): re-marked, not weakened. The first report now lands
    /// on the floor of the CURRENT tier — the same variation at its smallest
    /// dose — and the previous tier's floor became the second step, asserted
    /// below and swept over the whole scale in EngineV219Tests.
    func testFirstReportUnloadsFreezesAndOpensTheEpisode() {
        var state = seeded()
        state.failStreak[.squat] = 2
        let session = Engine.generateSession(state)   // counter 0: squat is in
        let after = Engine.applyFeedback(state: state, session: session,
                                         result: .more, discomfort: [.squat])
        XCTAssertEqual(after.levels[.squat], Level.tierFloor(20),
                       "tier 3 lands on its own floor")
        XCTAssertEqual(after.failStreak[.squat], 0, "the unload resets the streak")
        XCTAssertEqual(after.frozen[.squat], EngineConfig.freezeAppearances)
        XCTAssertEqual(after.sore[.squat], EngineConfig.freezeAppearances)
    }

    /// v2.19 (spec §30.6): re-marked and strengthened. The rest ladder is
    /// unchanged; what moved is the level. The SECOND report takes the step
    /// v2.11 took first — the floor of the previous tier — and from the third
    /// on the level stands, so the descent is bounded at two steps.
    func testRepeatReportsClimbTheLadderAndTakeTheSecondStepOnce() {
        var state = seeded()
        var (s, w) = advanceToAppearance(state, of: .squat)
        s = Engine.applyFeedback(state: s, session: w, result: .plan, discomfort: [.squat])
        let firstStep = s.levels[.squat]
        XCTAssertEqual(firstStep, Level.tierFloor(20), "first report: this tier's floor")
        let secondStep = Level.unload(Level.tierFloor(20))
        for (report, expected) in zip(2..., [6, 12, 12]) {   // ×2 with the ceiling
            (s, w) = advanceToAppearance(s, of: .squat)
            s = Engine.applyFeedback(state: s, session: w, result: .plan, discomfort: [.squat])
            XCTAssertEqual(s.frozen[.squat], expected)
            XCTAssertEqual(s.sore[.squat], expected)
            XCTAssertEqual(s.levels[.squat], secondStep,
                           "report \(report): the second step lands once and then holds")
        }
        state = s
    }

    // MARK: - §21.2 the freeze expires into waiting

    /// v2.20 (spec §31.2) REANNOTATED this one. "Taps never resume growth" was
    /// the whole defect: for a trainee who logs no numbers the fact route is
    /// unreachable, so the episode never ended. The subject the test was
    /// written for survives — a tap does not grow the level while the episode
    /// is open, and the session that closes it does not either — but the wait
    /// is now a COUNTDOWN, and its length comes from the state rather than
    /// from a loop bound that happened to stop short of it.
    func testExpiryWaitsAndTapsClampForTheWholeCountdown() throws {
        var s = seeded()
        var w = Engine.generateSession(s)
        s = Engine.applyFeedback(state: s, session: w, result: .plan, discomfort: [.squat])
        s = burnAppearances(s, of: .squat, count: EngineConfig.freezeAppearances)
        XCTAssertNil(s.frozen[.squat], "the counter is spent")
        XCTAssertEqual(s.sore[.squat], EngineConfig.freezeAppearances, "the episode lives")
        XCTAssertEqual(s.soreLeft[.squat], EngineConfig.freezeAppearances,
                       "and the freeze spent none of its confirmation")
        let held = try XCTUnwrap(s.levels[.squat])
        let need = try XCTUnwrap(s.soreLeft[.squat])
        for i in 1...need {
            (s, w) = advanceToAppearance(s, of: .squat)
            s = Engine.applyFeedback(state: s, session: w, result: .more)
            XCTAssertEqual(s.levels[.squat], held, "tap \(i) resumes no growth")
            XCTAssertEqual(s.failStreak[.squat], 0, "the streak stands while waiting")
            XCTAssertEqual(s.sore[.squat] != nil, i < need,
                           "the episode closes on tick \(need), not before")
        }
        // Only the appearance AFTER the closing one grows (§31.2 p.2).
        (s, w) = advanceToAppearance(s, of: .squat)
        s = Engine.applyFeedback(state: s, session: w, result: .more)
        XCTAssertGreaterThan(try XCTUnwrap(s.levels[.squat]), held,
                             "growth resumes one appearance after the close")
    }

    func testAFactAtOrAbovePlanConfirmsAndResumesUnderTheOrdinaryCap() throws {
        var s = seeded()
        var w = Engine.generateSession(s)
        s = Engine.applyFeedback(state: s, session: w, result: .plan, discomfort: [.squat])
        s = burnAppearances(s, of: .squat, count: EngineConfig.freezeAppearances)
        let held = s.levels[.squat]!
        (s, w) = advanceToAppearance(s, of: .squat)
        let load = try XCTUnwrap(w.exercises.first { $0.pattern == .squat }).load

        // A fact far above the plan: the ordinary cell caps it — waiting at
        // the floor is unloaded history, not a blank slate for calibration.
        let confirmed = Engine.applyFeedback(state: s, session: w, result: .plan,
                                             overrides: [.squat: load + 20])
        XCTAssertNil(confirmed.sore[.squat], "the episode is closed")
        let cap = EngineConfig.maxUp(pattern: .squat, tier: Level.decode(held).tier)
        XCTAssertEqual(confirmed.levels[.squat], held + cap)

        // A fact exactly at the plan steps like "on plan" and confirms too.
        let exact = Engine.applyFeedback(state: s, session: w, result: .plan,
                                         overrides: [.squat: load])
        XCTAssertNil(exact.sore[.squat])
        XCTAssertEqual(exact.levels[.squat], held + EngineConfig.deltaPlan)

        // A fact below the plan goes down and keeps the episode open.
        let below = Engine.applyFeedback(state: s, session: w, result: .plan,
                                         overrides: [.squat: max(0, load - 2)])
        XCTAssertEqual(below.sore[.squat], EngineConfig.freezeAppearances)
        XCTAssertLessThan(below.levels[.squat]!, held)
    }

    func testAFactUpDuringTheFreezeNeitherGrowsNorConfirms() throws {
        var s = seeded()
        let w0 = Engine.generateSession(s)
        s = Engine.applyFeedback(state: s, session: w0, result: .plan, discomfort: [.squat])
        let held = s.levels[.squat]!
        let (s1, w) = advanceToAppearance(s, of: .squat)
        let after = Engine.applyFeedback(state: s1, session: w, result: .plan,
                                         overrides: [.squat: 99])
        XCTAssertEqual(after.levels[.squat], held, "the assigned rest is served in full")
        XCTAssertEqual(after.sore[.squat], EngineConfig.freezeAppearances,
                       "a fact during the freeze does not confirm")
    }

    // MARK: - §21.2 p.7 a pin never shortens a pain freeze

    func testPinnedOnASoreePatternKeepsTheLongerRest() {
        var s = seeded()
        var (s1, w) = advanceToAppearance(s, of: .squat)
        s = Engine.applyFeedback(state: s1, session: w, result: .plan, discomfort: [.squat])
        (s, w) = advanceToAppearance(s, of: .squat)
        s = Engine.applyFeedback(state: s, session: w, result: .plan, discomfort: [.squat])
        XCTAssertEqual(s.frozen[.squat], 6)
        (s, w) = advanceToAppearance(s, of: .squat)
        let pinned = Engine.applyFeedback(state: s, session: w, result: .plan, pinned: [.squat])
        XCTAssertEqual(pinned.frozen[.squat], 6, "max(6, 3) — the pain rest stands")
        XCTAssertEqual(pinned.sore[.squat], 6, "the episode is untouched")
    }

    // MARK: - §21.2 p.8 breaks

    func testBreaksDropLevelsButKeepTheEpisode() {
        var s = seeded()
        let w = Engine.generateSession(s)
        s = Engine.applyFeedback(state: s, session: w, result: .plan, discomfort: [.squat])
        let decayed = Engine.applySilentDecay(state: s, gapDays: 10)
        XCTAssertEqual(decayed.sore[.squat], EngineConfig.freezeAppearances)
        XCTAssertEqual(decayed.levels[.squat], s.levels[.squat]! - 1)
        let back = Engine.applyComeback(state: s, gapDays: 40)
        XCTAssertEqual(back.sore[.squat], EngineConfig.freezeAppearances,
                       "the confirmation stays owed across a comeback")
    }

    // MARK: - §21.3 the credit gate (#125)

    func testCreditNeverGrowsAFrozenOrSoreBranch() throws {
        for reported in [Pattern.pullBar, .pull] {
            var s = seeded(hasBar: true, base: 10)
            var (s1, w) = advanceToAppearance(s, of: reported)
            s = Engine.applyFeedback(state: s1, session: w, result: .plan,
                                     discomfort: [reported])
            let held = s.levels[reported]!
            // Eight sessions of honest work on the other branch: no credit.
            for _ in 0..<8 {
                w = Engine.generateSession(s)
                s = Engine.applyFeedback(state: s, session: w, result: .plan)
            }
            XCTAssertEqual(s.levels[reported], held,
                           "\(reported): the episode blocks the credit")
            // Confirm with a fact — the credit flows again.
            (s, w) = advanceToAppearance(s, of: reported)
            let load = try XCTUnwrap(w.exercises.first { $0.pattern == reported }).load
            s = Engine.applyFeedback(state: s, session: w, result: .plan,
                                     overrides: [reported: load])
            XCTAssertNil(s.sore[reported])
            let other: Pattern = reported == .pull ? .pullBar : .pull
            let (s2, w2) = advanceToAppearance(s, of: other)
            let before = s2.levels[reported]!
            let after = Engine.applyFeedback(state: s2, session: w2, result: .plan)
            XCTAssertEqual(after.levels[reported], before + 1,
                           "\(reported): after confirmation the credit returns")
        }
    }

    // MARK: - §21.4 serialization

    func testSoreDecodesLenientlyAndSurvivesRoundtrip() throws {
        var s = seeded()
        let w = Engine.generateSession(s)
        s = Engine.applyFeedback(state: s, session: w, result: .plan, discomfort: [.squat])
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(decoded, s, "sore survives the JSON roundtrip")

        // A file written before v2.11 has no `sore` key at all.
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "sore")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        let legacy = try JSONDecoder().decode(EngineState.self, from: legacyData)
        XCTAssertTrue(legacy.sore.isEmpty, "a legacy file decodes to no episodes")

        // Garbage values are sanitized the way the reference does it.
        dict["sore"] = ["squat", 99, "hinge", -2, "pull", 6]
        let dirtyData = try JSONSerialization.data(withJSONObject: dict)
        let dirty = try JSONDecoder().decode(EngineState.self, from: dirtyData)
        XCTAssertEqual(dirty.sore[.squat], EngineConfig.freezeCapAppearances,
                       "a value past the ceiling is clamped")
        XCTAssertNil(dirty.sore[.hinge], "a negative entry is dropped")
        XCTAssertEqual(dirty.sore[.pull], 6)
    }

    func testGenerationIsIndependentOfSore() {
        let a = seeded()
        var b = seeded()
        b.sore[.squat] = 3
        XCTAssertEqual(Engine.generateSession(a), Engine.generateSession(b),
                       "sore never changes the plan itself")
    }
}
