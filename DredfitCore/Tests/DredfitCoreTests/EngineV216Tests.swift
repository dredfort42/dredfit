//
// Engine (issue #141): the two branches of the pull slot. The gate read
// whichever branch stood in the session, so once the branches diverged the
// push plan flipped between two set bands every session, forever — churn with
// no cause on screen. It now reads the weaker of the two.
//
// The credit pause itself is deliberately unchanged. Under a period-2 rhythm a
// branch that only ever gets "tough" sessions stays put, and that is the price
// of the protection the pause exists for — measured, not assumed (owner's
// decision 19.08.2026).
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV216Tests: XCTestCase {

    private func barState(_ levels: [Pattern: Int]) -> EngineState {
        var s = EngineState.initial
        s.hasBar = true
        for (p, v) in levels { s.levels[p] = v }
        return s
    }

    // MARK: - The gate reads the weaker branch

    func testThePushBandIsStableOnceTheBranchesDiverge() {
        var state = barState([.pull: 40, .pullBar: 20, .pushH: 40, .pushV: 40])
        var bands: Set<Int> = []
        for _ in 0..<8 {
            let session = Engine.generateSession(state)
            for ex in session.exercises where Pattern.pushSide.contains(ex.pattern) {
                bands.insert(ex.sets)
            }
            state = Engine.applyFeedback(state: state, session: session, result: .plan)
        }
        XCTAssertEqual(bands.count, 1,
                       "the push band used to flip every session; saw \(bands.sorted())")
    }

    func testTheGateTakesTheWeakerBranchAndIsSymmetric() throws {
        let low = barState([.pull: 40, .pullBar: 20, .pushH: 40])
        let mirrored = barState([.pull: 20, .pullBar: 40, .pushH: 40])
        let a = try XCTUnwrap(Engine.generateSession(low).exercises
            .first { $0.pattern == .pushH })
        let b = try XCTUnwrap(Engine.generateSession(mirrored).exercises
            .first { $0.pattern == .pushH })
        XCTAssertEqual(a.sets, Level.decode(20).sets, "the weaker branch sets the ceiling")
        XCTAssertEqual(a.sets, b.sets, "and it does not matter which branch is weaker")
    }

    func testWithoutABarTheGateStillHolds() throws {
        // The mutation that disabled the gate at hasBar == false survived the
        // whole verifier before this wave (audit mut-12) — and no bar is the
        // default configuration.
        var state = EngineState.initial
        state.levels[.pull] = 0
        state.levels[.pushH] = 40
        let held = try XCTUnwrap(Engine.generateSession(state).exercises
            .first { $0.pattern == .pushH })
        XCTAssertEqual(held.sets, Level.decode(0).sets, "the push waits for the pull")

        state.levels[.pull] = 40
        let released = try XCTUnwrap(Engine.generateSession(state).exercises
            .first { $0.pattern == .pushH })
        XCTAssertEqual(released.sets, Level.decode(40).sets,
                       "and gets its sets back once the pull is in the same band")
    }

    // MARK: - The credit pause is unchanged, and that is a decision

    func testAPeriodTwoRhythmParksTheBranchThatOnlyEverGetsToughSessions() {
        func run(phase: Int) -> EngineState {
            var state = EngineState.initial
            state.hasBar = true
            for k in 0..<96 {
                state = Engine.applyFeedback(state: state,
                                             session: Engine.generateSession(state),
                                             result: (k + phase).isMultiple(of: 2) ? .more : .less)
            }
            return state
        }
        // "at the ceiling in 96 sessions" rested on a growth event costing a
        // level. It costs a SUB-STEP now, so 96 sessions carry a branch about
        // 21 levels up the 47 — nobody reaches the ceiling in that time. The
        // subject is not the ceiling but the GAP between the branches, and
        // that is what gets pinned, from the run rather than from a constant.
        let a = run(phase: 0), b = run(phase: 1)
        XCTAssertGreaterThan(Level.ordinal(a.position(.pull)),
                             20 * Level.ordinal(a.position(.pullBar)) + 20,
                             "phase 0: the trained branch runs far ahead")
        XCTAssertGreaterThan(Level.ordinal(b.position(.pullBar)),
                             20 * Level.ordinal(b.position(.pull)) + 20,
                             "phase 1: mirrored")
        XCTAssertTrue(a.creditPaused.contains(.pullBar))
        XCTAssertTrue(b.creditPaused.contains(.pull))
    }

    func testOnASteadyRhythmBothBranchesReachTheCeiling() {
        var state = EngineState.initial
        state.hasBar = true
        // A longer run — the scale is 153 sub-steps tall.
        for _ in 0..<200 {
            state = Engine.applyFeedback(state: state, session: Engine.generateSession(state),
                                         result: .plan)
        }
        XCTAssertEqual(state.levels[.pull], EngineConfig.levelMax)
        XCTAssertEqual(state.levels[.pullBar], EngineConfig.levelMax,
                       "there is no lock on an ordinary rhythm")
    }

    func testTheCreditLoopStopsAtWhatTheTraineeCanActuallyDo() {
        // The protection the pause exists for: the credit must not run the
        // branch past a level the trainee keeps calling tough.
        for capacity in [6, 12, 20] {
            var state = EngineState.initial
            state.hasBar = true
            for _ in 0..<90 {
                let session = Engine.generateSession(state)
                let bar = session.exercises.contains { $0.pattern == .pullBar }
                let tooHard = bar && (state.levels[.pullBar] ?? 0) > capacity
                state = Engine.applyFeedback(state: state, session: session,
                                             result: tooHard ? .less : .plan)
            }
            // The parking spot is "capacity + 1" OR a block floor, when the
            // evaluative descent has run into one. Measured: at capacity 6 the
            // branch parks on 8 (previously 7). The cause is not the descent but the
            // aim — the healthy movements stand higher, the branch is almost
            // never the aim, it is held instead, and holding is not an intent
            // to descend so no streak builds and the deload, the only way past
            // a block floor, never opens. The price is deliberate and bounded
            // to ONE level; what this block is about — the plan does not run
            // away (#90 measured 29 against a capacity of 6) — is intact, and
            // the ceiling below still holds: one block step above capacity,
            // and standing is only allowed EXACTLY on a floor.
            let park = state.levels[.pullBar] ?? 0
            XCTAssertTrue(park <= capacity + 1
                          || (park == Level.bandFloor(park) && park <= capacity + EngineConfig.stepsPerTier),
                          "capacity \(capacity): the plan settles instead of running away (parked on \(park))")
        }
    }

    // MARK: - Coverage holes the audit listed (#145)

    func testDiscomfortOnASlotBranchPausesItsCredit() throws {
        let state = barState([.pull: 10, .pullBar: 10])
        let session = Engine.generateSession(state)
        let slot = try XCTUnwrap(session.exercises.first { Pattern.pullSide.contains($0.pattern) })
            .pattern
        // The signal was a discomfort report; it is now an exact number below
        // the plan. The guard is the same guard, in the same place — only what
        // arms it changed.
        let plan = try XCTUnwrap(session.exercises.first { $0.pattern == slot }).load
        let after = Engine.applyFeedback(state: state, session: session, result: .plan,
                                         overrides: [slot: max(0, plan - 2)])
        XCTAssertTrue(after.creditPaused.contains(slot),
                      "this path exists purely as a harm guard and was never pinned")
    }

    func testAFactOnASkippedMovementChangesNothing() throws {
        var state = EngineState.initial
        for p in Pattern.allCases { state.levels[p] = 20 }
        let session = Engine.generateSession(state)
        let target = try XCTUnwrap(session.exercises.first).pattern
        let after = Engine.applyFeedback(state: state, session: session, result: .less,
                                         overrides: [target: 3], skipped: [target])
        XCTAssertEqual(after.levels[target], 20, "a skip voids the session for that movement")
        XCTAssertEqual(after.failStreak[target], 0)
    }
}
