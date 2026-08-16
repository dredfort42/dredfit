//
//  EngineV212Tests.swift
//  DredfitCoreTests
//
//  Engine v2.12 (spec §22, issues #126/#133): a comeback lands at a dose no
//  higher than the last completed session — rep continuity on tier crossings,
//  a ladder of tier-bottom ceilings, a deepening series of returns — and the
//  "I was sick" lens makes the plan one tier easier for six restorative
//  sessions without touching the stored levels.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV212Tests: XCTestCase {

    private func seeded(_ level: Int, counter: Int = 4) -> EngineState {
        var s = EngineState.initial
        s.counter = counter
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    // MARK: - §22.1 rep continuity

    func testTierCrossingKeepsTheRepDose() {
        // L20 (tier 3 × 9 reps), 77 days → raw 15 crosses into tier 2:
        // the landing keeps 9 reps — level 11, not the tier-2 top.
        let after = Engine.applyComeback(state: seeded(20), gapDays: 77)
        XCTAssertEqual(after.levels[.squat], 11)
        XCTAssertEqual(Level.decode(11).reps, Level.decode(20).reps, "the dose survives")
        XCTAssertEqual(Level.decode(11).tier, Level.decode(20).tier - 1)
    }

    func testTheAuditReproLandsSoftly() {
        // A3-1: L18 after 35 days used to land at tier 2 × 13 (1.86× the
        // work); rep continuity lands it at tier 2 × 7.
        let after = Engine.applyComeback(state: seeded(18), gapDays: 35)
        XCTAssertEqual(after.levels[.squat], 9)
        XCTAssertEqual(Level.decode(9).reps, 7)
    }

    func testADoseBelowTheTierFloorClampsToTheFloor() {
        // L8 (tier 2 × 6), −2 crosses into tier 1 whose repStart is 8: the
        // dose 6 cannot be expressed — the floor is the safe landing.
        let after = Engine.applyComeback(state: seeded(8), gapDays: 14)
        XCTAssertEqual(after.levels[.squat], 0)
    }

    func testTheBandSnapKeepsItsPriority() {
        // 33 → 31 crosses the band boundary: the v2.7 floor snap, not the
        // tier continuity, decides.
        let after = Engine.applyComeback(state: seeded(33), gapDays: 14)
        XCTAssertEqual(after.levels[.squat], 24)
    }

    // MARK: - §22.2 the ceiling ladder

    func testTheLadderLandsOnTierBottoms() {
        for (gap, ceil) in [(56, 24), (77, 16), (119, 8), (180, 8), (365, 0)] {
            let after = Engine.applyComeback(state: seeded(47), gapDays: gap)
            XCTAssertEqual(after.levels[.squat], ceil, "gap \(gap)")
            let d = Level.decode(after.levels[.squat]!)
            XCTAssertEqual(d.reps, EngineConfig.repStart[d.tier],
                           "a ceiling is always a tier bottom (gap \(gap))")
        }
    }

    func testTheOldCliffAt180DaysIsGone() {
        let d179 = Engine.applyComeback(state: seeded(30), gapDays: 179).levels[.squat]
        let d180 = Engine.applyComeback(state: seeded(30), gapDays: 180).levels[.squat]
        XCTAssertEqual(d179, d180, "179 → 180 is no longer a two-tier cliff")
    }

    // MARK: - §22.3 the series of returns

    func testConsecutiveReturnsDeepenAndASessionResets() {
        var s = Engine.applyComeback(state: seeded(21), gapDays: 30)
        XCTAssertEqual(s.levels[.squat], 19, "first return is the table drop")
        XCTAssertEqual(s.returnRun, 1)
        s = Engine.applyComeback(state: s, gapDays: 30)
        XCTAssertEqual(s.levels[.squat], 16, "second return is one deeper")
        XCTAssertEqual(s.returnRun, 2)
        let w = Engine.generateSession(s)
        s = Engine.applyFeedback(state: s, session: w, result: .plan)
        XCTAssertEqual(s.returnRun, 0, "a completed session breaks the series")
    }

    func testADecayIsNotAReturn() {
        let s = Engine.applyComeback(state: seeded(21), gapDays: 30)
        XCTAssertEqual(Engine.applySilentDecay(state: s, gapDays: 10).returnRun, 1)
    }

    func testTheDecayComebackIdentityHoldsOnTheNewLanding() {
        for level in [8, 16, 17, 24, 32, 40, 47] {
            for gap in [16, 35, 77, 119, 180, 365] {
                let plain = Engine.applyComeback(state: seeded(level), gapDays: gap)
                let both = Engine.applyComeback(
                    state: Engine.applySilentDecay(state: seeded(level), gapDays: 10),
                    gapDays: gap, alreadyDecayed: true)
                XCTAssertEqual(plain.levels[.squat], both.levels[.squat],
                               "identity at L\(level)/\(gap)")
            }
        }
    }

    // MARK: - §22.4 the illness lens

    func testTheLensEasesThePlanWithoutTouchingLevels() {
        let ill = Engine.applyIllness(state: seeded(20))
        XCTAssertEqual(ill.illness, EngineConfig.illnessSessions)
        let w = Engine.generateSession(ill)
        for ex in w.exercises {
            XCTAssertEqual(ex.tier, Level.decode(Level.eased(20)).tier,
                           "\(ex.pattern) is one tier easier")
        }
        XCTAssertEqual(ill.levels[.squat], 20, "stored levels stand")
    }

    func testARestorativeSessionCountsButConcludesNothing() {
        var s = Engine.applyIllness(state: seeded(20))
        let w = Engine.generateSession(s)
        s = Engine.applyFeedback(state: s, session: w, result: .more,
                                 overrides: [.squat: 99])
        XCTAssertEqual(s.levels[.squat], 20, "facts and taps conclude nothing")
        XCTAssertEqual(s.illness, EngineConfig.illnessSessions - 1, "the lens ticks")
        XCTAssertEqual(s.counter, 5, "the session count advances")
        s = Engine.applyFeedback(state: s, session: Engine.generateSession(s), result: .less)
        XCTAssertEqual(s.lessRun, 0, "no run of less accumulates under the lens")
        XCTAssertEqual(s.levels[.squat], 20)
    }

    func testTheLensExpiresAndTheOrdinaryPlanReturns() {
        var s = Engine.applyIllness(state: seeded(20))
        for _ in 0..<EngineConfig.illnessSessions {
            s = Engine.applyFeedback(state: s, session: Engine.generateSession(s), result: .plan)
        }
        XCTAssertEqual(s.illness, 0)
        XCTAssertEqual(s.levels[.squat], 20, "no level moved in six sessions")
        let w = Engine.generateSession(s)
        XCTAssertEqual(w.exercises.first { $0.pattern == .squat }?.tier,
                       Level.decode(20).tier, "the plan is ordinary again")
    }

    func testPainStillWorksUnderTheLens() {
        let ill = Engine.applyIllness(state: seeded(20))
        let w = Engine.generateSession(ill)
        let hurt = Engine.applyFeedback(state: ill, session: w, result: .plan,
                                        discomfort: [.squat])
        XCTAssertEqual(hurt.levels[.squat], Level.unload(20), "the unload outranks the lens")
        XCTAssertEqual(hurt.sore[.squat], EngineConfig.freezeAppearances)
    }

    func testTheLensSurvivesBreaksAndRepeatTapsTopUp() {
        let ill = Engine.applyIllness(state: seeded(20))
        XCTAssertEqual(Engine.applySilentDecay(state: ill, gapDays: 10).illness,
                       EngineConfig.illnessSessions)
        XCTAssertEqual(Engine.applyComeback(state: ill, gapDays: 30).illness,
                       EngineConfig.illnessSessions)
        var s = Engine.applyFeedback(state: ill, session: Engine.generateSession(ill),
                                     result: .plan)
        s = Engine.applyIllness(state: s)
        XCTAssertEqual(s.illness, EngineConfig.illnessSessions, "a repeat tap tops up")
        XCTAssertEqual(Engine.applyIllness(state: ill), ill, "a tap on a fresh lens is a no-op")
    }

    // MARK: - serialization

    func testNewFieldsDecodeLenientlyAndRoundtrip() throws {
        var s = Engine.applyIllness(state: seeded(20))
        s = Engine.applyComeback(state: s, gapDays: 30)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(EngineState.self, from: data), s)

        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "returnRun")
        dict.removeValue(forKey: "illness")
        let legacy = try JSONDecoder().decode(EngineState.self,
                                              from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(legacy.returnRun, 0, "a legacy file has no series")
        XCTAssertEqual(legacy.illness, 0, "and no lens")

        dict["returnRun"] = -3
        dict["illness"] = 99
        let dirty = try JSONDecoder().decode(EngineState.self,
                                             from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(dirty.returnRun, 0, "a negative series is garbage")
        XCTAssertEqual(dirty.illness, EngineConfig.illnessSessions, "the lens clamps to its ceiling")
    }
}
