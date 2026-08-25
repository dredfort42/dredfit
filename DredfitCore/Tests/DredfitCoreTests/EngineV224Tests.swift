//
// Engine — RE-MARKED.
//
// is removed by this wave EXCEPT, the shared sets floor, which moves into the
// shared floor and becomes the ONLY floor. So four of the six tests here are
// gone with the budget — the shortfall under ten per cent, "shrinking the
// budget never lengthens the session", "no limit is identical to no budget",
// and "the tightest budget keeps every movement": all four measured the
// quality of a trim that no longer exists.
//
//  The two that survive did not measure the budget, they measured the FLOOR
//  and what a cut is allowed to touch. Both are kept word for word with the
//  axis swapped: sets used to be taken off by the budget, they are now taken
//  off by the handle, and neither invariant cares which lever moved.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

final class EngineV224Tests: XCTestCase {

    private func seeded(_ level: Int, bar: Bool = false, counter: Int = 0) -> EngineState {
        var s = EngineState.initial
        s.hasBar = bar
        s.counter = counter
        for p in Pattern.allCases { s.levels[p] = level }
        return s
    }

    private func split(pull: Int, pullBar: Int, others: Int,
                       bar: Bool = true, counter: Int = 0) -> EngineState {
        var s = seeded(others, bar: bar, counter: counter)
        s.levels[.pull] = pull
        s.levels[.pullBar] = pullBar
        return s
    }

    /// Rule 3: "skip the remaining sets", the gesture the
    /// workout screen put in place of the removed session-wide handle. The
    /// same cut on every movement, but set ONE AT A TIME through `setCut`,
    /// because there is no other way onto the axis now. Repeats the removed
    /// `shorterSession` step for step — `max(current, k)` in `allCases` order
    /// — so the tests written against it keep THEIR numbers. Their subject is
    /// the floor and the composition, not the gesture that moved the axis.
    private func cutEveryPattern(_ state: EngineState, _ steps: Int) -> EngineState {
        var next = state
        for p in Pattern.allCases {
            next = Engine.setCut(state: next, pattern: p, cut: max(next.cutOf(p), steps))
        }
        return next
    }

    // MARK: - The one floor

    /// The sweep the spec asks for, re-marked: no combination of HANDLE and
    /// gate may put any exercise below two sets — or above the ceiling, or
    /// hand out more per-set doses than there are sets.
    ///
    /// The budget axis is replaced by the handle's own, and the sweep is not
    /// narrowed: steps 4 and 9 are past any admissible cut on every band, so
    /// they check that the handle CLAMPS at the floor rather than dropping the
    /// plan through it.
    func testNoCombinationOfHandleAndGateGoesBelowTheFloor() {
        for steps in [0, 1, 2, 3, 4, 9] {
            for level in 0...EngineConfig.levelMax {
                for counter in 0..<8 {
                    for bar in [false, true] {
                        let states = [
                            seeded(level, bar: bar, counter: counter),
                            split(pull: 0, pullBar: 0, others: level,
                                  bar: bar, counter: counter),
                            split(pull: EngineConfig.levelMax, pullBar: 0, others: level,
                                  bar: bar, counter: counter),
                        ]
                        for state in states {
                            let handled = cutEveryPattern(state, steps)
                            for ex in Engine.generateSession(handled).exercises {
                                XCTAssertGreaterThanOrEqual(
                                    ex.sets, EngineConfig.setsFloor,
                                    "L\(level) c\(counter) bar=\(bar) handle \(steps): "
                                    + "\(ex.pattern) on \(ex.sets) sets")
                                XCTAssertLessThanOrEqual(ex.sets, EngineConfig.setsMax)
                                if let loads = ex.loads {
                                    XCTAssertEqual(loads.count, ex.sets,
                                        "L\(level): \(ex.pattern) loads vs sets")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - A cut takes sets and nothing else

    /// Word for word the old claim, with the handle as the lever: the list of
    /// movements, the variations, the doses and the levels are the ones the
    /// full plan had. This is what "no new state field" buys — the handle is
    /// the same `cut` the engine already reasons about.
    func testTheHandleTakesSetsAndNothingElse() {
        for steps in [1, 2, 3, 9] {
            for level in 0...EngineConfig.levelMax {
                let full = Engine.generateSession(seeded(level))
                let cut = Engine.generateSession(cutEveryPattern(seeded(level), steps))
                XCTAssertEqual(cut.exercises.map(\.pattern), full.exercises.map(\.pattern),
                    "L\(level) at handle \(steps): the movement list changed")
                for (a, b) in zip(full.exercises, cut.exercises) {
                    XCTAssertEqual(a.tier, b.tier)
                    XCTAssertEqual(a.load, b.load)
                    XCTAssertEqual(a.name, b.name)
                    XCTAssertLessThanOrEqual(b.sets, a.sets,
                        "L\(level): \(b.pattern) gained a set from the handle")
                }
            }
        }
    }
}
