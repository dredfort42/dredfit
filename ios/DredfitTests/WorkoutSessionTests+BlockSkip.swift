import XCTest
import DredfitCore
@testable import Dredfit

/// The question a block's escape asks (`skipQuestion(for:)`), driven the way
/// the alert drives it: the block stands still while it is up, "Keep going"
/// gives the clock back, and "Skip" ends it without billing the wait as
/// stretching.
extension WorkoutSessionTests {

    /// A cool-down on its first position, past the count-in.
    private func cooldownRunning() -> WorkoutSession {
        let flow = makeFlow(makeStore())
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        run(flow, until: { flow.cooldown.stage != .getReady })
        return flow
    }

    /// A stray tap answered minutes later finds the stretch where it was, and
    /// "Keep going" picks it up from the same second.
    func testTheBlockStandsStillWhileItsSkipIsAsked() throws {
        let flow = cooldownRunning()
        run(flow, for: 3)
        let index = flow.cooldown.index
        let stage = flow.cooldown.stage
        let remaining = flow.cooldown.clock.remaining

        let question = try XCTUnwrap(flow.skipQuestion(for: .cooldown))   // the question goes up
        // A minute of ticks with the app in front, as the view's timer runs
        // them: one jump would read as an absence and pause the block on its
        // own, hiding a question that froze nothing.
        run(flow, for: 60)
        XCTAssertEqual(flow.cooldown.index, index, "the block moved on behind the question")
        XCTAssertEqual(flow.cooldown.stage, stage)
        XCTAssertEqual(flow.cooldown.clock.remaining, remaining)

        question.cancel()                                  // "Keep going"
        XCTAssertEqual(flow.phase, .cooldown)
        XCTAssertEqual(flow.cooldown.clock.remaining, remaining,
                       "saying no must hand back the second the question froze")
        // …and the clock runs again: a block left frozen after "Keep going"
        // would show the same second forever.
        run(flow, for: 1)
        XCTAssertEqual(flow.cooldown.clock.remaining, remaining - 1,
                       "the stretch did not resume after the question")
    }

    /// "Skip" ends the block, and the minutes the question stood up are not
    /// stretching: the energy Health is told about reads this figure.
    func testTheSecondsTheQuestionStoodAreNotBilledAsStretching() throws {
        let flow = cooldownRunning()
        run(flow, for: 10)
        let question = try XCTUnwrap(flow.skipQuestion(for: .cooldown))   // the question goes up
        clock += 300
        question.perform()                                 // "Skip"
        XCTAssertEqual(flow.phase, .feedback)
        let billed = try XCTUnwrap(flow.cooldownSec)
        XCTAssertLessThan(billed, 60, "the \(billed) s billed include the question's 300")
    }

    /// A tap on the escape of a block that ended in the same instant asks
    /// nothing: no question over the rating, and nothing frozen behind it.
    func testABlockThatHasEndedAsksNothing() {
        let flow = cooldownRunning()
        flow.finish(.cooldown)
        XCTAssertNil(flow.skipQuestion(for: .cooldown))
        XCTAssertNil(flow.blockFrozenAt, "a question that was never asked froze the block")
        XCTAssertNil(flow.skipQuestion(for: .warmup), "the warm-up is long over")
    }
}
