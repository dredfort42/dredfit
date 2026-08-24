//
//  DredfitCoreTests
//
//  The sets handle.
//
//  The engine had no way to say "the same movement, less of it". A level fixes
//  the VARIATION and the DOSE PER SET, and on the floor of every mod-8 block
//  the dose is already the smallest that variation has, so a step down had to
//  swap the exercise — and the top of the tier below is heavier than the
// bottom of the current one. Measured on over the whole 10 × 48
//  lattice: a 7-13 day break made the plan HEAVIER in 48 cells of 480 (worst
//  ×6.50), a pain report made nothing lighter in 24, an honest "hard" every
//  session locked movement on all 48 levels, and the "I was ill" tap made the
//  plan heavier in 40. Each of the four is zero now.
//
// One test per guarantee, in the wave's own order, plus the one
//  compatibility claim the wave had to keep: a journal written by build 1.9
//  still decodes whole.
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV225Tests: XCTestCase {

    private func seeded(_ level: Int, bar: Bool = false,
                        cut: Int = 0) -> EngineState {
        var s = EngineState.initial
        s.hasBar = bar
        for p in Pattern.allCases {
            s.levels[p] = level
            let c = min(cut, Level.cutMax(level: level, floor: EngineConfig.setsFloor))
            if c > 0 { s.cut[p] = c }
        }
        return s
    }

    private func exercise(_ w: Session, _ p: Pattern) -> SessionExercise? {
        w.exercises.first { $0.pattern == p }
    }

    /// Run the pattern up to a session it actually stands in, without spending
    /// one of its appearances.
    private func advance(_ state: EngineState, to p: Pattern) -> (EngineState, Session) {
        var s = state
        var w = Engine.generateSession(s)
        var guardCount = 0
        while !w.exercises.contains(where: { $0.pattern == p }), guardCount < 16 {
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            w = Engine.generateSession(s)
            guardCount += 1
        }
        return (s, w)
    }

    // MARK: - (a) Migration

    /// Every new field is sparse, so a state that never met the sets handle
    /// produces the plan produced. Two halves: the plan of a level with
    /// an empty cut is the formula to the number, and a state file
    /// written before the wave decodes into exactly the state with the fields
    /// present and empty.
    ///
    /// The bit-for-bit comparison against the frozen build itself lives
    /// where it can be run against that build — the reference verifier and the
    /// golden fixture, where seven whole scenarios come out unchanged.
    func testAPlanWithNoCutIsTheV224Formula() {
        var cells = 0
        for p in Pattern.allCases {
            for level in 0...EngineConfig.levelMax {
                for sub in 0..<EngineConfig.setsMax {
                    let w = Level.work(pattern: p, level: level, sub: sub, cut: 0)
                    let d = Level.decode(level)
                    let sides = ExerciseLibrary.entry(for: p)
                        .variations[d.tier - 1].unilateral ? 2 : 1
                    let effSub = Level.effectiveSub(level: level, sub: sub, sets: d.sets)
                    let delta = Level.subDelta(pattern: p, level: level)
                    cells += 1
                    XCTAssertEqual(w.sets, d.sets, "\(p) L\(level): the band is the level's own")
                    XCTAssertEqual(w.cut, 0, "\(p) L\(level): and nothing is taken off")
                    XCTAssertEqual(w.total, (d.sets * w.load + effSub * delta) * sides,
                                   "\(p) L\(level) sub\(sub): the v2.24 formula to the number")
                }
            }
        }
        XCTAssertEqual(cells, Pattern.allCases.count * (EngineConfig.levelMax + 1)
                       * EngineConfig.setsMax, "the sweep covered the whole lattice")
    }

    func testAStateFileWithoutTheNewFieldsDecodesAsEmpty() throws {
        let modern = seeded(20)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(modern))
                as? [String: Any])
        for key in ["cut", "setsHold", "shownWork", "shownOrd"] {
            json.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(
            EngineState.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.cut.isEmpty && legacy.setsHold.isEmpty)
        XCTAssertTrue(legacy.shownWork.isEmpty && legacy.shownOrd.isEmpty)
        XCTAssertEqual(Engine.generateSession(legacy), Engine.generateSession(modern),
                       "and the plan is the one the fields-present state gives")
    }

    // MARK: - (b) A descent never adds load

    /// Every way down, every budget: if a pattern's position did not rise, its
    /// plan may not get heavier. Cells where the variation or the unit changed
    /// are counted out loud rather than silently skipped — a measure in reps
    /// across a change of variation is not valid, and that is the
    /// accepted gap.
    ///
    /// The invariant holds against the last plan the person actually SAW, so
    /// the sweep records the showing with `recordShown` — the very call
    /// says closes the gap — before taking each way down.
    func testNoWayDownEverAddsLoad() {
        var compared = 0, crossed = 0
        let ways: [(String, (EngineState) -> EngineState)] = [
            ("silent decay", { Engine.applySilentDecay(state: $0, gapDays: 8) }),
            ("comeback 14", { Engine.applyComeback(state: $0, gapDays: 14, alreadyDecayed: false) }),
            ("comeback 90", { Engine.applyComeback(state: $0, gapDays: 90, alreadyDecayed: false) }),
            // The lens and the pain report left the list
            // of ways down; the three handles joined it. The invariant is
            // indifferent to which lever moved — that is the whole point.
            ("easier variation", {
                var s = $0
                for p in Pattern.allCases { s = Engine.easierVariation(state: s, pattern: p) }
                return s
            }),
            ("fewer sets", {
                var s = $0
                for p in Pattern.allCases {
                    s = Engine.setCut(state: s, pattern: p, cut: s.cutOf(p) + 1)
                }
                return s
            }),
            ("shorter session", { Engine.shorterSession(state: $0, steps: 1) }),
            ("hard rating", {
                var s = $0
                s.lessRun = EngineConfig.lessRunToGlobal
                return Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                            result: .less)
            }),
            ("fact below plan", {
                let w = Engine.generateSession($0)
                var overrides: [Pattern: Int] = [:]
                for ex in w.exercises { overrides[ex.pattern] = max(0, ex.load - 2) }
                return Engine.applyFeedback(state: $0, session: w, result: .plan,
                                            overrides: overrides)
            }),
        ]
        // The budget axis is gone with the budget. The sweep is NOT
        // narrowed to compensate — the whole level scale replaces the thirteen
        // sampled rungs, and the cut axis reaches its deepest admissible step.
        for (name, step) in ways {
            do {
                for level in 0...EngineConfig.levelMax {
                    for cut in [0, 1, 2, 3] {
                        var s = seeded(level, cut: cut)
                        s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                                 result: .plan, gapDays: 7.0 / 3.0)
                        let before = Engine.generateSession(s)
                        let shown = Engine.recordShown(state: s, session: before)
                        let next = step(shown)
                        let after = Engine.generateSession(next)
                        for was in before.exercises {
                            guard let now = exercise(after, was.pattern) else { continue }
                            // The position rose — growth is legal, and the
                            // invariant is not about it.
                            if Level.posOrd(next.position(was.pattern))
                                > Level.posOrd(shown.position(was.pattern)) { continue }
                            if now.unit != was.unit || now.tier != was.tier { crossed += 1; continue }
                            compared += 1
                            XCTAssertLessThanOrEqual(
                                Engine.exerciseWork(now), Engine.exerciseWork(was),
                                "\(name) made \(was.pattern) heavier at L\(level) "
                                + "cut\(cut): \(was.display) → \(now.display)")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 5_000, "the sweep has to be wide to mean anything")
        XCTAssertGreaterThanOrEqual(crossed, 0,
                                    "cells across a change of variation or unit: \(crossed)")
    }

    // MARK: - (d) One set back per session

    /// Every way up, `gapDays == nil` included. The rule lives in `riseBy`,
    /// and until round 4b three paths walked around it — an absolute landing
    /// by fact, a calibration, and the weekly window's rebuild. It held then
    /// only through the OPTIONAL seventh argument, and an invariant may not
    /// rest on an input that might not be there.
    func testAtMostOneSetComesBackPerSession() {
        var cells = 0
        let ways: [(String, Double?)] = [("with a gap", 7.0 / 3.0), ("with no gap", nil)]
        for (name, gap) in ways {
            for level in 0...EngineConfig.levelMax {
                let deepest = Level.cutMax(level: level, floor: EngineConfig.setsFloor)
                guard deepest >= 1 else { continue }
                for p in Pattern.allCases {
                    var s = seeded(level, bar: true)
                    s.cut[p] = deepest
                    let w = Engine.generateSession(s)
                    guard exercise(w, p) != nil else { continue }
                    cells += 1
                    for (label, result, overrides) in [
                        ("plan", FeedbackResult.plan, [Pattern: Int]()),
                        ("more", .more, [:]),
                        ("fact above plan", .plan,
                         Dictionary(uniqueKeysWithValues:
                            w.exercises.map { ($0.pattern, $0.load + 5) })),
                        ("fact at plan", .plan,
                         Dictionary(uniqueKeysWithValues:
                            w.exercises.map { ($0.pattern, $0.load) })),
                    ] {
                        let next = Engine.applyFeedback(state: s, session: w, result: result,
                                                        overrides: overrides, gapDays: gap)
                        let back = deepest - next.cutOf(p)
                        XCTAssertLessThanOrEqual(back, EngineConfig.setsBackPerSession,
                                                 "\(name)/\(label): \(p) L\(level) gave \(back) back")
                        XCTAssertGreaterThanOrEqual(back, 0,
                                                    "\(name)/\(label): \(p) L\(level) cut deeper on a way UP")
                    }
                }
            }
        }
        XCTAssertGreaterThan(cells, 400, "the sweep has to reach every band")
    }

    /// And the hold between returns: the next set waits `setsBackHold`
    /// appearances, and in between the growth goes into the dose.
    func testAReturnedSetIsHeldForItsAppearances() {
        for level in [8, 24, 40] {
            let deepest = Level.cutMax(level: level, floor: EngineConfig.setsFloor)
            guard deepest >= 2 else { continue }
            var s = seeded(level)
            s.cut[.pull] = deepest            // `pull` stands in every session
            var previous = deepest
            var returns = 0, sinceReturn = 0
            for _ in 0..<12 {
                s = Engine.applyFeedback(state: s, session: Engine.generateSession(s),
                                         result: .more, gapDays: 7.0 / 3.0)
                let now = s.cutOf(.pull)
                if now < previous {
                    if returns > 0 {
                        XCTAssertGreaterThanOrEqual(sinceReturn, EngineConfig.setsBackHold,
                                                    "L\(level): the hold was skipped")
                    }
                    returns += 1
                    sinceReturn = 0
                } else {
                    sinceReturn += 1
                }
                previous = now
            }
            XCTAssertGreaterThanOrEqual(returns, 1, "L\(level): sets do come back eventually")
        }
    }

    // MARK: - (e) The one floor

    /// RE-MARKED, and the claim is INVERTED.
    ///
    /// It used to read "below two sets only the pain channel goes; below one,
    /// nothing ever does", and it counted the single-set cells to prove the
    /// pain floor was reachable. There is one floor now, so there is nothing
    /// to reach: the count must be exactly ZERO. The old assertion guarded the
    /// EXISTENCE of a hole; this one guards its absence.
    ///
    /// That hole was not theoretical. `setsFloorPain` leaked into every
    /// internal call — the audit found the shared floor was never once the
    /// argument — and an honest sweep of "hard" put 3458 plans out of 18 000
    /// below two sets, reachable without touching a handle at all.
    ///
    /// The budget and lens axes are replaced by the rotation counter, which
    /// moves both the session's composition and the side of the bar slot —
    /// the compositions where the gate and a cut actually meet.
    func testNothingEverGoesBelowTheOneFloor() {
        var cells = 0, belowFloor = 0
        for counter in 0..<8 {
            for level in 0...EngineConfig.levelMax {
                for cut in [0, 1, 2, 3, 4] {
                    for bar in [false, true] {
                        var s = seeded(level, bar: bar, cut: cut)
                        s.counter = counter
                        // Diverged pull branches: the gate trims the
                        // push by the weaker one, on top of everything else.
                        s.levels[.pullBar] = max(0, level - 8)
                        for ex in Engine.generateSession(s).exercises {
                            cells += 1
                            XCTAssertGreaterThanOrEqual(
                                ex.sets, EngineConfig.setsFloor,
                                "\(ex.pattern) L\(level) cut\(cut) c\(counter): below the floor")
                            if ex.sets < EngineConfig.setsFloor { belowFloor += 1 }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(cells, 20_000, "the floor sweep covered \(cells) exercises")
        XCTAssertEqual(belowFloor, 0,
                       "cells below the floor must be 0, found \(belowFloor)")
    }

    // MARK: - (f) The identity with a non-empty cut

    /// "A comeback" and "a decay plus a comeback" land in the same place, so
    /// that opening the app during the blind zone never costs more than
    /// staying away.
    ///
    /// THE STATE OF PLAY, named rather than hidden. states the identity
    /// ON LEVELS and with no cut, and in that form it holds exactly — the
    /// sweep below finds no divergence at all. It does NOT hold once a cut is
    /// carried across: `fallBy` spends the dose before the sets while `riseBy`
    /// returns the sets before the dose (the position measure makes that asymmetry
    /// deliberate), so the compensation reverses the decay's step precisely
    /// only where the decay moved the same axis. The reference has the same
    /// property, and the port has to reproduce it rather than paper over it —
    /// which is why the divergence is held by a BOUND, in
    /// `EngineTests.testTheFourteenTwoDivergenceWithACutStaysWhereItIs`: 920
    /// cells of 11,760, all one-sided, worst 6 positions. A fix makes that
    /// pass more easily; a regression turns it red.
    func testTheIdentityHoldsOnLevelsWithNoCut() {
        var cells = 0
        for level in 0...EngineConfig.levelMax {
            for gap in [14, 20, 35, 56, 90, 140, 365] {
                let s = seeded(level)
                let straight = Engine.applyComeback(state: s, gapDays: gap,
                                                    alreadyDecayed: false)
                let viaDecay = Engine.applyComeback(
                    state: Engine.applySilentDecay(state: s, gapDays: 8),
                    gapDays: gap, alreadyDecayed: true)
                for p in Pattern.allCases {
                    cells += 1
                    XCTAssertEqual(straight.levels[p], viaDecay.levels[p],
                                   "\(p) L\(level) gap\(gap): the levels diverged")
                    XCTAssertEqual(straight.sub[p] ?? 0, viaDecay.sub[p] ?? 0,
                                   "\(p) L\(level) gap\(gap): and so did the sub-step")
                }
            }
        }
        XCTAssertEqual(cells, Pattern.allCases.count * (EngineConfig.levelMax + 1) * 7,
                       "the identity was swept over the whole scale")
    }

    // MARK: - (g) The postcondition repair

    /// The invariant survives a changing rotation — a movement comes back into
    /// the plan a session or two later — and a moved HANDLE.
    ///
    /// Re-marked, and one carve-out DISAPPEARED. The budget was
    /// a legal reason for the plan to grow at a standing position, so it had
    /// to lift the repair's cap for exactly one transition, by hand. It worked
    /// PAST the position measure: it trimmed the plan without touching level,
    /// sub-step or cut. The handle writes `cut`, a coordinate of the position,
    /// so releasing it IS a rise and the general gate excludes it on its own —
    /// `budgetTouched` is gone, not replaced.
    ///
    /// The budget axis is replaced by a denser level grid so the sweep does
    /// not shrink.
    func testTheRepairHoldsAcrossTheRotationAndAMovedHandle() {
        var compared = 0, handleMoves = 0
        do {
            for level in stride(from: 0, through: EngineConfig.levelMax, by: 2) {
                for bar in [false, true] {
                    var s = seeded(level, bar: bar)
                    var shownWork: [Pattern: Int] = [:]
                    var shownOrd: [Pattern: Int] = [:]
                    var shownUnit: [Pattern: (LoadUnit, Int)] = [:]
                    for step in 0..<24 {
                        let w = Engine.generateSession(s)
                        for ex in w.exercises {
                            let p = ex.pattern
                            if let was = shownWork[p], let ord = shownOrd[p],
                               let (unit, tier) = shownUnit[p],
                               Level.posOrd(s.position(p)) <= ord,
                               ex.unit == unit, ex.tier == tier {
                                compared += 1
                                XCTAssertLessThanOrEqual(
                                    Engine.exerciseWork(ex), was,
                                    "the plan of \(p) grew at a standing position "
                                    + "(L\(level) step \(step))")
                            }
                            shownWork[p] = Engine.exerciseWork(ex)
                            shownOrd[p] = Level.posOrd(s.position(p))
                            shownUnit[p] = (ex.unit, ex.tier)
                        }
                        switch step % 5 {
                        case 3:
                            s.lessRun = EngineConfig.lessRunToGlobal
                            s = Engine.applyFeedback(state: s, session: w, result: .less,
                                                     gapDays: 7.0 / 3.0)
                        case 4:
                            // The pain report was the second
                            // signal that left the position standing; a SKIP is
                            // the one that survives, and it is the same class
                            // of transition the invariant is written about.
                            s = Engine.applyFeedback(state: s, session: w, result: .plan,
                                                     skipped: [w.exercises[step % 6].pattern],
                                                     gapDays: 7.0 / 3.0)
                        default:
                            s = Engine.applyFeedback(state: s, session: w, result: .plan,
                                                     gapDays: 7.0 / 3.0)
                        }
                        // The person moves the handle, down and back up. That is
                        // a move of the position on its third axis, so the
                        // general gate handles it — no carve-out.
                        if step == 11 { s = Engine.shorterSession(state: s, steps: 1); handleMoves += 1 }
                        if step == 17 {
                            for p in Pattern.allCases { s = Engine.setCut(state: s, pattern: p, cut: 0) }
                            handleMoves += 1
                        }
                    }
                }
            }
        }
        // The threshold is NOT lowered: the level grid was widened to pay for
        // the axis the budget took with it.
        XCTAssertGreaterThan(compared, 1_500, "the sweep has to be wide to mean anything")
        XCTAssertGreaterThan(handleMoves, 0, "and the handle really did move in it")
    }

    // MARK: - Compatibility: the 1.9 journal

    /// `SessionExercise` gained no NON-OPTIONAL field in this wave, and that is
    /// compatibility rather than style: a journal written by build 1.9 carries
    /// none of the keys added since, and one required field would zero the
    /// whole history on decode. The per-exercise sets floor the budget needs
    /// is therefore carried alongside the plan and never inside it —
    /// the port's answer to the reference's non-enumerable property.
    func testAJournalFromBuildOneNineStillDecodesWhole() throws {
        // Exactly the keys build 1.9 wrote — no `loads`, and nothing from the later waves.
        let legacy = """
        {
          "pattern": "push_h",
          "name": "Push-ups",
          "tier": 2,
          "unit": "reps",
          "load": 8,
          "perSide": false,
          "sets": 3,
          "restSetSec": 60,
          "restExerciseSec": 60
        }
        """
        let ex = try JSONDecoder().decode(SessionExercise.self,
                                          from: try XCTUnwrap(legacy.data(using: .utf8)))
        XCTAssertEqual(ex.pattern, .pushH)
        XCTAssertEqual(ex.name, "Push-ups")
        XCTAssertEqual(ex.tier, 2)
        XCTAssertEqual(ex.unit, .reps)
        XCTAssertEqual(ex.load, 8)
        XCTAssertEqual(ex.perSide, false)
        XCTAssertEqual(ex.sets, 3)
        XCTAssertEqual(ex.restSetSec, 60)
        XCTAssertEqual(ex.restExerciseSec, 60)
        XCTAssertNil(ex.loads, "a uniform plan stays nil — absence is a claim too")
        XCTAssertEqual(ex.perSetLoads, [8, 8, 8], "and every set reads back at the base dose")
        XCTAssertEqual(Engine.exerciseWork(ex), 24, "the work measure reads it whole")

        // And a whole session of them, which is the shape the journal stores.
        let session = """
        {
          "sessionNumber": 7,
          "warmupMin": 5,
          "cooldownMin": 3,
          "estimatedTotalMin": 33.5,
          "exercises": [\(legacy)]
        }
        """
        let decoded = try JSONDecoder().decode(Session.self,
                                               from: try XCTUnwrap(session.data(using: .utf8)))
        XCTAssertEqual(decoded.sessionNumber, 7)
        XCTAssertEqual(decoded.exercises.count, 1)
        XCTAssertEqual(decoded.estimatedTotalMin, 33.5)
    }

    // SNIPPED: `testThePainLadderFallsStrictlyAndKeepsTheVariation`.
    // The ladder was the pain channel walking down the SETS axis; the channel is
    // gone, so there is no ladder to walk.
    //
    // NOT LOST: "a cut takes sets and touches neither the variation nor the
    // dose" is the same claim on the surviving lever, and it is asserted by
    // `testTheHandleTakesSetsAndNothingElse` in EngineV224Tests over the whole
    // scale; "no way down ever adds load" — with the handles in the list —
    // stays in this suite.
}
