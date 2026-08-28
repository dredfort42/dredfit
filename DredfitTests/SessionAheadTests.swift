//
//  The number on the work screen.
//
//  The plan announces how long the workout takes; the decision about its
//  length is taken inside the workout now, so the number has to follow the
//  decision rather than the plan. What is asserted here is that it is the SAME
//  number: the engine's own arithmetic over a shorter list, never an app-side
//  estimate that would drift from the line on Today by an amount nobody could
//  account for.
//

import XCTest
import DredfitCore
@testable import Dredfit

final class SessionAheadTests: XCTestCase {

    /// A plan with every movement `variation` rungs up its ladder, at the dose
    /// ceiling — the long end of the scale, where "how much is left" matters.
    private func session(variation: Int) -> Session {
        var state = EngineState.initial
        for pattern in Pattern.allCases {
            let v = min(variation, Library.count(pattern))
            state.vars[pattern] = v
            state.doses[pattern] = Dose.grid(Library.unit(pattern, v)).max
            // A journal, so the ceiling does not turn into a probe on every
            // movement and change what "the sets left" even means here.
            state.lastHard.insert(pattern)
        }
        return Engine.generateSession(state)
    }

    /// Standing at the first set of the first exercise, everything is ahead —
    /// so the number is the announced duration itself, minus the warm-up
    /// already behind.
    func testAtTheStartWhatIsLeftIsTheWholeWorkout() {
        for variation in [1, 2, 3, 4] {
            let plan = session(variation: variation)
            let ahead = SessionAhead.minutes(plan.exercises, exIndex: 0, setsBehind: 0,
                                             ends: plan.warmupMin + plan.cooldownMin)
            XCTAssertEqual(ahead, Int(plan.estimatedTotalMin.rounded()),
                           "variation \(variation): the live number disagrees with the announced one")
        }
    }

    /// And it only ever goes down as the session is walked — set by set,
    /// exercise by exercise.
    func testItFallsWithEverySetBehind() {
        let plan = session(variation: 4)
        var previous = Int.max
        for exIndex in plan.exercises.indices {
            for behind in 0...plan.exercises[exIndex].sets {
                let now = SessionAhead.minutes(plan.exercises, exIndex: exIndex,
                                               setsBehind: behind,
                                               ends: plan.cooldownMin)
                XCTAssertLessThanOrEqual(now, previous,
                                         "exercise \(exIndex), \(behind) behind: time went UP")
                previous = now
            }
        }
    }

    /// The sets left are the LAST ones of the plan. On an uneven plan — 9-8-8
    /// — the person who has done the 9 has two 8s ahead of them, and a list
    /// built from the first sets instead would over-count the work left.
    func testTheSetsLeftAreTheOnesStillToCome() throws {
        let uneven = SessionExercise(pattern: .squat, name: "Squat", variation: 1, unit: .reps,
                                     load: 8, perSide: false, sets: 3,
                                     restSetSec: 60, restExerciseSec: 90, loads: [9, 8, 8],
                                     probe: nil)
        let ahead = try XCTUnwrap(
            SessionAhead.remaining([uneven], exIndex: 0, setsBehind: 1).first)
        XCTAssertEqual(ahead.sets, 2)
        XCTAssertEqual([ahead.plannedLoad(set: 0), ahead.plannedLoad(set: 1)], [8, 8],
                       "the sub-step was counted again after it was performed")
    }

    /// A skipped set is a set behind: the minutes come off at the moment of
    /// the tap, which is the whole promise of a number that recalculates.
    func testASkippedSetTakesItsMinutesOffImmediately() throws {
        let plan = session(variation: 4)
        let full = SessionAhead.minutes(plan.exercises, exIndex: 0, setsBehind: 0,
                                        ends: plan.cooldownMin)
        let afterSkip = SessionAhead.minutes(plan.exercises, exIndex: 0, setsBehind: 1,
                                             ends: plan.cooldownMin)
        XCTAssertLessThan(afterSkip, full, "a skipped set bought no time at all")
    }

    /// Past the last exercise there is nothing left but the blocks that are
    /// still to come — and past those, nothing.
    func testPastTheEndOnlyTheBlocksAreLeft() {
        let plan = session(variation: 3)
        let past = plan.exercises.count
        XCTAssertTrue(SessionAhead.remaining(plan.exercises, exIndex: past, setsBehind: 0).isEmpty)
        XCTAssertEqual(SessionAhead.minutes(plan.exercises, exIndex: past, setsBehind: 0,
                                            ends: plan.cooldownMin),
                       plan.cooldownMin)
        XCTAssertEqual(SessionAhead.minutes(plan.exercises, exIndex: past, setsBehind: 0, ends: 0), 0)
    }

    /// Indices off the end of the list, a negative count of sets behind, a
    /// negative block: this is read on every body pass of a live screen, so it
    /// answers rather than traps.
    func testItSurvivesNonsense() {
        let plan = session(variation: 3)
        XCTAssertTrue(SessionAhead.remaining(plan.exercises, exIndex: -1, setsBehind: 0).isEmpty)
        XCTAssertTrue(SessionAhead.remaining([], exIndex: 0, setsBehind: 0).isEmpty)
        XCTAssertEqual(SessionAhead.remaining(plan.exercises, exIndex: 0, setsBehind: -5).first?.sets,
                       plan.exercises[0].sets, "a negative count of sets behind added work")
        XCTAssertGreaterThanOrEqual(
            SessionAhead.minutes(plan.exercises, exIndex: 0, setsBehind: 99, ends: -10), 0)
    }
}
