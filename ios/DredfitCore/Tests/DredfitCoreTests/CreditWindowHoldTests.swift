//
//  The weekly window and a number that met the plan, the cross-credit and its
//  set returns, and the hold armed by sets coming back on screen (§41.16).
//  Golden pins these through whole scenarios; each test here names one rule,
//  so a port that breaks it says which.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class CreditWindowHoldTests: XCTestCase {

    // MARK: - Helpers

    /// A session in which the pattern under test stands, with the state it
    /// was generated from.
    private struct Appearance {
        let state: EngineState
        let session: Session
        let exercise: SessionExercise

        func feedback(_ result: FeedbackResult, _ overrides: [Pattern: Double] = [:],
                      gapDays: Double? = nil, probes: [Pattern: Int] = [:]) -> EngineState {
            Engine.applyFeedback(state: state, session: session, result: result,
                                 overrides: overrides, gapDays: gapDays, probes: probes)
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
    private func placed(_ p: Pattern, variation: Int, dose: Int, sets: Int = EngineConfig.setsBase,
                        sub: Int = 0, cut: Int = 0, journal: [Int: Int]) -> EngineState {
        var s = EngineState.initial
        s.vars[p] = variation
        s.doses[p] = dose
        if sets != EngineConfig.setsBase { s.sets[p] = sets }
        if sub > 0 { s.sub[p] = sub }
        if cut > 0 { s.cut[p] = cut }
        s.shown[p] = journal
        return s
    }

    /// The pull slot with the bar: the horizontal branch at a growing position,
    /// the vertical one as given.
    private func slot(barVariation: Int, barDose: Int, barSets: Int = EngineConfig.setsBase,
                      barSub: Int = 0, barCut: Int, barJournal: Int, counter: Int) -> EngineState {
        var s = placed(.pullBar, variation: barVariation, dose: barDose, sets: barSets, sub: barSub,
                       cut: barCut, journal: [barVariation: barJournal])
        s.hasBar = true
        s.counter = counter
        s.vars[.pull] = 4
        s.doses[.pull] = 8
        s.shown[.pull] = [4: 8]
        return s
    }

    // MARK: - §41.16 п. 1 · a number that met the plan obeys the weekly window

    /// A number that merely meets the plan rises by the engine's +1, as a tap
    /// does, so the window governs it as it governs the tap. Let through, it
    /// rose past a spent budget where a tap on the same session stood still,
    /// and a daily logger outgrew the window on the slow tissues by half again.
    func testUnderASpentWindowANumberThatMeetsThePlanStandsLikeATap() throws {
        var spent = placed(.squat, variation: 2, dose: 8, sub: 2, journal: [2: 9])
        spent.weekGain[.squat] = EngineConfig.weeklyRiseFast
        spent.weekAgeDays = 1
        let a = try appearance(spent, .squat)
        XCTAssertEqual(a.exercise.loads, [9, 9, 8])
        let tapped = a.feedback(.plan, gapDays: 1)
        let logged = a.feedback(.plan, [.squat: 26.0 / 3.0], gapDays: 1)
        XCTAssertEqual(tapped.position(.squat), a.state.position(.squat), "control: the window stops a tap")
        XCTAssertEqual(logged.position(.squat), tapped.position(.squat), "a met number stands like the tap")
        XCTAssertEqual(logged.weekGain[.squat], EngineConfig.weeklyRiseFast)

        var roomy = a.state
        roomy.weekGain[.squat] = EngineConfig.weeklyRiseFast - 1
        let grown = Engine.applyFeedback(state: roomy, session: a.session, result: .plan,
                                         overrides: [.squat: 26.0 / 3.0], gapDays: 1)
        XCTAssertEqual(grown.doses[.squat], 9, "with budget to spare it rises to 3×9")
        XCTAssertEqual(grown.weekGain[.squat], EngineConfig.weeklyRiseFast, "and the rise is charged")
    }

    /// The other side: fast adaptation is what the person DID, and no window
    /// trims it or charges for it.
    func testUnderASpentWindowFastAdaptationStaysFree() throws {
        var spent = placed(.squat, variation: 2, dose: 8, sub: 2, journal: [2: 9])
        spent.weekGain[.squat] = EngineConfig.weeklyRiseFast
        spent.weekAgeDays = 1
        let a = try appearance(spent, .squat)
        let adopted = a.feedback(.plan, [.squat: 12], gapDays: 1)
        XCTAssertEqual(adopted.doses[.squat], 12, "the dose is what was done")
        XCTAssertEqual(adopted.weekGain[.squat], EngineConfig.weeklyRiseFast, "nothing charged")
    }

    /// A number for a movement outside the session is discarded whole. Taken
    /// for a fact, it lifted the window off the credit that branch received.
    func testANumberForAMovementOutsideTheSessionChangesNothing() throws {
        var s = slot(barVariation: 5, barDose: 8, barCut: 0, barJournal: 15, counter: 0)
        s.weekGain[.pullBar] = EngineConfig.weeklyRiseSlow
        s.weekAgeDays = 1
        let a = try appearance(s, .pull)
        XCTAssertNil(a.session.exercises.first { $0.pattern == .pullBar })
        XCTAssertGreaterThan(Engine.progress(a.feedback(.more), .pullBar), Engine.progress(a.state, .pullBar),
                             "control: without the window the credit reaches the branch")
        let plain = a.feedback(.more, gapDays: 1)
        XCTAssertEqual(plain.position(.pullBar), a.state.position(.pullBar), "the spent window stops the credit")
        XCTAssertEqual(a.feedback(.more, [.pullBar: 20], gapDays: 1), plain)
    }

    // MARK: - §41.16 п. 2 · a set return ends the credit; the window charges what it gave

    /// A set the credit returns ends the credit, as a set return ends growth
    /// in `riseBy`. A dose step on top made a jump the weekly window's rebuild
    /// could not repeat: it kept the set alone and charged both.
    func testACreditThatReturnsASetEndsThere() throws {
        let s = slot(barVariation: 2, barDose: 20, barCut: 1, barJournal: 45, counter: 0)
        var grows = s
        grows.vars[.pull] = 2                       // two events of credit: below the slow top variations
        grows.shown[.pull] = [2: 8]
        let a = try appearance(grows, .pull)
        XCTAssertEqual(a.state.counter, grows.counter, "the horizontal branch stands first")
        let free = a.feedback(.more)
        XCTAssertNil(free.cut[.pullBar], "the set came back")
        XCTAssertEqual(free.position(.pullBar).dose, 20, "and nothing more: no dose step on top")
        XCTAssertEqual(free.position(.pullBar).sub, 0)
        let windowed = a.feedback(.more, gapDays: 2)
        XCTAssertEqual(windowed.position(.pullBar), free.position(.pullBar), "the window keeps the same set")
        XCTAssertEqual(windowed.weekGain[.pullBar], 1, "and charges the one event it is")
    }

    /// The window grants one event of an "easy" under a hold and a cut, the
    /// event lands on the set the cut hides and is lost — and must not be
    /// charged.
    func testTheWindowChargesOnlyWhatTheRebuildGave() throws {
        var s = slot(barVariation: 4, barDose: 11, barSub: 1, barCut: 1, barJournal: 12, counter: 1)
        s.setsHold[.pullBar] = EngineConfig.setsBackHold
        s.weekGain[.pullBar] = EngineConfig.weeklyRiseSlow - 1
        s.weekAgeDays = 1
        let a = try appearance(s, .pullBar)
        XCTAssertEqual(a.exercise.loads, [12, 11])
        let windowed = a.feedback(.more, gapDays: 1)
        XCTAssertEqual(windowed.position(.pullBar), a.state.position(.pullBar), "the granted event was lost")
        XCTAssertEqual(windowed.weekGain[.pullBar], EngineConfig.weeklyRiseSlow - 1, "so nothing is charged")
        XCTAssertGreaterThan(Engine.progress(a.feedback(.more), .pullBar), Engine.progress(a.state, .pullBar),
                             "control: without the window the same answer moves the plan")
    }

    // MARK: - §41.16 п. 3 · the hold is armed by sets coming back on screen

    /// A descent off a band carries the cut into the variation below: two
    /// sets on screen before, two after. A hold armed there spaces no return;
    /// it only parks the next growth event in its corner, where it is lost.
    func testADescentThatCarriesTheCutArmsNoHold() throws {
        let band = placed(.squat, variation: Library.count(.squat), dose: 4, sets: EngineConfig.setsMax,
                          cut: 3, journal: [5: 15, 6: 4])
        let a = try appearance(band, .squat)
        let down = a.feedback(.less)
        XCTAssertEqual(down.vars[.squat], Library.count(.squat) - 1)
        XCTAssertEqual(down.cut[.squat], 1, "the cut came along")
        XCTAssertNil(down.setsHold[.squat], "no more sets on screen, no hold")
        let back = try appearance(down, .squat).feedback(.plan)
        XCTAssertNil(back.cut[.squat], "so the next \"on plan\" brings the set back")
    }

    /// The other side: a probe taken on a cut plan — one set and the probe —
    /// enters 3×4. Sets on screen went up, and the hold is the hold's job.
    func testAProbeEntryThatAddsSetsArmsTheHold() throws {
        let cut = placed(.squat, variation: 1, dose: 15, cut: 1, journal: [1: 15])
        let a = try appearance(cut, .squat)
        XCTAssertNotNil(a.exercise.probe)
        let entered = a.feedback(.plan, probes: [.squat: 4])
        XCTAssertEqual(entered.vars[.squat], 2)
        XCTAssertEqual(entered.setsHold[.squat], EngineConfig.setsBackHold)
    }

    // MARK: - §41.16 п. 4 · a set the credit returns arms the hold

    /// Without the hold, the branch's own next appearance returned a second
    /// set at once: 2 → 3 → 4 sets on consecutive appearances.
    func testASetTheCreditReturnsArmsTheHold() throws {
        let s = slot(barVariation: Library.count(.pullBar), barDose: 9, barSets: EngineConfig.setsMax,
                     barCut: 3, barJournal: 15, counter: 0)
        let afterCredit = try appearance(s, .pull).feedback(.plan)
        XCTAssertEqual(afterCredit.cut[.pullBar], 2, "the credit returned a set")
        XCTAssertEqual(afterCredit.setsHold[.pullBar], EngineConfig.setsBackHold, "and armed the hold")
        let afterOwn = try appearance(afterCredit, .pullBar).feedback(.plan)
        XCTAssertEqual(afterOwn.cut[.pullBar], 2, "the branch's own appearance returns no second set")
    }

    /// A credit that returns no set leaves the hold as it was, and a window
    /// that takes the credit's set back takes the hold with it.
    func testACreditHoldGoesOnlyWithItsSet() throws {
        let noCut = slot(barVariation: 5, barDose: 8, barCut: 0, barJournal: 15, counter: 0)
        let dosed = try appearance(noCut, .pull).feedback(.plan)
        XCTAssertGreaterThan(Engine.progress(dosed, .pullBar), Engine.progress(noCut, .pullBar),
                             "control: the credit grew the dose")
        XCTAssertNil(dosed.setsHold[.pullBar], "no set, no hold")

        var spent = slot(barVariation: 5, barDose: 8, barCut: 1, barJournal: 15, counter: 0)
        spent.weekGain[.pullBar] = EngineConfig.weeklyRiseSlow
        spent.weekAgeDays = 1
        let capped = try appearance(spent, .pull).feedback(.plan, gapDays: 1)
        XCTAssertEqual(capped.cut[.pullBar], 1, "the window took the credit's set back")
        XCTAssertNil(capped.setsHold[.pullBar], "and the hold with it")
    }
}
