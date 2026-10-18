import XCTest
import DredfitCore
@testable import Dredfit

/// The standing warm-up as the flow runs it: a circle that reverses on a tone
/// with the clock running, and a last move that follows the session.
extension WorkoutSessionTests {

    /// The halfway boundary of a circle is the switch itself: no pause opens,
    /// the first half's 3-2-1 lands on the SWITCH tone rather than on a go, and
    /// the second half starts with its whole fifteen seconds. A go there would
    /// read as a second start in the middle of a movement that never stopped;
    /// a pause would stop it for nothing.
    func testACircleReversesOnTheSwitchToneWithTheClockRunning() throws {
        let flow = makeFlow(makeStore())
        flow.beginWarmup()
        run(flow, until: { flow.warmup.stage == .firstHalf })
        let index = flow.warmup.index
        XCTAssertTrue(flow.warmupMove.reverses, "the premise: the first split move is a circle")
        run(flow, until: { flow.warmup.clock.remaining == WorkoutSession.countdownSignalSeconds + 1 })
        signals.events.removeAll()

        var paused = false
        run(flow, until: {
            if flow.warmup.stage == .switchPause { paused = true }
            return flow.warmup.stage == .secondHalf
        })
        XCTAssertFalse(paused, "a circle reverses on the move: no switch pause")
        XCTAssertEqual(flow.warmup.index, index, "the second half belongs to the same move")
        XCTAssertEqual(flow.warmup.clock.remaining, Warmup.halfSeconds)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .switchSides])
        XCTAssertTrue(signals.events.contains(.announce(SplitStageWords(halves: .directions).switching)),
                      "the switch is spoken in the words of a direction, not of a side")
    }

    /// The block's one specific part: its last move prepares the first
    /// exercise of THIS session. Asked through the flow, because the wiring —
    /// which session, which exercise — is what this pins; the mapping itself
    /// is `BlockReserveTests`'.
    ///
    /// A session that opens on a HINGE, not the fresh install's squat: squat
    /// and lunge share a lead-in, and a session opening on a squat could not
    /// tell the first exercise from the last, or from a squat hard-coded.
    func testTheWarmupEndsOnTheLeadInOfTheFirstExercise() throws {
        var state = EngineState.initial
        // The rotation's start is `counter × 3 mod 8`; 6 puts it on the hinge,
        // which `Pattern.ordered` then lists before the pull.
        state.counter = 6
        let flow = makeFlow(makeStore(), session: Engine.generateSession(state))
        XCTAssertEqual(flow.session.exercises.first?.pattern, .hinge, "the premise")
        XCTAssertNotEqual(flow.session.exercises.last?.pattern, .hinge, "the premise")
        XCTAssertEqual(flow.warmupMoves.last?.id, "hip-hinges")
    }
}
