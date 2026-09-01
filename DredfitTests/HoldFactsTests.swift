//
//  The arithmetic of a hands-free hold: the writer the exercise summary needs,
//  the allowance a hold ended by thumb pays, and the bonus tail of the last
//  set. A file of its own beside SetFactsTests, which is about the per-set
//  fact in general and already stands at 521 lines against a 600-line lint.
//
//  Every rule here is a pure function on purpose. A rule stated inside a
//  SwiftUI view is a rule no gating test can reach — CI runs with
//  `-skip-testing:DredfitUITests` — which is how the audit of 27.08.2026
//  found rules that had quietly stopped being true.
//

import XCTest
import DredfitCore
@testable import Dredfit

final class HoldFactsTests: XCTestCase {

    private var session: Session!
    /// The plan of 3×45 seconds.
    private var hold: SessionExercise!
    /// The plan of 3×15 reps — the uneven-plan cases are built off it.
    private var reps: SessionExercise!

    override func setUpWithError() throws {
        try super.setUpWithError()
        var state = EngineState.initial
        for p in Pattern.allCases {
            state.doses[p] = Dose.grid(Library.unit(p, 1)).max
            // A ceiling offers a PROBE (§40.4), which would change what the
            // last set of these exercises even is. "Hard" was said, so the
            // plan is three working sets and nothing else.
            state.lastHard.insert(p)
        }
        // The second session: the rotation puts no hold in session one.
        state.counter = 1
        session = Engine.generateSession(state)
        hold = try XCTUnwrap(session.exercises.first { $0.unit == .hold })
        reps = try XCTUnwrap(session.exercises.first { $0.unit == .reps })
        // Read off the generator rather than assumed: if the plan moves, this
        // fails here instead of silently testing arithmetic about another one.
        XCTAssertEqual([hold.sets, hold.load], [3, 45])
        XCTAssertEqual([reps.sets, reps.load], [3, 15])
        XCTAssertNil(hold.probe)
    }

    // MARK: - Writing one set without truncating the rest

    /// The defect the summary exists to make impossible: correcting set 1
    /// when sets 2 and 3 are already recorded used to delete them, because the
    /// only writer there was `recording`, which truncates by design.
    func testCorrectingAnEarlierSetLeavesTheLaterOnesStanding() {
        var facts = SetFacts.recording(40, in: [:], hold, set: 0)
        facts = SetFacts.recording(38, in: facts, hold, set: 1)
        facts = SetFacts.recording(36, in: facts, hold, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, hold), [40, 38, 36])

        let corrected = SetFacts.recordingSet(50, in: facts, hold, set: 0)
        XCTAssertEqual(SetFacts.allSets(corrected, hold), [50, 38, 36],
                       "the sets after the corrected one are facts, not forecasts")
    }

    /// …and `recording` still truncates, because on the work screen the sets
    /// after the one under way have not happened yet. Both halves in one test:
    /// the pair is the rule.
    func testTheWorkScreenWriterStillTruncates() {
        var facts = SetFacts.recording(40, in: [:], hold, set: 0)
        facts = SetFacts.recording(38, in: facts, hold, set: 1)
        facts = SetFacts.recording(36, in: facts, hold, set: 2)

        let rewritten = SetFacts.recording(50, in: facts, hold, set: 0)
        XCTAssertEqual(rewritten[hold.pattern], [50],
                       "a number entered mid-exercise carries forward; it does "
                        + "not stand beside sets that have not been performed")
    }

    /// Gaps are filled with THIS set's plan. Against the flat base an uneven
    /// plan would be filled with the wrong number on its top set.
    func testGapsBeforeTheCorrectedSetAreFilledWithTheirOwnPlan() throws {
        let uneven = try XCTUnwrap(unevenReps())
        let plan = (0..<uneven.sets).map { uneven.plannedLoad(set: $0) }
        XCTAssertGreaterThan(plan[0], plan[1], "the top set is what makes it uneven")
        let facts = SetFacts.recordingSet(plan[2] - 2, in: [:], uneven, set: 2)
        XCTAssertEqual(SetFacts.allSets(facts, uneven), [plan[0], plan[1], plan[2] - 2],
                       "sets 1 and 2 ran silently, each at its own planned dose")
    }

    /// Everything back on the plan is nothing said at all — the way "put it
    /// back" works, and the reason the entry is dropped rather than stored.
    func testCorrectingEverythingBackOntoThePlanSaysNothing() {
        var facts = SetFacts.recordingSet(40, in: [:], hold, set: 1)
        XCTAssertNotNil(facts[hold.pattern])
        facts = SetFacts.recordingSet(45, in: facts, hold, set: 1)
        XCTAssertNil(facts[hold.pattern],
                     "a record equal to the plan set for set is not a record")
    }

    /// An UNEVEN plan performed exactly as written is also nothing said.
    /// Compared against the flat base, 9-8-8 would read as a shortfall on its
    /// own first set and hand the engine a number nobody reported.
    func testAnUnevenPlanPerformedAsWrittenIsNothingSaid() throws {
        let uneven = try XCTUnwrap(unevenReps())
        var facts = SetFacts.recordingSet(uneven.plannedLoad(set: 0), in: [:], uneven, set: 0)
        facts = SetFacts.recordingSet(uneven.plannedLoad(set: 1), in: facts, uneven, set: 1)
        facts = SetFacts.recordingSet(uneven.plannedLoad(set: 2), in: facts, uneven, set: 2)
        XCTAssertNil(facts[uneven.pattern])
    }

    /// Bounded by the exercise, like `allSets`: an index past the last set
    /// writes nothing rather than growing an array no exercise can have.
    ///
    /// The second half is the summary's own semantics and not an accident:
    /// the sets AFTER the corrected one keep the numbers they ran at, because
    /// on the summary they are already behind. On the work screen the same
    /// entry carries forward instead (`recording`), where the sets ahead have
    /// not happened and the shortfall is a statement about the exercise.
    func testASetOutsideTheExerciseWritesNothing() {
        let facts = SetFacts.recordingSet(40, in: [:], hold, set: 9)
        XCTAssertNil(facts[hold.pattern])
        let negative = SetFacts.recordingSet(40, in: [:], hold, set: -3)
        XCTAssertEqual(SetFacts.allSets(negative, hold), [40, 45, 45],
                       "a negative index is set one, as everywhere else")
    }

    // MARK: - The allowance a thumb pays

    /// The tap lands after the effort has stopped — the person comes off the
    /// floor and reaches for the phone — so a hold ended by tap is written
    /// down, never up.
    func testAHoldEndedByTapPaysTheReachAllowance() {
        XCTAssertEqual(SetFacts.holdEndedByTap(heldSeconds: 48), 45)
        XCTAssertEqual(SetFacts.holdEndedByTap(heldSeconds: 90), 87)
    }

    /// Never below what a hold can be STORED as. The mis-tap grace lets a set
    /// end at four seconds, and the corridor's floor is five.
    func testTheAllowanceNeverFallsThroughTheCorridorFloor() {
        let floor = SetFacts.corridor(for: .hold).lowerBound
        XCTAssertEqual(SetFacts.holdEndedByTap(heldSeconds: 6), floor)
        XCTAssertEqual(SetFacts.holdEndedByTap(heldSeconds: 4), floor)
    }

    // MARK: - The tail of the last set

    /// The plan plus the steps ACTUALLY COMPLETED. A step under way banks
    /// nothing, which is the whole reason the figure on the button cannot be
    /// inflated by the seconds spent reaching for the phone.
    func testOnlyCompletedStepsAreBanked() {
        let plan = 55
        XCTAssertEqual(SetFacts.holdTailBanked(planned: plan, heldSeconds: 55), 55)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: plan, heldSeconds: 59), 55)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: plan, heldSeconds: 60), 60)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: plan, heldSeconds: 64), 60)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: plan, heldSeconds: 70), 70)
    }

    /// The cap: twice the plan, cut by the top of the hold corridor. At a plan
    /// of 55 the corridor bites first, which is why both halves are asserted.
    func testTheTailIsCappedByTwiceThePlanAndByTheCorridor() {
        let ceiling = SetFacts.corridor(for: .hold).upperBound
        XCTAssertEqual(SetFacts.holdTailCap(planned: 55), ceiling)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: 55, heldSeconds: 111), ceiling)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: 55, heldSeconds: 200), ceiling)

        // …and where the plan is short enough, the doubling is what bites.
        XCTAssertEqual(SetFacts.holdTailCap(planned: 20), 40)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: 20, heldSeconds: 300), 40)
    }

    /// A plan already at the top of the corridor has no tail to give: its cap
    /// IS its plan. The flow reads exactly this to decide whether to open one
    /// — a tail that opened and closed on the same tick would record an
    /// estimate for a set the clock measured to the second.
    func testAPlanAtTheCorridorTopHasNoRoomForATail() {
        let ceiling = SetFacts.corridor(for: .hold).upperBound
        XCTAssertEqual(SetFacts.holdTailCap(planned: ceiling), ceiling)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: ceiling,
                                               heldSeconds: ceiling + 30), ceiling)
    }

    /// Nothing under the plan is a tail at all: the tail begins where the
    /// plan is met, and a hold that fell short is an ordinary early stop.
    func testABelowPlanHoldHasNoTail() {
        XCTAssertEqual(SetFacts.holdTailBanked(planned: 45, heldSeconds: 30), 45)
    }

    /// A restored snapshot can carry any number at all, and `planned × 2` is
    /// an Int multiplication that traps on overflow.
    func testNoStoredPlanCanTrapTheCap() {
        XCTAssertEqual(SetFacts.holdTailCap(planned: .max),
                       SetFacts.corridor(for: .hold).upperBound)
        XCTAssertEqual(SetFacts.holdTailCap(planned: .min), 0)
        XCTAssertEqual(SetFacts.holdTailBanked(planned: .max, heldSeconds: .max),
                       SetFacts.corridor(for: .hold).upperBound)
    }

    /// The banked figure never claims the seconds the reach allowance takes
    /// off an ordinary early stop. Both corrections point the same way — down
    /// — and applying both to one number would charge the athlete twice for
    /// one walk to the phone.
    func testTheTailIsNotChargedTheReachAllowanceOnTopOfItsRounding() {
        let banked = SetFacts.holdTailBanked(planned: 45, heldSeconds: 52)
        XCTAssertEqual(banked, 50)
        XCTAssertLessThan(SetFacts.holdEndedByTap(heldSeconds: banked), banked,
                          "the two are different corrections; only one applies")
    }

    // MARK: - Helpers

    /// An uneven plan, built the way the engine builds one: a sub-step is one
    /// rung split across the sets, so the top set stands one above the rest.
    ///
    /// Off a CLEAN state, not this suite's: the sub-step is disabled on the
    /// top rung of a grid (§40.1), which is exactly where `setUp` puts
    /// everything, so an uneven plan cannot be built there at all.
    private func unevenReps() -> SessionExercise? {
        var state = EngineState.initial
        state.counter = 1
        state.sub[reps.pattern] = 1
        let session = Engine.generateSession(state)
        guard let ex = session.exercises.first(where: { $0.pattern == reps.pattern }),
              let loads = ex.loads, Set(loads).count > 1 else { return nil }
        return ex
    }
}
