//
//  The pull slot caps a push's sets, and two rules keep that cap honest: a
//  push enters its next set band only once the pull slot shows that many sets
//  after its own session, and a push whose position stands gets back exactly
//  the sets the cap has handed back since it was last shown. The golden
//  fixture pins both through whole scenarios; each test here names one face
//  of one rule, so a port that breaks it says which.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class PushGateTests: XCTestCase {

    // MARK: - Helpers

    /// A position on the TOP variation of `p`, with a journal that has shown
    /// every rung — the state a person who climbed the ladder carries.
    private func put(_ s: inout EngineState, _ p: Pattern, sets: Int = EngineConfig.setsBase,
                     dose: Int, sub: Int = 0, cut: Int = 0) {
        let top = Library.count(p)
        s.vars[p] = top
        s.doses[p] = dose
        s.sets[p] = sets == EngineConfig.setsBase ? nil : sets
        s.sub[p] = sub > 0 ? sub : nil
        s.cut[p] = cut > 0 ? cut : nil
        var journal: [Int: Int] = [:]
        for v in 1...top { journal[v] = Dose.grid(Library.unit(p, v)).max }
        s.shown[p] = journal
    }

    /// The pull on its fourth variation — below the top, so no band ever
    /// opens for it, and its count of sets moves only by its cut.
    private func putLowPull(_ s: inout EngineState, dose: Int, cut: Int = 0) {
        s.vars[.pull] = 4
        s.doses[.pull] = dose
        s.cut[.pull] = cut > 0 ? cut : nil
        s.shown[.pull] = [1: 15, 2: 15, 3: 15, 4: dose]
    }

    private func onScreen(_ s: EngineState, _ p: Pattern) -> Int {
        let q = s.position(p)
        return Engine.setsAfterCut(sets: q.sets, cut: q.cut)
    }

    private func exercise(_ s: EngineState, _ p: Pattern) -> SessionExercise? {
        Engine.generateSession(s).exercises.first { $0.pattern == p }
    }

    /// One session of the app's order: the plan is shown, then rated, then
    /// the sets skipped during it land, then the steps added for next time.
    private func train(_ s: EngineState, _ result: FeedbackResult = .plan,
                       overrides: [Pattern: Double] = [:], skipped: Set<Pattern> = [],
                       setsSkipped: [Pattern: Int] = [:], raised: [Pattern: Int] = [:],
                       gapDays: Double? = nil) -> EngineState {
        let session = Engine.generateSession(s)
        return Engine.applyFeedback(state: s, session: session, result: result,
                                    overrides: overrides, skipped: skipped,
                                    setsSkipped: setsSkipped, gapDays: gapDays,
                                    probes: [:], raised: raised)
    }

    // MARK: - A push enters a band behind the pull

    /// Archer push-ups on their ceiling would enter 4×11 while the pull
    /// stands on three sets — and the cap would then show 3×11, a third less
    /// than the 3×15 just done, under a "Now 4 sets" that is not true. The
    /// push waits on its ceiling instead; with the pull on four it enters.
    func testAPushWaitsOnItsCeilingWhileThePullShowsFewerSets() {
        var s = EngineState.initial
        put(&s, .pushH, dose: 15)
        put(&s, .pull, dose: 14, sub: 2)
        let after = train(s)
        XCTAssertEqual(onScreen(after, .pull), 3, "the pull stays on three this session")
        XCTAssertEqual(after.position(.pushH).sets, 3, "the push does not enter band 4 ahead of the pull")
        XCTAssertEqual(after.position(.pushH).dose, 15, "it waits on its ceiling")

        var control = EngineState.initial
        put(&control, .pushH, dose: 15)
        put(&control, .pull, sets: 4, dose: 11)
        let entered = train(control).position(.pushH)
        XCTAssertEqual([entered.sets, entered.dose], [4, 11], "control: with the pull on four it enters")
    }

    /// The pull is read AFTER its own growth this session: a pull that
    /// enters band 4 in the same session lets the push in with it.
    func testAPushEntersBehindAPullThatRoseInTheSameSession() {
        var s = EngineState.initial
        put(&s, .pushH, dose: 15)
        put(&s, .pull, dose: 15)
        let after = train(s)
        XCTAssertEqual(after.position(.pull).sets, 4, "the pull entered band 4 this session")
        XCTAssertEqual([after.position(.pushH).sets, after.position(.pushH).dose], [4, 11])
    }

    /// The pull is read after its weekly window too. Its main loop enters
    /// band 4, the spent window takes that back, and the push reads the pull
    /// as it actually stands — on three.
    func testThePullIsReadAfterItsWeeklyWindow() {
        var s = EngineState.initial
        put(&s, .pushH, dose: 15)
        put(&s, .pull, dose: 15)
        s.weekGain[.pull] = EngineConfig.weeklyRiseSlow
        s.weekAgeDays = 1
        let after = train(s, gapDays: 0.5)
        XCTAssertEqual(after.position(.pull).sets, 3, "the window kept the pull on three")
        XCTAssertEqual(after.position(.pushH).sets, 3, "the push waits for the pull the window kept")
    }

    /// And after a fall in the same session: the pull showed four, a number
    /// below the floor of its variation sent it down to three sets. The
    /// better of "before" and "after" would let the push into 4×11 and the
    /// next plan would cap it at 3×11.
    func testThePullIsReadAfterAFallInTheSameSession() {
        var s = EngineState.initial
        put(&s, .pushH, dose: 15)
        put(&s, .pull, sets: 4, dose: 11)
        let after = train(s, overrides: [.pull: 2])
        XCTAssertEqual(after.vars[.pull], Library.count(.pull) - 1, "the pull went a variation down")
        XCTAssertEqual(onScreen(after, .pull), 3)
        XCTAssertEqual(after.position(.pushH).sets, 3, "the push waits for the pull that fell")
    }

    /// With the bar the weaker branch decides, and the cross-credit counts:
    /// the credit that carries the bar's branch into band 4 lets the push in
    /// within the same session; a credit that leaves the branch on three
    /// does not.
    func testWithTheBarTheWeakerBranchDecidesAndTheCreditCounts() {
        func slot(barDose: Int, barSub: Int) -> EngineState {
            var s = EngineState.initial
            s.hasBar = true
            put(&s, .pushH, dose: 15)
            put(&s, .pull, sets: 4, dose: 11)
            put(&s, .pullBar, dose: barDose, sub: barSub)
            return s
        }
        let credited = train(slot(barDose: 15, barSub: 0))
        XCTAssertEqual(credited.position(.pullBar).sets, 4, "the credit carried the bar's branch into band 4")
        XCTAssertEqual(credited.position(.pushH).sets, 4, "and the push entered with it")

        let short = train(slot(barDose: 14, barSub: 1))
        XCTAssertEqual(short.position(.pullBar).sets, 3, "a credit of one event leaves the branch on three")
        XCTAssertEqual(short.position(.pushH).sets, 3, "the weaker branch keeps the push waiting")
    }

    /// The pull caps pushes only: a squat on its ceiling enters its band
    /// whatever the pull shows.
    func testOnlyAPushWaitsForThePull() {
        var s = EngineState.initial
        put(&s, .squat, dose: 15)
        put(&s, .pull, dose: 14, sub: 2)
        let after = train(s)
        XCTAssertEqual(onScreen(after, .pull), 3)
        XCTAssertEqual([after.position(.squat).sets, after.position(.squat).dose], [4, 11])
    }

    /// What is compared is the push's BAND, not the sets it shows. A push on
    /// 3×15 with a set taken off, while its hold ticks, grows into the band:
    /// band 4 against a pull on three waits, though 4 − 1 on screen would fit.
    func testTheBandIsComparedNotTheSetsOnScreen() {
        var s = EngineState.initial
        put(&s, .pushH, dose: 15, cut: 1)
        s.setsHold[.pushH] = 1
        putLowPull(&s, dose: 10)
        let after = train(s)
        XCTAssertEqual(onScreen(after, .pull), 3)
        XCTAssertEqual(after.position(.pushH).sets, 3, "band 4 waits for a pull on three")
        XCTAssertEqual(after.position(.pushH).cut, 1, "the hold kept the set off")
    }

    // MARK: - A lifted gate gives a standing push its sets back

    /// Push and pull on 5×15, one pull set skipped. The press shows 4×15 at
    /// its next appearance — the pull really does show four — and the pull
    /// returns its set in that session. Once the cap has lifted, the press is
    /// back on 5×15. Before the rule the repair held it on 4×15 at every
    /// appearance until the press fell: at the top of the scale it cannot
    /// rise.
    func testALiftedGateGivesAFrozenPushItsSetsBack() throws {
        var s = EngineState.initial
        put(&s, .pushH, sets: 5, dose: 15)
        put(&s, .pushV, sets: 5, dose: 15)
        put(&s, .pull, sets: 5, dose: 15)
        var shown: [Int] = []
        for k in 0..<6 {
            if let pv = exercise(s, .pushV) { shown.append(pv.sets) }
            s = train(s, setsSkipped: k == 0 ? [.pull: 1] : [:], gapDays: 7 / 3)
        }
        XCTAssertEqual(shown, [5, 4, 5, 5], "capped once while the pull showed four, then back")
    }

    /// A set of the push skipped at its last showing keeps the repair's hold
    /// when the cap lifts: a cut is a descent. Here the press got a set back
    /// in that session and the same set was skipped, so its position stands
    /// and its own sets equal those it was shown with — only the skip's trace
    /// tells the hold apart from a cap.
    func testASkippedPushSetKeepsTheRepairsHold() {
        var s = EngineState.initial
        put(&s, .pushH, sets: 5, dose: 12, cut: 1)
        put(&s, .pull, dose: 14, sub: 2)
        s = train(s, setsSkipped: [.pushH: 1])
        s = train(s)
        XCTAssertEqual(onScreen(s, .pull), 4, "the cap lifted from three to four")
        let held = exercise(s, .pushH)
        XCTAssertEqual(held?.sets, 3, "the skipped set is not handed back")
    }

    /// The twin of the test above: the same state with the trace wiped is a
    /// standing push under a cap that rose by one, and gets that set back. So
    /// it is the trace, and nothing else, that keeps the skipped set off.
    func testWithoutItsTraceTheSkippedSetWouldComeBack() throws {
        var s = EngineState.initial
        put(&s, .pushH, sets: 5, dose: 12, cut: 1)
        put(&s, .pull, dose: 14, sub: 2)
        s = train(s, setsSkipped: [.pushH: 1])
        s = train(s)
        XCTAssertEqual(s.shownSkip, [.pushH], "the skipped set left its trace")
        var wiped = s
        wiped.shownSkip = []
        XCTAssertEqual(exercise(wiped, .pushH)?.sets, 4)
    }

    /// What comes back is the rise of the push's OWN cap, min(own, pull),
    /// on top of whatever the repair holds for its own reasons. Band 4: the
    /// cap never cut the press (three of its own under a pull on three), so a
    /// rising pull adds nothing and the hold for its skipped set stays. Band
    /// 5: the cap cut one set, it lifts by one, and one set comes back on top
    /// of the held 13-12.
    func testTheLiftIsTheRiseOfThePushsOwnCap() throws {
        func chain(band: Int) -> EngineState {
            var s = EngineState.initial
            s.counter = 2
            put(&s, .pushH, sets: band, dose: 12)
            put(&s, .pull, sets: 4, dose: 11, cut: 1)
            func session(skipped: Set<Pattern>, skipSet: Bool) {
                let w = Engine.generateSession(s)
                s = Engine.recordShown(state: s, session: w)
                s = Engine.applyFeedback(state: s, session: w, result: .plan, skipped: skipped,
                                         setsSkipped: skipSet ? [.pushH: 1] : [:], gapDays: 2)
            }
            session(skipped: [.pull], skipSet: true)
            session(skipped: [.pushH], skipSet: false)
            session(skipped: [], skipSet: false)
            return s
        }
        let four = try XCTUnwrap(exercise(chain(band: 4), .pushH))
        XCTAssertEqual(four.loads, [13, 12], "band 4: the cap never cut, nothing comes back")
        let five = try XCTUnwrap(exercise(chain(band: 5), .pushH))
        XCTAssertEqual(five.loads, [13, 12, 12], "band 5: one set back, on top of the hold")
    }

    /// Fewer own sets than at the last showing keep the hold too: "hard" on
    /// the dose floor took a set off, the raise handle put the position back
    /// where it stood. The pull returns its set and the cap rises — but the
    /// press has a set fewer of its own, and that is a descent.
    func testFewerOwnSetsKeepTheHold() throws {
        var s = EngineState.initial
        put(&s, .pushH, sets: 5, dose: 4)
        putLowPull(&s, dose: 8, cut: 1)
        s = train(s, .less, raised: [.pushH: 1], gapDays: 7 / 3)
        XCTAssertEqual(s.position(.pushH).cut, 1, "the descent took a set off")
        s = train(s, gapDays: 7 / 3)
        XCTAssertEqual(onScreen(s, .pull), 3, "the pull returned its set")
        let held = try XCTUnwrap(exercise(s, .pushH))
        XCTAssertEqual(held.loads, [5, 4], "the hold stands though the cap rose")
    }

    /// A state written before the gate memory existed carries the memory of
    /// what was shown and nothing about the cap. A standing push on it gets
    /// its whole cap back once — the press frozen at 4×15 under a pull long
    /// back on five — and a push that FELL since its showing stays under the
    /// repair: a descent never adds work.
    func testAStateWithoutGateMemoryIsReleasedOnce() throws {
        var s = EngineState.initial
        put(&s, .pushH, sets: 5, dose: 15)
        put(&s, .pushV, sets: 5, dose: 13)
        put(&s, .pull, sets: 5, dose: 15)
        s.shownWork = [.pushH: 4 * 15 * 2, .pushV: 4 * 14]
        s.shownOrd = [
            .pushH: Engine.posOrd(.pushH, s.position(.pushH)),
            .pushV: Engine.posOrd(.pushV, Position(variation: Library.count(.pushV), sets: 5,
                                                  dose: 14, sub: 0, cut: 0)),
        ]
        let session = Engine.generateSession(s)
        let press = try XCTUnwrap(session.exercises.first { $0.pattern == .pushH })
        XCTAssertEqual(press.sets, 5, "the frozen press gets its cap back")
        let handstand = try XCTUnwrap(session.exercises.first { $0.pattern == .pushV })
        XCTAssertEqual([handstand.sets, handstand.load], [4, 13], "the fallen one stays under the repair")

        // From the next showing on, the ordinary rule: the pull loses a set,
        // the cap takes one; the pull returns it, the press follows.
        var shown: [Int] = []
        for k in 0..<10 {
            if let ph = exercise(s, .pushH) { shown.append(ph.sets) }
            s = train(s, setsSkipped: k == 2 ? [.pull: 1] : [:], gapDays: 7 / 3)
        }
        XCTAssertEqual(Array(shown.prefix(5)), [5, 5, 4, 5, 5])
    }

    // MARK: - The memory itself

    /// The feedback remembers the cap a push was SHOWN under — read off the
    /// state the plan was built from, as the position is. Here the pull
    /// returns a set in that very session and the press returns one of its
    /// own: the memory keeps three and three, the numbers on screen, not the
    /// four and four the session ends on. A push skipped whole was shown all
    /// the same, and remembers too.
    func testTheFeedbackRemembersTheCapAtTheShowing() {
        var s = EngineState.initial
        put(&s, .pushH, sets: 4, dose: 12, cut: 1)
        put(&s, .pushV, sets: 4, dose: 12)
        put(&s, .pull, sets: 4, dose: 15, cut: 1)
        s.shownSkip = [.pushH, .pushV]
        let after = train(s, skipped: [.pushV])
        XCTAssertEqual(after.position(.pull).cut, 0, "the pull returned its set this session")
        XCTAssertEqual(after.position(.pushH).cut, 0, "and so did the press")
        XCTAssertEqual(after.shownCap, [.pushH: 3, .pushV: 3])
        XCTAssertEqual(after.shownOwn, [.pushH: 3, .pushV: 4])
        XCTAssertEqual(after.shownSkip, [], "a showing closes the trace of a cut")
    }

    /// `recordShown` writes the same memory a feedback does, from the state the
    /// plan was built from, for the pushes on that plan and for nothing else;
    /// a push not on the plan keeps both its memory and its trace. The golden
    /// fixture never renders a plan, so this is the only pin on it.
    func testRecordShownWritesTheCapMemory() {
        var s = EngineState.initial
        s.counter = 1   // the vertical press stands in this session, the horizontal one does not
        put(&s, .pushV, sets: 4, dose: 12, cut: 1)
        put(&s, .pull, sets: 4, dose: 15, cut: 2)
        s.shownSkip = [.pushH, .pushV]
        s.shownCap[.pushH] = 4
        s.shownOwn[.pushH] = 3
        let session = Engine.generateSession(s)
        XCTAssertFalse(session.exercises.contains { $0.pattern == .pushH })
        let recorded = Engine.recordShown(state: s, session: session)
        XCTAssertEqual(recorded.shownCap, [.pushV: 2, .pushH: 4])
        XCTAssertEqual(recorded.shownOwn, [.pushV: 3, .pushH: 3])
        XCTAssertEqual(recorded.shownSkip, [.pushH], "the press not on the plan keeps its trace")
        XCTAssertEqual(Engine.recordShown(state: recorded, session: session), recorded,
                       "recording the same showing again changes nothing")
    }

    /// The trace marks a GROWING cut on a push, and only that: a cut given back,
    /// a cut set to what it is, and a cut on anything but a push leave none.
    func testSetCutLeavesATraceOnlyWhenAPushsCutGrows() {
        var s = EngineState.initial
        put(&s, .pushH, sets: 4, dose: 12)
        put(&s, .pushV, sets: 4, dose: 12, cut: 1)
        put(&s, .squat, sets: 4, dose: 12)
        XCTAssertEqual(Engine.setCut(state: s, pattern: .pushH, cut: 1).shownSkip, [.pushH])
        XCTAssertEqual(Engine.setCut(state: s, pattern: .pushV, cut: 0).shownSkip, [])
        XCTAssertEqual(Engine.setCut(state: s, pattern: .pushV, cut: 1).shownSkip, [])
        XCTAssertEqual(Engine.setCut(state: s, pattern: .squat, cut: 1).shownSkip, [])
    }

    /// Read leniently and healed: a file without the memory opens with none
    /// (the state of a build before the memory, released once); a file with it
    /// keeps it; a pattern the cap does not reach, or a count no plan can show,
    /// is healed away before the engine reads it.
    func testTheCapMemoryDecodesLenientlyAndHeals() throws {
        let bare = #"{"counter":3,"vars":["push_h",6],"doses":["push_h",12]}"#
        let old = try JSONDecoder().decode(EngineState.self, from: Data(bare.utf8))
        XCTAssertEqual(old.shownCap, [:])
        XCTAssertEqual(old.shownOwn, [:])
        XCTAssertEqual(old.shownSkip, [])

        let full = #"{"counter":3,"vars":["push_h",6],"doses":["push_h",12],"#
            + #""shownCap":["push_h",4,"squat",3,"push_v",9],"#
            + #""shownOwn":["push_h",3,"push_v",-1,"moon",2],"#
            + #""shownSkip":["push_v","squat","moon"]}"#
        let kept = try JSONDecoder().decode(EngineState.self, from: Data(full.utf8))
        XCTAssertEqual(kept.shownCap[.pushH], 4)
        let healed = kept.sanitized()
        XCTAssertEqual(healed.shownCap, [.pushH: 4, .pushV: EngineConfig.setsMax])
        XCTAssertEqual(healed.shownOwn, [.pushH: 3, .pushV: EngineConfig.setsFloor])
        XCTAssertEqual(healed.shownSkip, [.pushV])

        let roundTrip = try JSONDecoder().decode(EngineState.self,
                                                 from: JSONEncoder().encode(healed))
        XCTAssertEqual(roundTrip, healed)
    }
}
