//
//  EngineV26Tests.swift
//  DredfitCoreTests
//
//  The pinned input: the hold-this-level request, the second and milder way
//  into the freeze. Mirrors the "Discomfort and the freeze" block of
//  EngineV25Tests one for one — every difference between the two files is a
//  difference between the two inputs: the pinning session is processed, not
//  voided. Plus the two cases that only exist here: pinned + skipped
//  reproducing discomfort, and the reporting appearance not being consumed.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV26Tests: XCTestCase {

    /// A state where every pattern sits at the same level, so one session
    /// exercises six patterns at once.
    private func seeded(level: Int, counter: Int = 0) -> EngineState {
        var state = EngineState.initial
        state.counter = counter
        for p in Pattern.allCases { state.levels[p] = level }
        return state
    }

    private func report(_ state: EngineState, _ result: FeedbackResult,
                        pinned: Set<Pattern> = [], discomfort: Set<Pattern> = [],
                        skipped: Set<Pattern> = [],
                        overrides: [Pattern: Int] = [:]) -> EngineState {
        Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                             result: result, overrides: overrides,
                             skipped: skipped, discomfort: discomfort,
                             pinned: pinned)
    }

    // MARK: - The pin and the freeze

    /// The pinning session is processed, not voided — but growth clamps to
    /// the old level, the streak stays where it was, and the pattern comes
    /// out frozen.
    func testAPinClampsGrowthAndFreezes() {
        var state = seeded(level: 12)
        state.failStreak[.pull] = 1
        let next = report(state, .more, pinned: [.pull])

        XCTAssertEqual(next.levels[.pull], 12, "growth is clamped to the old level")
        XCTAssertEqual(next.failStreak[.pull], 1, "the streak neither grows nor resets")
        XCTAssertEqual(next.freezeRemaining(.pull), EngineConfig.freezeAppearances)
        XCTAssertEqual(next.counter, state.counter + 1, "the workout still happened")
        XCTAssertEqual(next.levels[.squat], 14, "a neighbour still climbs")
    }

    /// Pinned, the pattern keeps its place in the plan and stays put for
    /// exactly N appearances — `pull` is in every session, so appearances are
    /// sessions here.
    func testThePinnedLevelStaysForExactlyThreeAppearances() {
        var state = report(seeded(level: 12), .plan, pinned: [.pull])
        for left in stride(from: EngineConfig.freezeAppearances, to: 0, by: -1) {
            XCTAssertEqual(state.freezeRemaining(.pull), left)
            state = report(state, .more)
            XCTAssertEqual(state.levels[.pull], 12, "no growth while pinned")
        }
        XCTAssertEqual(state.freezeRemaining(.pull), 0, "the rest has run out")
        state = report(state, .more)
        XCTAssertEqual(state.levels[.pull], 14, "growth returns")
    }

    /// Honesty is never overridden — and unlike discomfort, the fact lands in
    /// the pinning session itself: a fact below the plan takes the level down
    /// right there, one above it is clamped to where it was.
    func testAFactStillMovesAPinnedPatternDown() {
        let down = report(seeded(level: 12), .plan, pinned: [.pull], overrides: [.pull: 8])
        XCTAssertLessThan(down.levels[.pull]!, 12, "a fact below the plan still lands")
        XCTAssertEqual(down.failStreak[.pull], 0, "and the streak does not grow on it")
        let up = report(seeded(level: 12), .plan, pinned: [.pull], overrides: [.pull: 99])
        XCTAssertEqual(up.levels[.pull], 12, "a fact above the plan cannot grow it")
    }

    /// No punishment for asking to ease off: the rating still takes its step
    /// down, but the streak neither grows nor resets, so the deload cannot
    /// fire on top of a pin — the one behaviour this input exists to prevent.
    func testAPinCannotDeload() {
        var state = seeded(level: 20)
        state.failStreak[.pull] = 2
        state = report(state, .less, pinned: [.pull])
        XCTAssertEqual(state.levels[.pull], 19, "the honest −1 still lands")
        XCTAssertEqual(state.failStreak[.pull], 2, "but the third shortfall is not counted")
        for _ in 0..<EngineConfig.freezeAppearances { state = report(state, .less) }

        XCTAssertEqual(state.levels[.pull], 16, "four shortfalls, four steps — no deload")
        XCTAssertEqual(state.failStreak[.pull], 2, "the streak stayed where it was")
        state = report(state, .less)
        XCTAssertEqual(state.levels[.pull], 12, "once thawed the deload is possible again")
    }

    /// A repeat pin starts the rest over — whichever input armed it.
    func testARepeatPinRefreshesTheCounter() {
        var state = report(seeded(level: 12), .plan, discomfort: [.pull])
        state = report(state, .plan)
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances - 1)
        state = report(state, .plan, pinned: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances,
                       "a pin refreshes a discomfort-armed freeze too")
    }

    /// A skip freezes the counter with everything else — the pattern was not
    /// trained, so the appearance does not count.
    func testASkipDoesNotSpendAPinnedAppearance() {
        var state = report(seeded(level: 12), .plan, pinned: [.pull])
        let before = state.freezeRemaining(.pull)
        state = report(state, .plan, skipped: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), before)
        XCTAssertEqual(state.levels[.pull], 12)
    }

    /// Named in both, the skip voids the session as usual and the pin still
    /// arms the rest — no precedence rule, the two effects are orthogonal.
    func testAPinThroughASkipStillArmsTheRest() {
        let state = report(seeded(level: 12), .more, pinned: [.pull],
                           skipped: [.pull], overrides: [.pull: 99])
        XCTAssertEqual(state.levels[.pull], 12, "the skip voids the session")
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances,
                       "the pin still arms the rest")
    }

    /// §16 rule 10: at level 0 there is nothing below to pin and calibration
    /// is not touched as code — but the pin's clamp still wins, so even a
    /// calibration fact leaves the level at 0 while the rest is armed.
    func testAPinAtZeroArmsTheRestAndTheLevelStaysAtZero() {
        let state = report(EngineState.initial, .plan, pinned: [.pull],
                           overrides: [.pull: 20])
        XCTAssertEqual(state.levels[.pull], 0, "a calibration fact cannot lift a pinned zero")
        XCTAssertEqual(state.freezeRemaining(.pull), EngineConfig.freezeAppearances,
                       "the rest is armed all the same")
    }

    /// A pattern that is not in the session is a no-op, as with skips.
    func testAPinOutsideTheSessionIsANoOp() {
        let state = seeded(level: 12)
        let inSession = Set(Engine.generateSession(state).exercises.map(\.pattern))
        let outside = Pattern.allCases.first { !inSession.contains($0) }!
        XCTAssertEqual(report(state, .plan, pinned: [outside]).freezeRemaining(outside), 0)
    }

    /// A break lowers the levels but must not thaw a pin-armed rest.
    func testBreaksDoNotThawAPinnedRest() {
        let rested = report(seeded(level: 20), .plan, pinned: [.pull])
        let left = rested.freezeRemaining(.pull)

        let decayed = Engine.applySilentDecay(state: rested, gapDays: 10)
        XCTAssertEqual(decayed.freezeRemaining(.pull), left, "silent decay keeps the rest")
        XCTAssertEqual(decayed.levels[.pull], 19, "and still takes the step")

        let back = Engine.applyComeback(state: decayed, gapDays: 16, alreadyDecayed: true)
        XCTAssertEqual(back.freezeRemaining(.pull), left, "the comeback keeps it too")
        XCTAssertEqual(back.levels[.pull], 18, "the two drops still do not stack")
        XCTAssertEqual(report(back, .more).levels[.pull], 18, "and it is still pinned")
    }

    // MARK: - The identity and the reporting appearance

    /// The identity the whole wave rests on, across the level lattice:
    /// `pinned` arms the rest, `skipped` voids the session, discomfort does
    /// both — so pinned + skipped is discomfort, state for state.
    func testAPinPlusASkipReproducesDiscomfort() {
        for result in [FeedbackResult.less, .plan, .more] {
            for level in 0...EngineConfig.levelMax {
                var state = seeded(level: level)
                state.failStreak[.pull] = 1
                let viaPin = report(state, result, pinned: [.pull], skipped: [.pull])
                let viaDiscomfort = report(state, result, discomfort: [.pull])
                XCTAssertEqual(viaPin, viaDiscomfort,
                               "pinned + skipped ≠ discomfort at level \(level), \(result)")
            }
        }
    }

    /// The reporting appearance is never consumed: a pattern pinned in a
    /// session where it was already frozen with 2 appearances left comes out
    /// of that session with exactly 3 — not 1 (a fresh read decremented) and
    /// not 2 (a decrement instead of the refresh).
    func testTheReportingAppearanceIsNotConsumed() {
        var state = report(seeded(level: 12), .plan, pinned: [.pull])
        state = report(state, .plan)
        XCTAssertEqual(state.freezeRemaining(.pull), 2, "two appearances left")
        state = report(state, .plan, pinned: [.pull])
        XCTAssertEqual(state.freezeRemaining(.pull), 3, "exactly three, not one and not two")
        XCTAssertEqual(state.levels[.pull], 12, "and the level is still held")
    }

    // MARK: - Serialization

    /// A pin adds no state field: a pin-armed rest lives in `frozen` and
    /// round-trips through the state file exactly as a discomfort-armed one.
    func testAPinnedRestRoundTripsThroughTheStateFile() throws {
        let rested = report(seeded(level: 12), .plan, pinned: [.pull])
        let data = try JSONEncoder().encode(rested)
        let back = try JSONDecoder().decode(EngineState.self, from: data)
        XCTAssertEqual(back, rested)
        XCTAssertEqual(back.freezeRemaining(.pull), EngineConfig.freezeAppearances)
    }
}
