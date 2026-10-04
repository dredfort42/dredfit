//
//  The journal a number that meets the plan leaves (§41.14), the accepted
//  corner of the sets hold, and the hold the weekly ceiling must not arm
//  (§41.15). Golden pins these through whole scenarios; the tests here name
//  each rule on its own, so a port that breaks one says which.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class JournalAndHoldTests: XCTestCase {

    // MARK: - Helpers

    /// A session in which the pattern under test stands, with the state it
    /// was generated from.
    private struct Appearance {
        let state: EngineState
        let session: Session
        let exercise: SessionExercise

        func feedback(_ result: FeedbackResult, _ overrides: [Pattern: Double] = [:],
                      gapDays: Double? = nil) -> EngineState {
            Engine.applyFeedback(state: state, session: session, result: result,
                                 overrides: overrides, gapDays: gapDays)
        }
    }

    /// Found by moving the counter alone — everything else is the state
    /// under test.
    private func appearance(_ s: EngineState, _ p: Pattern) throws -> Appearance {
        var found: Appearance?
        for c in s.counter..<(s.counter + 16) where found == nil {
            var t = s
            t.counter = c
            let session = Engine.generateSession(t)
            if let ex = session.exercises.first(where: { $0.pattern == p }) {
                found = Appearance(state: t, session: session, exercise: ex)
            }
        }
        return try XCTUnwrap(found, "\(p.rawValue) never stands in a session")
    }

    /// One pattern placed by hand on top of a clean start.
    private func placed(_ p: Pattern, variation: Int, dose: Int, sub: Int = 0, cut: Int = 0,
                        journal: Int) -> EngineState {
        var s = EngineState.initial
        s.vars[p] = variation
        s.doses[p] = dose
        if sub > 0 { s.sub[p] = sub }
        if cut > 0 { s.cut[p] = cut }
        s.shown[p] = [variation: journal]
        return s
    }

    // MARK: - §41.14 · a number that meets the plan journals the best set it proves

    /// 9-9-8 done as 10, 8, 8: the plan's sum, so "the plan was met", and the
    /// rise crosses the rung to 3×9. Journalling the fold — 8, the plan's
    /// base — would put the journal under the plan it just assigned; a tap
    /// on the same session journals 9, and so must the number.
    func testAMixedFactAtTheRungBoundaryJournalsWhatATapWould() throws {
        let a = try appearance(placed(.squat, variation: 2, dose: 8, sub: 2, journal: 9), .squat)
        XCTAssertEqual(a.exercise.loads, [9, 9, 8])
        let logged = a.feedback(.plan, [.squat: 26.0 / 3.0])
        let tapped = a.feedback(.plan)
        XCTAssertEqual(logged.position(.squat), tapped.position(.squat), "the same rise either way")
        XCTAssertEqual(logged.doses[.squat], 9, "3×9 next")
        XCTAssertEqual(logged.shownDose(.squat, variation: 2), 9,
                       "the journal sits under the plan it just assigned")
        XCTAssertEqual(logged.shownDose(.squat, variation: 2), tapped.shownDose(.squat, variation: 2))
    }

    /// A met number journals no more than the plan's top. 3×9 done as 10, 9,
    /// 9 is inside the window (9.33), and the mean rounded up says 10 — but
    /// "met" means the plan was done, and the plan's top here is its base, so
    /// a uniform plan journals exactly what it did before the rule existed.
    func testAMetFactNeverJournalsAboveThePlansTop() throws {
        let a = try appearance(placed(.squat, variation: 2, dose: 9, journal: 9), .squat)
        XCTAssertNil(a.exercise.loads, "a uniform plan")
        let logged = a.feedback(.plan, [.squat: 28.0 / 3.0])
        XCTAssertEqual(logged.shownDose(.squat, variation: 2), 9)
        XCTAssertEqual(logged.shownDose(.squat, variation: 2),
                       a.feedback(.plan).shownDose(.squat, variation: 2), "as a tap")
    }

    /// The probe reads the journal (§41.4). 15-15-14 done as 16, 14, 14 met
    /// the plan and reached 3×15; with the fold journalled the probe would
    /// wait an appearance the tapper does not wait.
    func testTheLoggerIsOfferedTheProbeWhenTheTapperIs() throws {
        let a = try appearance(placed(.squat, variation: 2, dose: 14, sub: 2, journal: 15), .squat)
        let afterLog = try appearance(a.feedback(.plan, [.squat: 44.0 / 3.0]), .squat).exercise
        let afterTap = try appearance(a.feedback(.plan), .squat).exercise
        XCTAssertNotNil(afterTap.probe, "control: the tapper is offered the probe")
        XCTAssertNotNil(afterLog.probe, "the logger who met the same plan is offered it too")
        XCTAssertEqual(afterLog.display, afterTap.display)
    }

    /// The cross-credit is bounded by the branch's own journal. A vertical
    /// pull 9-9-8 done as 10, 8, 8 that journalled 8 would stop the next
    /// growth of the horizontal pull from reaching the branch at 3×9.
    func testTheLoggerKeepsTheCrossCreditTheTapperGets() throws {
        var start = placed(.pullBar, variation: 5, dose: 8, sub: 2, journal: 9)
        start.hasBar = true
        start.counter = 1                         // odd: the vertical branch stands
        start.vars[.pull] = 4
        start.doses[.pull] = 8
        start.shown[.pull] = [4: 8]
        func creditAfter(_ overrides: [Pattern: Double]) throws -> Position {
            let own = try appearance(start, .pullBar)
            XCTAssertEqual(own.state.counter, start.counter, "the branch's own appearance comes first")
            let mid = own.feedback(.plan, overrides)
            let horizontal = try appearance(mid, .pull)
            return horizontal.feedback(.plan).position(.pullBar)
        }
        let tapped = try creditAfter([:])
        XCTAssertEqual(tapped.sub, 1, "control: the tap's journal lets the credit through")
        XCTAssertEqual(try creditAfter([.pullBar: 26.0 / 3.0]), tapped)
    }

    /// Holds: the engine sees only the mean of the seconds, and the grid steps
    /// by five. Someone who can hold 44 s and declares 44 on every set of
    /// 45-45-40 has NOT shown the ceiling: the plan still crosses to 3×45 (the
    /// named residual), but the journal stays at 40 and no probe comes — the
    /// top taken on trust would offer one their working sets then throw out.
    /// 45, 45, 44 proves the top: journal 45, and the probe follows.
    func testAHoldJournalsTheTopOnlyWhenTheSecondsProveIt() throws {
        let a = try appearance(placed(.coreAntiExt, variation: 4, dose: 40, sub: 2, journal: 45),
                               .coreAntiExt)
        XCTAssertEqual(a.exercise.loads, [45, 45, 40])

        let unproven = a.feedback(.plan, [.coreAntiExt: 44])
        XCTAssertEqual(unproven.doses[.coreAntiExt], 45, "the met plan still rises")
        XCTAssertEqual(unproven.shownDose(.coreAntiExt, variation: 4), 40,
                       "44 s in every set proves no 45")
        XCTAssertNil(try appearance(unproven, .coreAntiExt).exercise.probe,
                     "no probe without the ceiling shown")

        let proven = a.feedback(.plan, [.coreAntiExt: 134.0 / 3.0])
        XCTAssertEqual(proven.shownDose(.coreAntiExt, variation: 4), 45,
                       "a mean of 44.67 s means a set of at least 45 s")
        XCTAssertNotNil(try appearance(proven, .coreAntiExt).exercise.probe)
    }

    // MARK: - §41.15 · the hold's corner, accepted

    /// Under a cut, while the hold ticks, the next sub-step can land on the
    /// set the cut took off; `fit` clamps it back and "on plan" moves nothing.
    /// The owner kept this (04.10.2026): every repair measured gave up
    /// something ranked higher. Pinned both ways — the plan stands, and
    /// without the hold the same tap brings the set back.
    func testUnderACutTheHoldCanLeaveTheNextPlanStanding() throws {
        var held = placed(.squat, variation: 2, dose: 8, sub: 1, cut: 1, journal: 9)
        held.setsHold[.squat] = 1
        let a = try appearance(held, .squat)
        XCTAssertEqual(a.exercise.loads, [9, 8], "two sets on screen, the top one already raised")
        let next = a.feedback(.plan)
        XCTAssertEqual(next.position(.squat), a.state.position(.squat), "the accepted corner: nothing moves")
        XCTAssertEqual(Engine.progress(next, .squat), Engine.progress(a.state, .squat))
        XCTAssertNil(next.setsHold[.squat], "the appearance still spends the hold")

        let after = try appearance(next, .squat).feedback(.plan)
        XCTAssertNil(after.cut[.squat], "the hold ran out: the set comes back")
        XCTAssertEqual(after.setsHold[.squat], EngineConfig.setsBackHold)

        var free = held
        free.setsHold[.squat] = nil
        XCTAssertNil(try appearance(free, .squat).feedback(.plan).cut[.squat],
                     "control: without the hold the same tap returns the set")
    }

    // MARK: - §41.15 · the weekly ceiling arms no hold for a return it undid

    /// The week's budget is spent: the main loop gives a set back and arms
    /// the hold, the ceiling takes the return back. Left armed, the hold
    /// would keep the set off for two more appearances under a cut, though
    /// no set had returned.
    func testAReturnTheWeeklyCeilingUndoesArmsNoHold() throws {
        var spent = placed(.squat, variation: 2, dose: 8, cut: 1, journal: 8)
        spent.weekGain[.squat] = EngineConfig.weeklyRiseFast
        spent.weekAgeDays = 1
        let a = try appearance(spent, .squat)

        let capped = a.feedback(.plan, gapDays: 1)
        XCTAssertEqual(capped.cut[.squat], 1, "the ceiling undid the return")
        XCTAssertNil(capped.setsHold[.squat], "and so armed no hold")

        let free = a.feedback(.plan)
        XCTAssertNil(free.cut[.squat], "control: without the window the set comes back")
        XCTAssertEqual(free.setsHold[.squat], EngineConfig.setsBackHold, "control: and the hold is armed")

        var roomy = a.state
        roomy.weekGain[.squat] = EngineConfig.weeklyRiseFast - 1
        let kept = Engine.applyFeedback(state: roomy, session: a.session, result: .plan, gapDays: 1)
        XCTAssertNil(kept.cut[.squat], "control: with budget to spare the return stands")
        XCTAssertEqual(kept.setsHold[.squat], EngineConfig.setsBackHold, "control: and so does the hold")
    }

    /// The same on a band of the top variation, where a return leaves a cut
    /// behind: the rule is "no return happened", not "some cut is left".
    func testOnABandTheCeilingUndoesTheHoldOnlyWithTheReturn() throws {
        var band = placed(.squat, variation: Library.count(.squat), dose: 4, cut: 3, journal: 4)
        band.sets[.squat] = EngineConfig.setsMax
        band.weekGain[.squat] = EngineConfig.weeklyRiseFast
        band.weekAgeDays = 1
        let a = try appearance(band, .squat)
        XCTAssertEqual(a.exercise.sets, 2, "five sets, three taken off")

        let capped = a.feedback(.plan, gapDays: 1)
        XCTAssertEqual(capped.cut[.squat], 3)
        XCTAssertNil(capped.setsHold[.squat])

        var roomy = a.state
        roomy.weekGain[.squat] = EngineConfig.weeklyRiseFast - 1
        let kept = Engine.applyFeedback(state: roomy, session: a.session, result: .plan, gapDays: 1)
        XCTAssertEqual(kept.cut[.squat], 2, "one set back, two still off")
        XCTAssertEqual(kept.setsHold[.squat], EngineConfig.setsBackHold,
                       "a return that stands keeps its hold, cut or no cut")
    }

    /// The ceiling also trims a cross-credit. Under a running hold the credit
    /// returns no set, so the rollback has nothing to take back: the other
    /// branch's hold ticks only with its own appearances.
    func testTheCeilingLeavesTheOtherBranchHoldAlone() throws {
        var s = placed(.pullBar, variation: 5, dose: 8, cut: 1, journal: 15)
        s.hasBar = true
        s.counter = 0                             // even: the horizontal branch stands
        s.vars[.pull] = 4
        s.doses[.pull] = 8
        s.shown[.pull] = [4: 8]
        s.setsHold[.pullBar] = EngineConfig.setsBackHold
        s.weekGain[.pullBar] = EngineConfig.weeklyRiseSlow
        s.weekAgeDays = 1
        let a = try appearance(s, .pull)
        XCTAssertEqual(a.state.counter, s.counter)
        XCTAssertNil(a.session.exercises.first { $0.pattern == .pullBar })

        let capped = a.feedback(.plan, gapDays: 1)
        XCTAssertEqual(capped.setsHold[.pullBar], EngineConfig.setsBackHold,
                       "a branch that did not appear keeps its hold")
        let free = a.feedback(.plan)
        XCTAssertGreaterThan(Engine.progress(free, .pullBar), Engine.progress(s, .pullBar),
                             "control: without the window the credit reaches the branch")
    }
}
