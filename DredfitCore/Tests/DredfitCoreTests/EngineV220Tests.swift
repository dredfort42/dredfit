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

    /// Report pain on `.pull` from `level`, then burn exactly the assigned
    /// rest — the state that comes back is WAITING with a full countdown.
    /// `.pull` is in every session without a bar, so an appearance is a step.
    private func intoWaiting(_ level: Int) -> EngineState {
        var s = tap(seeded(level), .plan, discomfort: [.pull])
        while s.freezeRemaining(.pull) > 0 { s = tap(s) }
        return s
    }

    // MARK: - §31.2 p.1-2 The countdown closes the episode

    /// Clean appearances spend the countdown; the session that closes it does
    /// NOT grow, and the next one does. The length is read from the state,
    /// never hard-coded: however much rest was assigned is however much has to
    /// be confirmed.
    func testCleanAppearancesCloseTheEpisodeAndGrowthResumesNext() throws {
        for level in [8, 20, 24, 40, EngineConfig.levelMax] {
            var s = intoWaiting(level)
            let landed = Level.tierFloor(level)
            let need = try XCTUnwrap(s.soreLeft[.pull])
            XCTAssertEqual(need, EngineConfig.freezeAppearances,
                           "L\(level): a first report assigns the full window")
            XCTAssertEqual(s.levels[.pull], landed, "L\(level): first unload step")

            for i in 1...need {
                s = tap(s)
                XCTAssertEqual(s.levels[.pull], landed,
                               "L\(level) step \(i): the countdown runs without growth")
                XCTAssertEqual(s.soreLeft[.pull] ?? 0, i < need ? need - i : 0,
                               "L\(level) step \(i): one tick spent")
                XCTAssertEqual(s.sore[.pull] != nil, i < need,
                               "L\(level) step \(i): the episode closes on the last tick")
            }
            // Growth resumes from the NEXT appearance (§31.2 p.2).
            s = tap(s)
            let cap = EngineConfig.maxUp(pattern: .pull, tier: Level.decode(landed).tier)
            // v2.22 (spec §33): growth resumes by a SUB-STEP.
            assertPosition(s, .pull,
                           Level.rise(level: landed, sub: 0,
                                      by: min(EngineConfig.deltaPlan, cap)),
                           "L\(level): growth resumes one appearance later")
        }
    }

    /// The freeze spends no tick of the countdown: assigned rest is rest, not
    /// evidence that the pain is gone (§31.2 p.1 — "in the waiting state").
    func testTheFreezeSpendsNoConfirmation() {
        var s = tap(seeded(20), .plan, discomfort: [.pull])
        while s.freezeRemaining(.pull) > 0 {
            XCTAssertEqual(s.soreLeft[.pull], EngineConfig.freezeAppearances,
                           "the countdown stands while the rest is being served")
            s = tap(s)
        }
        XCTAssertEqual(s.soreLeft[.pull], EngineConfig.freezeAppearances)
        XCTAssertEqual(s.sore[.pull], EngineConfig.freezeAppearances)
    }

    // MARK: - §31.2 p.3 What does NOT confirm

    /// A "less" rating is not a clean appearance: the countdown stands, and
    /// every such session pushes the closing back by exactly one appearance.
    func testLessDoesNotSpendTheCountdown() throws {
        for hard in [1, 2, 5] {
            var s = intoWaiting(20)
            let need = try XCTUnwrap(s.soreLeft[.pull])
            for k in 1...hard {
                s = tap(s, .less)
                XCTAssertEqual(s.soreLeft[.pull], need,
                               "\(hard)×less, step \(k): the countdown stands")
            }
            for _ in 1..<need { s = tap(s) }
            XCTAssertNotNil(s.sore[.pull],
                            "\(hard)×less: one clean appearance short, still open")
            s = tap(s)
            XCTAssertNil(s.sore[.pull], "\(hard)×less: closes exactly one step later")
        }
    }

    /// A fact BELOW the plan does not confirm either — and the level still
    /// goes down, never adding load on the way: honesty is not overridden.
    func testAFactBelowThePlanDoesNotSpendTheCountdown() throws {
        let s = intoWaiting(20)
        let need = try XCTUnwrap(s.soreLeft[.pull])
        let w = Engine.generateSession(s)
        let ex = try XCTUnwrap(w.exercises.first { $0.pattern == .pull })
        let before = try XCTUnwrap(s.levels[.pull])
        let low = Engine.applyFeedback(state: s, session: w, result: .plan,
                                       overrides: [.pull: max(0, ex.load - 2)])
        XCTAssertEqual(low.soreLeft[.pull], need, "a shortfall spends no tick")
        XCTAssertEqual(low.sore[.pull], EngineConfig.freezeAppearances, "and closes nothing")
        let after = try XCTUnwrap(low.levels[.pull])
        XCTAssertLessThan(after, before, "the level still goes down")
        XCTAssertTrue(Level.noHarder(pattern: .pull, from: before, to: after),
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
        XCTAssertEqual(s.sore[.pull], EngineConfig.freezeAppearances,
                       "the episode outlives a run of skips")

        // v2.22 (spec §33): the hold clause went with the input. The subject —
        // only CLEAN appearances spend a tick — stands, and a repeat pain report
        // restarts both the rest and the countdown rather than spending it.
        let again = tap(intoWaiting(20), .plan, discomfort: [.pull])
        XCTAssertEqual(again.freezeRemaining(.pull), 2 * EngineConfig.freezeAppearances,
                       "a repeat report doubles the rest")
        XCTAssertEqual(again.soreLeft[.pull], 2 * EngineConfig.freezeAppearances,
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
        XCTAssertEqual(s.soreLeft[.pull], EngineConfig.freezeAppearances - 1)
        let landedFirst = try XCTUnwrap(s.levels[.pull])

        s = tap(s, .plan, discomfort: [.pull])       // the repeat report
        let rung = min(EngineConfig.freezeAppearances * 2, EngineConfig.freezeCapAppearances)
        XCTAssertEqual(s.sore[.pull], rung, "the ladder is read from the assignment")
        XCTAssertEqual(s.freezeRemaining(.pull), rung, "and so is the rest")
        XCTAssertEqual(s.levels[.pull], Level.unload(landedFirst),
                       "the second unload step fires, not skipped")
        XCTAssertEqual(s.soreLeft[.pull], rung, "the countdown restarts at the new assignment")

        // And the way back is now as long as the new assignment.
        while s.freezeRemaining(.pull) > 0 { s = tap(s) }
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
        let twoSteps = try XCTUnwrap(s.levels[.pull])
        s = tap(s)
        s = tap(s, .plan, discomfort: [.pull])                    // third report
        XCTAssertEqual(s.levels[.pull], twoSteps, "the third report moves no level")
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
        for spent in 0..<EngineConfig.freezeAppearances {
            var s = intoWaiting(20)
            for _ in 0..<spent { s = tap(s) }
            let oldL = try XCTUnwrap(s.levels[.pull])
            let w = Engine.generateSession(s)
            let load = try XCTUnwrap(w.exercises.first { $0.pattern == .pull }?.load)
            let conf = Engine.applyFeedback(state: s, session: w, result: .plan,
                                            overrides: [.pull: load])
            XCTAssertNil(conf.sore[.pull], "\(spent) spent: closed at once")
            XCTAssertNil(conf.soreLeft[.pull], "\(spent) spent: the countdown goes too")
            assertPosition(conf, .pull,
                           Level.rise(level: oldL, sub: s.sub[.pull] ?? 0,
                                      by: EngineConfig.deltaPlan),
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

        let hard = tap(s, .less)
        XCTAssertEqual(hard.soreLeft[.pull], need, "a \"less\" under the lens spends no tick")

        for i in 1...need {
            XCTAssertGreaterThan(s.illness, 0, "the lens is still on at step \(i)")
            s = tap(s)
            XCTAssertEqual(s.soreLeft[.pull] ?? 0, i < need ? need - i : 0,
                           "a clean appearance under the lens spends a tick (step \(i))")
        }
        XCTAssertNil(s.sore[.pull], "the episode closes under the lens")
        XCTAssertEqual(s.levels[.pull], Level.tierFloor(20),
                       "and the level still never moved under it (§22.4)")
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
            let before = try XCTUnwrap(s.levels[.pullBar])
            w = Engine.generateSession(s)
            let trained = w.exercises.first { Pattern.pullSide.contains($0.pattern) }?.pattern
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            if trained != .pullBar {
                XCTAssertEqual(s.levels[.pullBar], before,
                               "no credit reaches a branch inside an episode")
            }
        }
        XCTAssertNil(s.sore[.pullBar], "the branch's episode closed on the countdown")

        w = Engine.generateSession(s)
        let trained = w.exercises.first { Pattern.pullSide.contains($0.pattern) }?.pattern
        if trained != .pullBar {
            let before = Level.ordinal(s.position(.pullBar))
            s = Engine.applyFeedback(state: s, session: w, result: .plan)
            XCTAssertEqual(Level.ordinal(s.position(.pullBar)), before + 1,
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
        XCTAssertEqual(back.sore[.pull], EngineConfig.freezeAppearances, "the episode is intact")
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

    /// A tap-only trainee gets out of an episode at all — and in exactly
    /// `2 × freezeAppearances + 1` appearances: the rest, the countdown, and
    /// one more to resume. Before v2.20 this loop never terminated.
    func testTheTapOnlyPathIsFinite() throws {
        // v2.22 (spec §33): "the level moved" is no longer the sign that growth
        // resumed — the first growth event moves the SUB-STEP. The path is
        // measured on the position instead; its length is unchanged.
        var s = tap(seeded(20), .plan, discomfort: [.pull])
        let landed = Level.ordinal(s.position(.pull))
        var appearances = 0
        while Level.ordinal(s.position(.pull)) == landed, appearances < 200 {
            s = tap(s)
            appearances += 1
        }
        XCTAssertEqual(appearances, EngineConfig.freezeAppearances * 2 + 1,
                       "three of rest, three of countdown, one to resume")
        XCTAssertGreaterThan(Level.ordinal(s.position(.pull)), landed)
    }
}
