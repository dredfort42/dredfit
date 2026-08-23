//
//  EngineV220Tests.swift
//  DredfitCoreTests
//
//  v2.20 (spec §31, #150): a pain episode ends without numbers too.
//
//  Waiting for confirmation used to be indefinite, and only an explicit fact
//  at or above the plan closed it (§21.2 p.5). That is right for whoever logs
//  numbers — and unreachable by construction for whoever does not, which is
//  the person this product is designed around. Measured on the v2.19
//  reference: one "it hurts" tap, then taps only, three sessions a week —
//  125 appearances of the squat over 200 sessions, growth zero, while the
//  neighbouring movement of the same rotation ran to the top of the scale.
//  That is not the "improve the result" rung failing, it is the "keep the
//  habit" one: a movement that never grows stops being a habit at all.
//
//  So confirmation got a SECOND route: a countdown of CLEAN appearances
//  (§31.2). The fact route is untouched — it still closes the episode on the
//  spot and grows in the same move. The slow route closes it and leaves the
//  growth for the next appearance: an appearance without growth is cheaper
//  than a tendon.
//
//  The countdown lives in its own field. `sore` holds the episode's freeze
//  ASSIGNMENT, and two rules read it — the 3 → 6 → 12 ladder and which report
//  this is in the two-step unload (§30.6). Counting down inside `sore` would
//  misread both; testTheLadderIsStillReadAfterCleanAppearances is the check
//  that would fail (§31.3).
//

import XCTest
@testable import DredfitCore

// Foundation ships its own `Pattern`; the tests mean the engine's.
private typealias Pattern = DredfitCore.Pattern

final class EngineV220Tests: XCTestCase {

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

    /// One appearance of `pattern`, on the given rating and inputs.
    private func tap(_ state: EngineState, _ result: FeedbackResult = .plan,
                     overrides: [Pattern: Int] = [:], skipped: Set<Pattern> = [],
                     discomfort: Set<Pattern> = []) -> EngineState {
        let w = Engine.generateSession(state)
        return Engine.applyFeedback(state: state, session: w, result: result,
                                    overrides: overrides, skipped: skipped,
                                    discomfort: discomfort)
    }

    /// Report pain on `.pull` from `level`, then reach WAITING — a live
    /// episode with the freeze spent and a full countdown.
    ///
    /// v2.25 (spec §36.5): the counters run in PARALLEL now, so the ordinary
    /// trajectory passes straight through that state — the appearance that
    /// burns the freeze closes the episode too. It stayed reachable through
    /// the "I was sick" lens, whose appearances spend the freeze without
    /// touching the countdown (§22.4), and that is the route used here. The
    /// lens is cleared afterwards, because under it the fast confirmation
    /// route is shut and this file is largely about that route.
    private func intoWaiting(_ level: Int) -> EngineState {
        var s = tap(seeded(level), .plan, discomfort: [.pull])
        var guardCount = 0
        while s.freezeRemaining(.pull) > 0, guardCount < 60 {
            s = Engine.applyIllness(state: s)
            s = tap(s)
            guardCount += 1
        }
        s.illness = 0
        return s
    }

    /// The position a first report of an episode lands on (§36.5): the level
    /// stands, the sets come off down to the shared floor.
    private func painLanding(_ level: Int) -> Position {
        Position(level: level, sub: 0,
                 cut: Level.cutMax(level: level, floor: EngineConfig.setsFloor))
    }

    // MARK: - §31.2 p.1-2 The countdown closes the episode

    /// Clean appearances spend the countdown; the session that closes it does
    /// NOT grow, and the next one does. The length is read from the state,
    /// never hard-coded: however much rest was assigned is however much has to
    /// be confirmed.
    func testCleanAppearancesCloseTheEpisodeAndGrowthResumesNext() throws {
        for level in [8, 20, 24, 40, EngineConfig.levelMax] {
            var s = intoWaiting(level)
            let landed = painLanding(level)
            let need = try XCTUnwrap(s.soreLeft[.pull])
            XCTAssertEqual(need, Engine.painStair(seen: 1),
                           "L\(level): a first report assigns the full window")
            assertPosition(s, .pull, landed, "L\(level): first unload step")

            for i in 1...need {
                s = tap(s)
                assertPosition(s, .pull, landed,
                               "L\(level) step \(i): the countdown runs without growth")
                XCTAssertEqual(s.soreLeft[.pull] ?? 0, i < need ? need - i : 0,
                               "L\(level) step \(i): one tick spent")
                XCTAssertEqual(s.sore[.pull] != nil, i < need,
                               "L\(level) step \(i): the episode closes on the last tick")
            }
            // Growth resumes from the NEXT appearance (§31.2 p.2).
            s = tap(s)
            let cap = EngineConfig.maxUp(pattern: .pull, tier: Level.decode(landed.level).tier)
            // v2.22 (spec §33): growth resumes by a SUB-STEP.
            // v2.25 (spec §36.3): and a SET comes back before any dose does.
            assertPosition(s, .pull,
                           Level.riseBy(level: landed.level, sub: landed.sub, cut: landed.cut,
                                        by: min(EngineConfig.deltaPlan, cap),
                                        allowSetsBack: true),
                           "L\(level): growth resumes one appearance later")
            XCTAssertEqual(s.cutOf(.pull), landed.cut - EngineConfig.setsBackPerSession,
                           "L\(level): exactly one set comes back")
        }
    }

    /// Re-marked for v2.25 (spec §36.5), title and subject together: the two
    /// counters run in PARALLEL. "The freeze spends no confirmation" encoded a
    /// QUEUE, and the queue is what held a person on one set for 38
    /// appearances after three reports — 12.7 weeks at three sessions a week,
    /// 19 at two. They answer different questions ("how long to rest" and "has
    /// the pain passed") and have to tick at the same time.
    ///
    /// The expectation is stricter than the one it replaces: instead of two
    /// independent readings it asserts the two counters are EQUAL on every
    /// appearance, which catches a drift in either direction.
    func testTheFreezeAndTheCountdownRunTogether() {
        var s = tap(seeded(20), .plan, discomfort: [.pull])
        let assigned = Engine.painStair(seen: 1)
        var appearances = 0
        while s.freezeRemaining(.pull) > 0 {
            XCTAssertEqual(s.soreLeft[.pull], s.freezeRemaining(.pull),
                           "the countdown runs level with the rest")
            s = tap(s)
            appearances += 1
        }
        XCTAssertEqual(appearances, assigned, "and both are spent in the assigned time")
        XCTAssertNil(s.sore[.pull], "so the last appearance of the rest closes the episode")
        XCTAssertNil(s.soreLeft[.pull], "and takes the countdown with it")
    }

    // MARK: - §31.2 p.3 What does NOT confirm

    /// Re-marked WHOLE for v2.25 (spec §36.5). The old rule — a "less" does
    /// not spend the countdown — tied two different questions together. After
    /// two "less" in a row §19.1 makes the rating GLOBAL, and from that moment
    /// no appearance was ever clean: the episode never closed at all, in 480
    /// cells of 480. The honest signal locked the trainee in and the dishonest
    /// one set them free.
    ///
    /// The countdown now runs on appearances, and safety is held by the
    /// DESCENT instead — which is what this test asserts alongside it: the
    /// closing does not move by a single appearance, and every "hard" walks
    /// the position one more step DOWN. The old form never looked at the
    /// position at all.
    func testLessSpendsTheCountdownAndStillWalksTheLevelDown() throws {
        for hard in [1, 2, 5] {
            var s = intoWaiting(20)
            let need = try XCTUnwrap(s.soreLeft[.pull])
            var want = s.position(.pull)
            for k in 1...hard {
                // The rating is taken under the run (§19.2): an unnamed "less"
                // is TARGETED until then and may never reach `.pull` at all,
                // which would test the subject past its own aim.
                s.lessRun = EngineConfig.lessRunToGlobal
                // The floor of the step is decided by the state the appearance
                // STARTS in: under a live episode an honest "hard" reaches the
                // pain floor (§36.9).
                let floor = s.sore[.pull] != nil
                    ? EngineConfig.setsFloorPain : EngineConfig.setsFloor
                s = tap(s, .less)
                XCTAssertEqual(s.soreLeft[.pull] ?? 0, max(0, need - k),
                               "\(hard)×less, step \(k): a tick is spent like any other")
                want = Level.fallBy(level: want.level, sub: want.sub, cut: want.cut,
                                    by: 1, floor: floor)
                assertPosition(s, .pull, want,
                               "\(hard)×less, step \(k): and the position walks down")
                XCTAssertEqual(s.sore[.pull] != nil, k < need,
                               "\(hard)×less, step \(k): closes on the assigned appearance")
            }
            for i in (hard + 1)...max(hard + 1, need) where i <= need {
                s = tap(s)
                XCTAssertEqual(s.sore[.pull] != nil, i < need,
                               "\(hard)×less: still on schedule at appearance \(i)")
            }
            XCTAssertNil(s.sore[.pull], "\(hard)×less: closed on appearance \(need), not later")
        }
    }

    /// Re-marked for v2.25 (§36.5) for the same reason as the "less" case: the
    /// predicate stopped reading whether the plan was manageable. A shortfall
    /// spends a tick like any other appearance — and the subject of the block,
    /// "honesty is not overridden", is asserted exactly as before: the
    /// position goes DOWN and the gate proves the descent adds no load.
    func testAFactBelowThePlanSpendsATickAndStillGoesDown() throws {
        let s = intoWaiting(20)
        let need = try XCTUnwrap(s.soreLeft[.pull])
        let w = Engine.generateSession(s)
        let ex = try XCTUnwrap(w.exercises.first { $0.pattern == .pull })
        let before = s.position(.pull)
        let low = Engine.applyFeedback(state: s, session: w, result: .plan,
                                       overrides: [.pull: max(0, ex.load - 2)])
        XCTAssertEqual(low.soreLeft[.pull], need - 1, "a shortfall spends one tick")
        XCTAssertEqual(low.sore[.pull], Engine.painStair(seen: 1),
                       "one appearance closes nothing")
        XCTAssertLessThan(Level.posOrd(low.position(.pull)), Level.posOrd(before),
                          "the position still goes down")
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: before.level,
                                     to: low.levels[.pull]!, fromSub: before.sub,
                                     toSub: low.sub[.pull] ?? 0,
                                     fromCut: before.cut, toCut: low.cutOf(.pull)),
                      "and the descent never adds load (§30.2)")
    }

    /// A skip is not an appearance, and a hold is not a confirmation — it puts
    /// the pattern back under a freeze (§31.2 p.6).
    func testSkipsAndHoldsFreezeTheCountdown() throws {
        var s = intoWaiting(20)
        let need = try XCTUnwrap(s.soreLeft[.pull])
        for k in 1...(need + 3) {
            s = tap(s, .plan, skipped: [.pull])
            XCTAssertEqual(s.soreLeft[.pull], need, "skip \(k): no tick spent")
        }
        XCTAssertEqual(s.sore[.pull], Engine.painStair(seen: 1),
                       "the episode outlives a run of skips")

        // v2.22 (spec §33): the hold clause went with the input. The subject —
        // only CLEAN appearances spend a tick — stands, and a repeat pain report
        // restarts both the rest and the countdown rather than spending it.
        let again = tap(intoWaiting(20), .plan, discomfort: [.pull])
        XCTAssertEqual(again.freezeRemaining(.pull), Engine.painStair(seen: 2),
                       "a repeat report deepens the rest")
        XCTAssertEqual(again.soreLeft[.pull], Engine.painStair(seen: 2),
                       "and restarts the countdown at the new assignment")
    }

    // MARK: - §31.2 p.4 A repeat report

    /// The rest ladder and the two-step unload both read the ASSIGNMENT, so
    /// they stay correct after any number of clean appearances — and the
    /// countdown restarts at the new assignment, lengthening the way back.
    ///
    /// This is the check that a single-field design fails: with the countdown
    /// living in `sore`, one clean appearance would leave 2 there, the ladder
    /// would hand out 4 instead of 6, and the second unload step would never
    /// fire at all (§31.3).
    func testTheLadderIsStillReadAfterCleanAppearances() throws {
        var s = intoWaiting(20)
        s = tap(s)                                   // one clean appearance
        XCTAssertEqual(s.soreLeft[.pull], Engine.painStair(seen: 1) - 1)

        s = tap(s, .plan, discomfort: [.pull])       // the repeat report
        // v2.25 (§36.5): the ladder is read off the HISTORY, `painSeen`, not
        // off the assignment — with an episode now closing on a countdown, a
        // repeat report tied to `sore` would have stopped deepening the rest.
        let rung = Engine.painStair(seen: 2)
        XCTAssertEqual(s.painSeen[.pull], 2, "the memory of pain counts the reports")
        XCTAssertEqual(s.sore[.pull], rung, "the ladder is read from the history")
        XCTAssertEqual(s.freezeRemaining(.pull), rung, "and so is the rest")
        XCTAssertEqual(s.cutOf(.pull),
                       Level.cutMax(level: 20, floor: EngineConfig.setsFloorPain),
                       "the second unload step fires, not skipped")
        XCTAssertEqual(s.soreLeft[.pull], rung, "the countdown restarts at the new assignment")

        // And the way back is now as long as the new assignment. v2.25: the
        // freeze and the countdown are one and the same run of appearances.
        for i in 1..<rung {
            s = tap(s)
            XCTAssertNotNil(s.sore[.pull], "still open on clean appearance \(i) of \(rung)")
        }
        s = tap(s)
        XCTAssertNil(s.sore[.pull], "closes exactly on clean appearance \(rung)")
    }

    /// The descent stays bounded at two steps: a third report moves no level,
    /// and clean appearances in between do not unlock a third one (§30.6 p.3).
    func testAThirdReportStillMovesNoLevel() throws {
        var s = intoWaiting(20)
        s = tap(s)
        s = tap(s, .plan, discomfort: [.pull])                    // second report
        let twoSteps = s.position(.pull)
        s = tap(s)
        s = tap(s, .plan, discomfort: [.pull])                    // third report
        // v2.25 (§36.5): nothing cuts below the pain floor — the depth of the
        // rest grows, the depth of the cut does not.
        assertPosition(s, .pull, twoSteps, "the third report moves no position")
        XCTAssertEqual(s.sore[.pull], EngineConfig.freezeCapAppearances,
                       "the ladder tops out")
        XCTAssertEqual(s.soreLeft[.pull], EngineConfig.freezeCapAppearances,
                       "and the countdown follows it")
    }

    // MARK: - §21.2 p.5 The fast route is untouched

    /// A fact at or above the plan closes the episode on the spot and grows in
    /// the same move — at any depth of the countdown, the untouched one
    /// included.
    func testAFactStillClosesImmediatelyAndGrowsInTheSameMove() throws {
        for spent in 0..<Engine.painStair(seen: 1) {
            var s = intoWaiting(20)
            for _ in 0..<spent { s = tap(s) }
            guard s.sore[.pull] != nil else { continue }
            let entry = s.position(.pull)
            let w = Engine.generateSession(s)
            let load = try XCTUnwrap(w.exercises.first { $0.pattern == .pull }?.load)
            let conf = Engine.applyFeedback(state: s, session: w, result: .plan,
                                            overrides: [.pull: load])
            XCTAssertNil(conf.sore[.pull], "\(spent) spent: closed at once")
            XCTAssertNil(conf.soreLeft[.pull], "\(spent) spent: the countdown goes too")
            // v2.25 (§36.3): the fast route resumes growth by the same step as
            // everything else — a SET first, and no more than one a session.
            assertPosition(conf, .pull,
                           Level.riseBy(level: entry.level, sub: entry.sub, cut: entry.cut,
                                        by: EngineConfig.deltaPlan, allowSetsBack: true),
                           "\(spent) spent: and grows in the same move")
        }
    }

    // MARK: - §31.2 p.1 Under the illness lens

    /// The lens already spends `frozen`, so it spends the countdown too, on
    /// the same predicate: the same appearance cannot mean different things
    /// depending on whether the trainee tapped "I was sick".
    func testTheIllnessLensSpendsTheCountdownOnTheSamePredicate() throws {
        var s = Engine.applyIllness(state: intoWaiting(20))
        let need = try XCTUnwrap(s.soreLeft[.pull])
        XCTAssertGreaterThan(EngineConfig.illnessSessions, need,
                             "the lens has to outlast the countdown for this to be a test")

        // v2.25 (§36.5): the predicate no longer reads the rating — under the
        // lens or anywhere else. The two copies of the branch must agree word
        // for word, and that is what is asserted here.
        let hard = tap(s, .less)
        XCTAssertEqual(hard.soreLeft[.pull], need - 1,
                       "a \"less\" under the lens spends a tick like any appearance")

        for i in 1...need {
            XCTAssertGreaterThan(s.illness, 0, "the lens is still on at step \(i)")
            s = tap(s)
            XCTAssertEqual(s.soreLeft[.pull] ?? 0, i < need ? need - i : 0,
                           "a clean appearance under the lens spends a tick (step \(i))")
        }
        XCTAssertNil(s.sore[.pull], "the episode closes under the lens")
        assertPosition(s, .pull, painLanding(20),
                       "and the position still never moved under it (§22.4)")
    }

    // MARK: - §21.3 The cross-credit

    /// The credit stays blocked while the episode lives and flows again once
    /// the COUNTDOWN closes it — not only once a fact does.
    func testTheCreditResumesAfterTheCountdownCloses() throws {
        var s = seeded(10, hasBar: true)
        var (state, w) = advance(s, to: .pullBar)
        s = Engine.applyFeedback(state: state, session: w, result: .plan,
                                 discomfort: [.pullBar])
        var guardCount = 0
        while s.sore[.pullBar] != nil, guardCount < 60 {
            guardCount += 1
            let before = s.position(.pullBar)
            w = Engine.generateSession(s)
            let trained = w.exercises.first { Pattern.pullSide.contains($0.pattern) }?.pattern
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            if trained != .pullBar {
                assertPosition(s, .pullBar, before,
                               "no credit reaches a branch inside an episode")
            }
        }
        XCTAssertNil(s.sore[.pullBar], "the branch's episode closed on the countdown")

        w = Engine.generateSession(s)
        let trained = w.exercises.first { Pattern.pullSide.contains($0.pattern) }?.pattern
        if trained != .pullBar {
            // v2.25 (§36.3): the credit is measured on the SHARED scale — a
            // growth event spent on a set coming back carries credit too.
            let before = Level.posOrd(s.position(.pullBar))
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            XCTAssertEqual(Level.posOrd(s.position(.pullBar)), before + 1,
                           "and the credit flows again after a countdown close")
        }
    }

    // MARK: - §31.2 p.7 / §31.3 Breaks, serialization, sanitizing

    /// A break moves levels but never the episode or its countdown — the same
    /// asymmetry of error `frozen` and `sore` already carry (§21.2 p.8).
    func testBreaksLeaveTheCountdownAlone() throws {
        let spent = tap(intoWaiting(20))
        let need = try XCTUnwrap(spent.soreLeft[.pull])
        let decayed = Engine.applySilentDecay(state: spent, gapDays: 10)
        XCTAssertEqual(decayed.soreLeft[.pull], need, "a silent decay spends no tick")
        let back = Engine.applyComeback(state: decayed, gapDays: 30, alreadyDecayed: true)
        XCTAssertEqual(back.soreLeft[.pull], need, "nor does a comeback")
        XCTAssertEqual(back.sore[.pull], Engine.painStair(seen: 1), "the episode is intact")
    }

    /// The sanitizer heals the field the way the reference does: a tick with
    /// no live episode is garbage, a tick above its own assignment is
    /// impossible, and a MISSING tick for a live episode means the full
    /// window — that is how a state written before v2.20 reads.
    func testTheSanitizerHealsTheCountdown() {
        var s = seeded(10)
        s.sore = [.pull: 6, .squat: EngineConfig.freezeAppearances]
        s.soreLeft = [.pull: 2, .squat: 99, .hinge: 4]
        let healed = s.sanitized()
        XCTAssertEqual(healed.soreLeft[.pull], 2, "a valid tick survives")
        XCTAssertEqual(healed.soreLeft[.squat], EngineConfig.freezeAppearances,
                       "a tick above the assignment clamps down to it")
        XCTAssertNil(healed.soreLeft[.hinge], "a tick with no episode is dropped")

        var legacy = seeded(10)
        legacy.sore = [.pull: EngineConfig.freezeAppearances]
        legacy.soreLeft = [:]
        XCTAssertEqual(legacy.sanitized().soreLeft[.pull], EngineConfig.freezeAppearances,
                       "a pre-v2.20 episode gets the whole confirmation window")
    }

    /// A file written before v2.20 carries no `soreLeft` key at all and must
    /// decode into a full window, not into an episode that closes at once.
    func testAStateFileWithoutTheFieldDecodesIntoAFullWindow() throws {
        var s = seeded(10)
        s.sore = [.pull: 6]
        s.soreLeft = [.pull: 4]
        // Round-trip keeps both halves.
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(back.sore[.pull], 6)
        XCTAssertEqual(back.soreLeft[.pull], 4)

        // Strip the key the way a v2.19 file has it stripped.
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
                                    as? [String: Any])
        json.removeValue(forKey: "soreLeft")
        XCTAssertNil(json["soreLeft"])
        let legacy = try JSONDecoder().decode(
            EngineState.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.sore[.pull], 6, "the episode still decodes")
        XCTAssertEqual(legacy.soreLeft[.pull], 6,
                       "and its countdown starts full — no migration needed")
    }

    /// The plan never reads the countdown: the same levels give the same
    /// session whatever the field holds.
    func testTheCountdownDoesNotReachThePlan() {
        var withField = seeded(20)
        withField.sore = [.pull: EngineConfig.freezeAppearances]
        withField.soreLeft = [.pull: 1]
        XCTAssertEqual(Engine.generateSession(seeded(20)).exercises.map(\.load),
                       Engine.generateSession(withField).exercises.map(\.load))
    }

    // MARK: - §31 The number the wave exists for

    /// A tap-only trainee gets out of an episode at all — the number the wave
    /// exists for. Before v2.20 this loop never terminated.
    ///
    /// Re-marked for v2.25 (spec §36.5): the counters run in parallel, so the
    /// old `2 × freezeAppearances + 1` was the price of the QUEUE, not of the
    /// rest. It also gave 38 appearances on one set after three reports. The
    /// figure is `painStair + 1` now, and it is still derived from the
    /// assignment rather than written down.
    func testTheTapOnlyPathIsFinite() throws {
        // v2.22 (spec §33): "the level moved" is no longer the sign that growth
        // resumed — the first growth event moves the SUB-STEP.
        // v2.25 (spec §36.3): or gives a SET back, which the pair (level, sub)
        // cannot see at all — so the path is measured on the shared measure.
        var s = tap(seeded(20), .plan, discomfort: [.pull])
        let landed = Level.posOrd(s.position(.pull))
        var appearances = 0
        while Level.posOrd(s.position(.pull)) == landed, appearances < 200 {
            s = tap(s)
            appearances += 1
        }
        XCTAssertEqual(appearances, Engine.painStair(seen: 1) + 1,
                       "the assigned rest, spent alongside the countdown, and one to resume")
        XCTAssertGreaterThan(Level.posOrd(s.position(.pull)), landed)
    }
}
