//
//  Everything §40.7 lists under "not touched": the rotation and the slots, the
//  bar gate, the counter and the double-feedback guard, the skip, the breaks,
//  the sanitizer — plus the invariants that outlived the level (И4, И6).
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineTests: XCTestCase {

    // MARK: - Rotation and slots

    /// The pull slot stands in every session; over eight sessions each
    /// rotating pattern comes up exactly five times.
    func testPullInEverySessionAndRotationCoverage() {
        var counts: [Pattern: Int] = [:]
        var state = EngineState.initial
        for _ in 0..<8 {
            let session = Engine.generateSession(state)
            XCTAssertEqual(session.exercises.count, EngineConfig.patternsPerSession)
            XCTAssertTrue(session.exercises.contains { $0.pattern == .pull },
                          "the pull slot is fixed")
            for ex in session.exercises { counts[ex.pattern, default: 0] += 1 }
            state.counter += 1
        }
        XCTAssertEqual(counts[.pull], 8)
        for p in Pattern.ordered where p != .pull {
            XCTAssertEqual(counts[p], 5, "\(p.rawValue) must appear five times in eight")
        }
    }

    /// The exercises of a session come out in the canonical order, never in
    /// the order the rotation happened to pick them.
    func testSessionExercisesFollowCanonicalOrder() {
        for counter in 0..<16 {
            var state = EngineState.initial
            state.counter = counter
            let order = Engine.generateSession(state).exercises.map(\.pattern)
            let ranks = order.map { p -> Int in
                Pattern.ordered.firstIndex(of: p == .pullBar ? .pull : p) ?? -1
            }
            XCTAssertEqual(ranks, ranks.sorted(), "session \(counter + 1) is out of order")
        }
    }

    /// With the bar on, the odd sessions hand the pull slot to the vertical
    /// branch — and with it off, the branch never appears.
    func testHasBarAlternatesThePullSlot() {
        var state = EngineState.initial
        state.hasBar = true
        for counter in 0..<8 {
            state.counter = counter
            let patterns = Engine.generateSession(state).exercises.map(\.pattern)
            XCTAssertTrue(patterns.contains(counter % 2 == 1 ? .pullBar : .pull),
                          "session \(counter + 1) took the wrong branch")
            XCTAssertFalse(patterns.contains(counter % 2 == 1 ? .pull : .pullBar))
        }
        state.hasBar = false
        for counter in 0..<8 {
            state.counter = counter
            XCTAssertFalse(Engine.generateSession(state).exercises.contains { $0.pattern == .pullBar },
                           "with no bar the vertical branch is never planned")
        }
    }

    /// The two branches of the pull slot keep their own positions.
    func testPullBranchesAreIndependent() {
        var state = EngineState.initial
        state.hasBar = true
        state.vars[.pullBar] = 5
        state.doses[.pullBar] = 7
        state.counter = 1
        let bar = Engine.generateSession(state).exercises.first { $0.pattern == .pullBar }
        XCTAssertEqual(bar?.variation, 5)
        XCTAssertEqual(bar?.load, 7)
        XCTAssertEqual(state.vars[.pull], 1, "the horizontal branch did not move")
    }

    // MARK: - Growth, parking and the floor

    /// Answering "on plan" forever climbs the whole ladder — through probes,
    /// which are the only door — and ends parked on the top variation's last
    /// band. Growth never crosses a variation on its own.
    func testAlwaysPlanClimbsToTheTopAndParks() {
        var state = EngineState.initial
        // The longest ladders are seven variations of twelve rungs each, and
        // the top ones cap growth at one event per appearance — so the walk to
        // the very top is long by construction, not by accident.
        for _ in 0..<1500 {
            let session = Engine.generateSession(state)
            var probes: [Pattern: Int] = [:]
            for ex in session.exercises where ex.probe != nil {
                probes[ex.pattern] = Dose.grid(ex.probe!.unit).min
            }
            state = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [:], skipped: [], gapDays: nil,
                                         probes: probes)
        }
        for p in Pattern.ordered {
            XCTAssertEqual(state.vars[p], Library.count(p), "\(p.rawValue): the top variation")
            XCTAssertEqual(state.sets[p] ?? EngineConfig.setsBase, EngineConfig.setsMax,
                           "\(p.rawValue): the last band")
            XCTAssertEqual(state.doses[p], Dose.grid(Library.unit(p, state.vars[p]!)).max,
                           "\(p.rawValue): the top of the grid")
        }
    }

    /// Answering "hard" forever lands on the bottom of the whole ladder and
    /// stops there: first variation, floor of the grid, floor of the sets.
    func testAlwaysLessFloorsAtTheBottom() {
        var state = EngineState.initial
        state.vars[.squat] = 4
        state.doses[.squat] = 9
        for _ in 0..<200 {
            let session = Engine.generateSession(state)
            state = Engine.applyFeedback(state: state, session: session, result: .less,
                                         overrides: [:], skipped: [], gapDays: nil, probes: [:])
        }
        for p in Pattern.ordered {
            XCTAssertEqual(state.vars[p], 1, "\(p.rawValue): the bottom variation")
            XCTAssertEqual(state.doses[p], Dose.grid(Library.unit(p, 1)).min,
                           "\(p.rawValue): the floor of the grid")
            XCTAssertEqual(Engine.setsAfterCut(sets: state.sets[p] ?? EngineConfig.setsBase,
                                               cut: state.cutOf(p)),
                           EngineConfig.setsFloor, "\(p.rawValue): the floor of the sets")
        }
    }

    /// Three shortfalls in a row deload the movement by whole rungs of dose.
    func testDeloadFiresOnTheThirdConsecutiveShortfall() {
        var state = EngineState.initial
        state.doses[.squat] = 12
        state.shown[.squat] = [1: 12]
        for round in 1...3 {
            // The squat only stands in the odd sessions of the rotation, and a
            // streak is counted in APPEARANCES — so put it back in every time
            // rather than letting the rotation silently skip a round.
            state.counter = 0
            let session = Engine.generateSession(state)
            let before = state.doses[.squat]!
            state = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [.squat: before - 1], skipped: [],
                                         gapDays: nil, probes: [:])
            if round < 3 {
                XCTAssertEqual(state.failStreak[.squat], round)
            } else {
                XCTAssertEqual(state.failStreak[.squat], 0, "the streak resets on the deload")
            }
        }
        // Two honest shortfalls take it to 10; the third takes it to 9 and the
        // deload then drops three more rungs.
        XCTAssertEqual(state.doses[.squat], 6)
    }

    // MARK: - The skip (v2.1.1)

    func testSkippedPatternKeepsItsPositionAndStreak() {
        var state = EngineState.initial
        state.failStreak[.squat] = 2
        let session = Engine.generateSession(state)
        let after = Engine.applyFeedback(state: state, session: session, result: .more,
                                         overrides: [:], skipped: [.squat], gapDays: nil,
                                         probes: [:])
        XCTAssertEqual(after.doses[.squat], state.doses[.squat], "an untrained pattern does not move")
        XCTAssertEqual(after.failStreak[.squat], 2, "and its streak is frozen, not reset")
        XCTAssertNil(after.shown[.squat], "and nothing is written to its journal")
        XCTAssertGreaterThan(after.doses[.pushH]! + (after.sub[.pushH] ?? 0),
                             state.doses[.pushH]!, "the rest of the session still moved")
    }

    func testSkipBeatsAnOverride() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [.squat: 14], skipped: [.squat],
                                         gapDays: nil, probes: [:])
        XCTAssertEqual(after.doses[.squat], 4, "the fact for a skipped movement is ignored")
        XCTAssertNil(after.shown[.squat])
    }

    func testAllSkippedAdvancesOnlyTheCounter() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        let skipped = Set(session.exercises.map(\.pattern))
        let after = Engine.applyFeedback(state: state, session: session, result: .more,
                                         overrides: [:], skipped: skipped, gapDays: nil,
                                         probes: [:])
        XCTAssertEqual(after.counter, 1)
        XCTAssertEqual(after.vars, state.vars)
        XCTAssertEqual(after.doses, state.doses)
        XCTAssertTrue(after.shown.isEmpty)
    }

    /// A fact about a movement that is not in today's session is dropped — the
    /// trap the fixture's own author-guard exists to catch.
    func testFactForAMovementOutsideTheSessionIsIgnored() {
        var state = EngineState.initial
        state.counter = 0
        let session = Engine.generateSession(state)
        XCTAssertFalse(session.exercises.contains { $0.pattern == .calf })
        let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [.calf: 13], skipped: [], gapDays: nil,
                                         probes: [:])
        XCTAssertEqual(after.doses[.calf], state.doses[.calf])
        XCTAssertNil(after.shown[.calf])
    }

    // MARK: - Determinism and the double-feedback guard (И6)

    func testDeterminism() {
        var a = EngineState.initial
        var b = EngineState.initial
        for _ in 0..<40 {
            let sa = Engine.generateSession(a)
            let sb = Engine.generateSession(b)
            XCTAssertEqual(sa, sb)
            a = Engine.applyFeedback(state: a, session: sa, result: .more, overrides: [.pull: 7],
                                     skipped: [], gapDays: 2.0, probes: [:])
            b = Engine.applyFeedback(state: b, session: sb, result: .more, overrides: [.pull: 7],
                                     skipped: [], gapDays: 2.0, probes: [:])
        }
        XCTAssertEqual(a, b)
    }

    /// The same (state, session) pair fed back twice is a silent no-op.
    func testReplayedFeedbackIsANoOp() {
        let state = EngineState.initial
        let session = Engine.generateSession(state)
        let once = Engine.applyFeedback(state: state, session: session, result: .plan,
                                        overrides: [:], skipped: [], gapDays: nil, probes: [:])
        let twice = Engine.applyFeedback(state: once, session: session, result: .plan,
                                         overrides: [:], skipped: [], gapDays: nil, probes: [:])
        XCTAssertEqual(twice, once)
    }

    // MARK: - Breaks

    /// The silent decay acts only inside the blind zone of 7…13 days.
    func testSilentDecayActsOnlyInsideTheBlindZone() {
        var state = EngineState.initial
        state.doses[.squat] = 10
        for gap in [0, 3, 6, 14, 40] {
            XCTAssertEqual(Engine.applySilentDecay(state: state, gapDays: gap).doses[.squat], 10,
                           "gap \(gap) is outside the blind zone")
        }
        for gap in [7, 10, 13] {
            XCTAssertEqual(Engine.applySilentDecay(state: state, gapDays: gap).doses[.squat], 9,
                           "gap \(gap) costs exactly one rung")
        }
    }

    /// §14.2, and now BY CONSTRUCTION: a decay plus a weakened comeback is the
    /// plain comeback. Walking one step and then drop−1 steps is walking drop
    /// steps, because every mechanism walks the same rungs.
    func testDecayPlusWeakenedComebackEqualsPlainComeback() {
        var state = EngineState.initial
        state.vars[.squat] = 4
        state.doses[.squat] = 9
        state.vars[.coreAntiExt] = 3
        state.doses[.coreAntiExt] = 35
        state.shown = [.squat: [3: 12, 4: 9], .coreAntiExt: [2: 30, 3: 35]]

        let peeked = Engine.applyComeback(
            state: Engine.applySilentDecay(state: state, gapDays: 10),
            gapDays: 30, alreadyDecayed: true)
        let plain = Engine.applyComeback(state: state, gapDays: 30, alreadyDecayed: false)
        XCTAssertEqual(peeked.vars, plain.vars)
        XCTAssertEqual(peeked.doses, plain.doses)
        XCTAssertEqual(peeked.sub, plain.sub)
        XCTAssertEqual(peeked.cut, plain.cut)
        XCTAssertEqual(peeked.sets, plain.sets)
    }

    /// A comeback never moves the counter — a break is not a training event.
    func testComebackLeavesTheCounterAlone() {
        var state = EngineState.initial
        state.counter = 11
        let after = Engine.applyComeback(state: state, gapDays: 40, alreadyDecayed: false)
        XCTAssertEqual(after.counter, 11)
        XCTAssertEqual(after.returnRun, 1)
        XCTAssertEqual(after.rampWindow, EngineConfig.rampWindowSessions)
    }

    // MARK: - Handles (§37.4 rewritten by §40.6)

    /// "Give me something easier" lands in the JOURNAL of the variation below,
    /// not on a floor — there are no tier floors in v3.
    func testEasierVariationLandsInTheJournal() {
        var state = EngineState.initial
        state.vars[.squat] = 3
        state.doses[.squat] = 7
        state.shown = [.squat: [2: 11, 3: 7]]
        let after = Engine.easierVariation(state: state, pattern: .squat)
        XCTAssertEqual(after.vars[.squat], 2)
        XCTAssertEqual(after.doses[.squat], 11, "back to what was actually done there")
        XCTAssertEqual(after.sets[.squat] ?? EngineConfig.setsBase, EngineConfig.setsBase)
    }

    /// On the first variation the handle is inert: there is nothing below it.
    func testEasierVariationIsInertOnTheFirstRung() {
        let state = EngineState.initial
        XCTAssertEqual(Engine.easierVariation(state: state, pattern: .squat), state)
    }

    /// И4: no path of descent may make the plan heavier. Swept over every
    /// variation and every rung of every ladder, from a journal that remembers
    /// the ceiling of the variation below.
    func testNoDescentEverMakesThePlanHeavier() {
        for p in Pattern.allCases {
            var shown: [Int: Int] = [:]
            for v in 1...Library.count(p) { shown[v] = Dose.grid(Library.unit(p, v)).max }
            let journal: [Pattern: [Int: Int]] = [p: shown]
            for v in 1...Library.count(p) {
                let grid = Dose.grid(Library.unit(p, v))
                for rung in 0..<Dose.rungCount(Library.unit(p, v)) {
                    let from = Position(variation: v, sets: EngineConfig.setsBase,
                                        dose: Dose.dose(Library.unit(p, v), atRung: rung),
                                        sub: 0, cut: 0)
                    for steps in 1...4 {
                        let to = Engine.fallBy(p, from, steps, shown: journal)
                        XCTAssertTrue(Engine.noHarder(p, from: from, to: to, shown: journal),
                                      "\(p.rawValue) v\(v) at \(grid.min + rung * grid.step) "
                                      + "descending \(steps)")
                    }
                }
            }
        }
    }

    // MARK: - The sanitizer

    /// A file written by a future version, opened after a downgrade: entries
    /// for unknown patterns are dropped rather than failing the whole decode.
    func testUnknownPatternDecodesLeniently() throws {
        let json = #"""
        {"counter":3,"vars":["squat",2,"kettlebell_swing",9],
         "doses":["squat",7,"kettlebell_swing",99],"failStreak":["squat",1]}
        """#
        let state = try JSONDecoder().decode(EngineState.self, from: Data(json.utf8))
        XCTAssertEqual(state.vars[.squat], 2)
        XCTAssertEqual(state.doses[.squat], 7)
        XCTAssertEqual(state.vars.count, 1, "the unknown pattern was dropped")
        XCTAssertEqual(state.sanitized().vars.count, Pattern.allCases.count,
                       "and the sanitizer fills the rest in")
    }

    /// A corrupt counter must not feed the rotation: it would index out of
    /// bounds, and near Int.max it would trap the process on every plan.
    func testGarbageCounterIsHealed() throws {
        let json = #"""
        {"counter":-5,"vars":["squat",1],"doses":["squat",4],"failStreak":["squat",0]}
        """#
        let state = try JSONDecoder().decode(EngineState.self, from: Data(json.utf8))
        XCTAssertEqual(state.counter, 0)
        XCTAssertEqual(Engine.generateSession(state).sessionNumber, 1)
    }

    /// Out-of-range coordinates are healed, not preserved: a variation past
    /// the ladder, a dose off the grid, a band on a variation that has none.
    func testOutOfRangePositionsAreHealed() {
        var state = EngineState.initial
        state.vars[.squat] = 99
        state.doses[.squat] = 37
        state.sets[.lunge] = 5          // not the top variation — no bands there
        state.sub[.hinge] = 9
        state.cut[.calf] = 9
        let clean = state.sanitized()
        XCTAssertEqual(clean.vars[.squat], Library.count(.squat))
        XCTAssertEqual(clean.doses[.squat], 15, "clamped to the top of the grid")
        XCTAssertEqual(clean.sets[.lunge] ?? EngineConfig.setsBase, EngineConfig.setsBase)
        XCTAssertEqual(clean.sub[.hinge] ?? 0, 2, "at most sets − 1")
        XCTAssertEqual(clean.cutOf(.calf), EngineConfig.setsBase - EngineConfig.setsFloor)
    }

    // MARK: - What the plan says

    func testDisplayStringsAreWellFormed() {
        var state = EngineState.initial
        state.doses[.squat] = 9
        state.sub[.squat] = 1
        state.vars[.coreAntiExt] = 3
        state.doses[.coreAntiExt] = 30
        state.vars[.lunge] = 2
        let session = Engine.generateSession(state)
        for ex in session.exercises {
            XCTAssertFalse(ex.display.isEmpty)
            XCTAssertFalse(ex.name.isEmpty)
            if ex.loads == nil {
                XCTAssertTrue(ex.display.contains("\(ex.sets)×\(ex.load)"),
                              "\(ex.pattern.rawValue): a uniform plan reads N×dose")
            } else {
                XCTAssertTrue(ex.display.contains("-"),
                              "\(ex.pattern.rawValue): an uneven plan reads 9-8-8")
            }
        }
    }

    /// The announced duration is a real number of minutes, and the probe is
    /// inside it: a session with a probe is not shorter than the same session
    /// without one.
    func testDurationCountsTheProbe() throws {
        var withProbe = EngineState.initial
        withProbe.doses[.squat] = 15
        withProbe.shown[.squat] = [1: 15]
        var noProbe = withProbe
        noProbe.lastHard = [.squat]

        let a = Engine.generateSession(withProbe)
        let b = Engine.generateSession(noProbe)
        XCTAssertNotNil(try XCTUnwrap(a.exercises.first { $0.pattern == .squat }).probe)
        XCTAssertNil(try XCTUnwrap(b.exercises.first { $0.pattern == .squat }).probe)
        XCTAssertGreaterThan(a.estimatedTotalMin, 0)
        XCTAssertEqual(a.estimatedTotalMin, b.estimatedTotalMin, accuracy: 2.0,
                       "the probe replaces a set, it does not add a block of work")
    }
}
