//
//  What v3 added, tested where golden cannot reach: the clean start with no
//  migration, the probe and its three outcomes, the entry of 3×4, adaptation
//  by honest facts, the ceiling on any assignment (И2), and the one unit
//  boundary in the library.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV3Tests: XCTestCase {

    // MARK: - Helpers

    /// A state with one pattern moved and everything else fresh. Everything
    /// past the position travels in `Seed` — the position is six coordinates
    /// now, and nine loose parameters is a parameter list nobody reads.
    private struct Seed {
        var sets = EngineConfig.setsBase
        var shown: [Int: Int] = [:]
        var counter = 0
        var hasBar = false
    }

    private func state(_ p: Pattern, variation: Int, dose: Int,
                       _ seed: Seed = Seed()) -> EngineState {
        var s = EngineState.initial
        s.counter = seed.counter
        s.hasBar = seed.hasBar
        s.vars[p] = variation
        s.doses[p] = dose
        if seed.sets != EngineConfig.setsBase { s.sets[p] = seed.sets }
        if !seed.shown.isEmpty { s.shown[p] = seed.shown }
        return s
    }

    /// Squat on the ceiling of its first variation, ready for a probe.
    private func squatAtCeiling() -> EngineState {
        state(.squat, variation: 1, dose: 15, Seed(shown: [1: 15]))
    }

    private func exercise(_ session: Session, _ p: Pattern) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == p },
                      "\(p.rawValue) is not in this session")
    }

    // MARK: - §40.8 · no migration, so an incompatible state starts clean

    /// A state written by v2 carries `levels` and no `vars`, and the decode
    /// FAILS on it. That failure IS the no-migration decision: the app reads
    /// it as "hand the engine `initial`" and keeps the workout journal, which
    /// lives in a different file.
    func testStateFromV2FailsToDecode() throws {
        let v2 = #"""
        {"counter":42,"levels":["squat",34,"push_h",20],"failStreak":["squat",0],
         "hasBar":true,"lessRun":0,"returnRun":0,"rampWindow":0,"weekAgeDays":0}
        """#
        XCTAssertThrowsError(
            try JSONDecoder().decode(EngineState.self, from: Data(v2.utf8)),
            "a v2 state must not decode — code that reads the old shape is deliberately absent")
    }

    /// And a clean start is exactly what §40.8 promises: every pattern on its
    /// first rung, 3×4 (3×15 s), nothing shown yet.
    func testCleanStartIsEveryPatternAtThreeByFour() throws {
        let session = Engine.generateSession(.initial)
        XCTAssertEqual(session.exercises.count, EngineConfig.patternsPerSession)
        for ex in session.exercises {
            XCTAssertEqual(ex.variation, 1, "\(ex.pattern.rawValue): first rung")
            XCTAssertEqual(ex.sets, 3, "\(ex.pattern.rawValue): three sets")
            XCTAssertEqual(ex.load, Dose.grid(ex.unit).min, "\(ex.pattern.rawValue): the floor")
            XCTAssertNil(ex.loads, "\(ex.pattern.rawValue): a clean start is uniform")
            XCTAssertNil(ex.probe, "\(ex.pattern.rawValue): nothing to probe from the floor")
        }
        XCTAssertTrue(EngineState.initial.shown.isEmpty)
        XCTAssertEqual(Engine.totalProgress(.initial), 0)
    }

    /// A v3 state survives the round trip it is actually stored through.
    func testStateRoundTripsThroughCodable() throws {
        var s = squatAtCeiling()
        s.sets[.calf] = 3           // sparse fields written explicitly, then healed away
        s.lastHard = [.pull]
        s.creditPaused = [.pullBar]
        s.setsHold[.hinge] = 2
        s.weekAgeDays = 2.5
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(back.sanitized(), s.sanitized())
        XCTAssertEqual(back.shown[.squat], [1: 15])
        XCTAssertEqual(back.lastHard, [.pull])
    }

    // MARK: - §40.4 · the probe

    /// The probe replaces the LAST of the remaining sets: one working set
    /// fewer, one set of the next variation, and the session's volume does not
    /// grow.
    func testProbeReplacesTheLastSetAndDoesNotGrowTheSession() throws {
        let session = Engine.generateSession(squatAtCeiling())
        let squat = try exercise(session, .squat)
        XCTAssertEqual(squat.sets, 2, "two working sets, not three")
        let probe = try XCTUnwrap(squat.probe)
        XCTAssertEqual(probe.variation, 2)
        XCTAssertEqual(probe.load, 4, "the target is the floor of the grid")
        XCTAssertTrue(probe.perSide, "the split squat is trained one side at a time")
        XCTAssertEqual(probe.name, Library.name(.squat, 2))
        // Volume: 2×15 of the old plus 1×4 per side of the new, against 3×15.
        XCTAssertEqual(squat.plannedVolume, 30)
    }

    /// A probe is offered only on the ceiling, only below the top variation,
    /// and only when the last answer was not "hard".
    func testProbeConditionsAreAllThree() throws {
        var below = squatAtCeiling()
        below.doses[.squat] = 14
        XCTAssertNil(try exercise(Engine.generateSession(below), .squat).probe,
                     "below the ceiling there is nothing to probe from")

        var top = squatAtCeiling()
        top.vars[.squat] = Library.count(.squat)
        top.doses[.squat] = 15
        XCTAssertNil(try exercise(Engine.generateSession(top), .squat).probe,
                     "the top variation has nowhere to go")

        var hard = squatAtCeiling()
        hard.lastHard = [.squat]
        XCTAssertNil(try exercise(Engine.generateSession(hard), .squat).probe,
                     "«hard» was said and has not been unsaid")
    }

    /// Outcome one: the number came back at or above the floor — the variation
    /// changes, and the entry is ALWAYS 3×4.
    func testProbeResolvedEntersTheNextVariationAtThreeByFour() throws {
        let start = squatAtCeiling()
        let session = Engine.generateSession(start)
        let after = Engine.applyFeedback(state: start, session: session, result: .plan,
                                         overrides: [:], skipped: [], gapDays: nil,
                                         probes: [.squat: 6])
        XCTAssertEqual(after.vars[.squat], 2)
        XCTAssertEqual(after.doses[.squat], 4, "entry is the floor of the grid")
        XCTAssertEqual(after.sets[.squat] ?? EngineConfig.setsBase, 3)
        XCTAssertEqual(after.sub[.squat] ?? 0, 0)
        XCTAssertEqual(after.cutOf(.squat), 0)
        // The journal records what the probe actually showed, and the old
        // variation's entry is the point of return.
        XCTAssertEqual(after.shown[.squat]?[2], 6)
        XCTAssertEqual(after.shown[.squat]?[1], 15)

        // And the plan that follows is 3×4 per side.
        var next = after
        next.counter = 0                     // put the squat back into session one
        let plan = try exercise(Engine.generateSession(next), .squat)
        XCTAssertEqual(plan.sets, 3)
        XCTAssertEqual(plan.load, 4)
        XCTAssertTrue(plan.perSide)
        XCTAssertNil(plan.loads)
    }

    /// Outcome two: the number came back BELOW the floor — the variation is
    /// out of reach. И3: nothing moves but the journal of facts, and the
    /// appearance still counted as an ordinary one.
    func testProbeFailedMovesNothingButTheJournal() throws {
        let start = squatAtCeiling()
        let session = Engine.generateSession(start)
        let after = Engine.applyFeedback(state: start, session: session, result: .plan,
                                         overrides: [:], skipped: [], gapDays: nil,
                                         probes: [.squat: 2])
        XCTAssertEqual(after.vars[.squat], 1, "still on the old variation")
        XCTAssertEqual(after.doses[.squat], 15, "still on its ceiling")
        XCTAssertEqual(after.sub[.squat] ?? 0, 0)
        XCTAssertEqual(after.shown[.squat]?[2], 2, "what was shown is still recorded")
        XCTAssertFalse(after.lastHard.contains(.squat), "a failed probe is not a failure")
        // The probe comes back on the next appearance.
        var next = after
        next.counter = 0
        XCTAssertNotNil(try exercise(Engine.generateSession(next), .squat).probe)
    }

    /// Outcome three: no number at all — the probe did not resolve, and
    /// nothing at all changes, the journal included.
    func testProbeUnresolvedChangesNothing() throws {
        let start = squatAtCeiling()
        let session = Engine.generateSession(start)
        let after = Engine.applyFeedback(state: start, session: session, result: .plan,
                                         overrides: [:], skipped: [], gapDays: nil,
                                         probes: [:])
        XCTAssertEqual(after.vars[.squat], 1)
        XCTAssertEqual(after.doses[.squat], 15)
        XCTAssertNil(after.shown[.squat]?[2])
        XCTAssertEqual(after.shown[.squat]?[1], 15, "the journal of the OLD variation is untouched")
    }

    /// A "hard" answer on the movement is ordinary "hard" handling, and the
    /// probe of that session does not count even with a number reported.
    func testProbeIsNotCountedWhenTheMovementWasHard() throws {
        let start = squatAtCeiling()
        let session = Engine.generateSession(start)
        let after = Engine.applyFeedback(state: start, session: session, result: .plan,
                                         overrides: [.squat: 9], skipped: [], gapDays: nil,
                                         probes: [.squat: 12])
        XCTAssertEqual(after.vars[.squat], 1, "the probe is not counted")
        XCTAssertEqual(after.doses[.squat], 9, "the honest number set the dose")
        XCTAssertNil(after.shown[.squat]?[2], "and nothing was recorded for the new variation")
        XCTAssertTrue(after.lastHard.contains(.squat))
    }

    /// A skipped exercise resolves nothing: the pattern was not trained.
    func testSkippedExerciseResolvesNoProbe() throws {
        let start = squatAtCeiling()
        let session = Engine.generateSession(start)
        let after = Engine.applyFeedback(state: start, session: session, result: .plan,
                                         overrides: [:], skipped: [.squat], gapDays: nil,
                                         probes: [.squat: 12])
        XCTAssertEqual(after.vars[.squat], 1)
        XCTAssertNil(after.shown[.squat]?[2])
    }

    // MARK: - §40.3 · honest numbers, both ways

    /// A fact ABOVE the plan sets the next dose to what was shown — not to
    /// "plan + 1". This is the one mechanism that walks a person back to their
    /// own level after the clean start of 3.0, and `maxUp` does not bound it.
    func testFactAbovePlanAdoptsWhatWasShown() throws {
        let start = EngineState.initial
        let session = Engine.generateSession(start)
        let after = Engine.applyFeedback(state: start, session: session, result: .plan,
                                         overrides: [.squat: 12], skipped: [], gapDays: nil,
                                         probes: [:])
        XCTAssertEqual(after.doses[.squat], 12)
        XCTAssertEqual(after.sub[.squat] ?? 0, 0)
        XCTAssertEqual(after.shown[.squat]?[1], 12)
        XCTAssertEqual(after.vars[.squat], 1, "a fact can never jump a variation")
    }

    /// A fact BELOW the floor of the variation sends the pattern one variation
    /// down, landing in the journal — not on the floor of a tier, because
    /// there are no tier floors.
    ///
    /// RE-MARKED §41.1 (v3.1, 26.08.2026), class: change of semantics. The old
    /// expectation was `doses == 11`, the journal's CEILING. The trainee is
    /// leaving "Bulgarian split squats" at 3×8 per side — work 48; landing on
    /// 3×11 would be 66, a 37 % rise straight after they showed a fact below
    /// the variation's floor. The landing now walks down and stops at 8: work
    /// 48, exactly what they were doing.
    func testFactBelowTheFloorLandsNoHeavier() throws {
        let start = state(.squat, variation: 3, dose: 8, Seed(shown: [2: 11, 3: 8]))
        let session = Engine.generateSession(start)
        let after = Engine.applyFeedback(state: start, session: session, result: .plan,
                                         overrides: [.squat: 2], skipped: [], gapDays: nil,
                                         probes: [:])
        XCTAssertEqual(after.vars[.squat], 2)
        XCTAssertEqual(after.doses[.squat], 8, "the point of return, but never heavier (§41.1)")
        XCTAssertTrue(Engine.noHarder(.squat, from: start.position(.squat),
                                      to: after.position(.squat), shown: start.shown),
                      "a descent may not add work")
        XCTAssertEqual(after.sets[.squat] ?? EngineConfig.setsBase, 3)
        XCTAssertTrue(after.lastHard.contains(.squat))
    }

    /// Two appearances per variation is what §40.8 promises the walk back
    /// costs, and here it is: floor → own numbers → ceiling → probe.
    func testWalkingBackTakesTwoAppearancesPerVariation() throws {
        var s = EngineState.initial
        var appearances = 0
        // Appearance 1: the plan is 3×4, the person does 20.
        while s.vars[.squat] != 3, appearances < 8 {
            let session = Engine.generateSession(s)
            guard let squat = session.exercises.first(where: { $0.pattern == .squat }) else {
                s.counter += 1
                continue
            }
            appearances += 1
            var overrides: [Pattern: Double] = [:]
            var probes: [Pattern: Int] = [:]
            if squat.probe != nil {
                probes[.squat] = 20         // the new variation is comfortably there
            } else {
                overrides[.squat] = 20      // an honest number well above the plan
            }
            s = Engine.applyFeedback(state: s, session: session, result: .plan,
                                     overrides: overrides, skipped: [], gapDays: nil,
                                     probes: probes)
        }
        XCTAssertEqual(s.vars[.squat], 3, "the Bulgarian split squat")
        XCTAssertEqual(appearances, 4, "§40.8 promised «about five»; the engine does it in four")
    }

    // MARK: - И2 · nothing is ever assigned that was not shown

    /// The ceiling on every assignment, swept over a long mixed trajectory:
    /// the highest dose in any plan is at most one rung above the journal of
    /// the variation it belongs to.
    func testAssignedDoseNeverExceedsWhatWasShownPlusOneRung() throws {
        var s = EngineState.initial
        s.hasBar = true
        let answers: [FeedbackResult] = [.plan, .more, .plan, .plan, .more, .less, .plan, .more]
        for step in 0..<120 {
            let session = Engine.generateSession(s)
            for ex in session.exercises {
                let journal = s.shown[ex.pattern]?[ex.variation] ?? Dose.grid(ex.unit).min
                let top = ex.load + ((ex.loads?.contains { $0 > ex.load } ?? false)
                                     ? Dose.grid(ex.unit).step : 0)
                XCTAssertLessThanOrEqual(
                    top, journal + Dose.grid(ex.unit).step,
                    "step \(step) \(ex.pattern.rawValue) v\(ex.variation): "
                    + "assigned \(top) against a journal of \(journal)")
                XCTAssertGreaterThanOrEqual(ex.sets, EngineConfig.setsFloor)
            }
            var probes: [Pattern: Int] = [:]
            for ex in session.exercises where ex.probe != nil {
                probes[ex.pattern] = Dose.grid(ex.probe!.unit).min
            }
            s = Engine.applyFeedback(state: s, session: session,
                                     result: answers[step % answers.count],
                                     overrides: [:], skipped: [], gapDays: 7.0 / 3.0,
                                     probes: probes)
        }
    }

    /// Entry into a variation is ALWAYS 3×4 (3×15 s), on every path a sweep
    /// can reach: the only door is a probe, and the probe sets the floor.
    func testEveryVariationEntryIsThreeByTheFloor() throws {
        var s = EngineState.initial
        s.hasBar = true
        var entries = 0
        for _ in 0..<200 {
            let before = s.vars
            let session = Engine.generateSession(s)
            var probes: [Pattern: Int] = [:]
            for ex in session.exercises where ex.probe != nil {
                probes[ex.pattern] = Dose.grid(ex.probe!.unit).min
            }
            s = Engine.applyFeedback(state: s, session: session, result: .more,
                                     overrides: [:], skipped: [], gapDays: 7.0 / 3.0,
                                     probes: probes)
            for p in Pattern.allCases where s.vars[p]! > before[p]! {
                entries += 1
                XCTAssertEqual(s.doses[p], Dose.grid(Library.unit(p, s.vars[p]!)).min,
                               "\(p.rawValue): entry at the floor")
                XCTAssertEqual(s.sets[p] ?? EngineConfig.setsBase, EngineConfig.setsBase,
                               "\(p.rawValue): entry on three sets")
                XCTAssertEqual(s.sub[p] ?? 0, 0, "\(p.rawValue): entry with no sub-step")
                XCTAssertEqual(s.cutOf(p), 0, "\(p.rawValue): entry with nothing cut")
            }
        }
        XCTAssertGreaterThan(entries, 20, "the sweep must actually reach some entries")
    }

    // MARK: - §40.1 · the one unit boundary

    /// `pull_bar` 2→3 crosses from seconds to reps. The ratio of `w` is
    /// undefined there, so the density invariant skips it and the only way
    /// across is a probe — in BOTH directions the journal keeps its own unit.
    func testPullBarUnitBoundaryIsCrossedByProbeOnly() throws {
        let entry = ExerciseLibrary.entry(for: .pullBar)
        XCTAssertEqual(entry.variation(2).unit, .hold)
        XCTAssertEqual(entry.variation(3).unit, .reps)
        XCTAssertTrue(entry.probeOnly(variation: 3))

        // Up: 45 s on the scapular hang, probe for 4 reps of the negative.
        let start = state(.pullBar, variation: 2, dose: 45,
                          Seed(shown: [1: 45, 2: 45], counter: 1, hasBar: true))
        let session = Engine.generateSession(start)
        let bar = try exercise(session, .pullBar)
        XCTAssertEqual(bar.unit, .hold)
        let probe = try XCTUnwrap(bar.probe)
        XCTAssertEqual(probe.unit, .reps)
        XCTAssertEqual(probe.load, 4)

        let up = Engine.applyFeedback(state: start, session: session, result: .plan,
                                      overrides: [:], skipped: [], gapDays: nil,
                                      probes: [.pullBar: 5])
        XCTAssertEqual(up.vars[.pullBar], 3)
        XCTAssertEqual(up.doses[.pullBar], 4)
        XCTAssertEqual(up.shown[.pullBar]?[3], 5)

        // Down: an honest zero on the negative sends the branch back to the
        // hang — at the seconds the journal remembers, but never at a load
        // heavier than the one just refused.
        //
        // RE-MARKED §41.1 (v3.1, 26.08.2026), class: change of semantics. The
        // old expectation was 45 s, the journal's ceiling. This is one of the
        // three boundaries of accepted gap §41.6 item 1 — a unit change, where
        // reps and seconds have no defined ratio — so the landing takes the
        // grid floor of the hold, which is the lightest thing that exists.
        var back = up
        back.counter = 1
        let session2 = Engine.generateSession(back)
        let down = Engine.applyFeedback(state: back, session: session2, result: .plan,
                                        overrides: [.pullBar: 0], skipped: [], gapDays: nil,
                                        probes: [:])
        XCTAssertEqual(down.vars[.pullBar], 2)
        XCTAssertEqual(down.doses[.pullBar], 15, "the floor of the hold grid, not its ceiling")
        XCTAssertEqual(Library.unit(.pullBar, down.vars[.pullBar]!), .hold)
    }
}
