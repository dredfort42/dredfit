import XCTest
import DredfitCore
@testable import Dredfit

/// The cool-down as the flow runs it: a side switched on the spot, and the
/// block picking up where the athlete is when the sheet changes it.
extension WorkoutSessionTests {

    /// The warm-up declined and the last set of the last exercise done: the
    /// flow on the first position of its cool-down.
    private func inCooldown(_ store: AppStore) -> WorkoutSession {
        let flow = makeFlow(store)
        flow.declineWarmup()
        flow.exIndex = flow.exercises.count - 1
        flow.setIndex = 2
        flow.completeSet()
        flow.beginCooldown()
        return flow
    }

    /// The warm-up circle's rule, for a side: the halfway boundary of a stretch
    /// switched on the spot is the switch tone with the clock running — no
    /// pause, and no go in the middle of a hold that never stopped.
    func testASideSwitchedOnTheSpotRunsOnTheSwitchTone() throws {
        let flow = inCooldown(makeStore())
        let spot = try XCTUnwrap(flow.cooldownPositions.firstIndex { $0.halves == .sidesOnTheSpot })
        run(flow, until: { flow.cooldown.index == spot && flow.cooldown.stage == .firstHalf }, limit: 1_000)
        run(flow, until: { flow.cooldown.clock.remaining == WorkoutSession.countdownSignalSeconds + 1 })
        signals.events.removeAll()

        var paused = false
        run(flow, until: {
            if flow.cooldown.stage == .switchPause { paused = true }
            return flow.cooldown.stage == .secondHalf
        })
        XCTAssertFalse(paused, "a switch on the spot must not stop the clock")
        XCTAssertEqual(flow.cooldown.index, spot, "the second side belongs to the same position")
        XCTAssertEqual(flow.cooldown.clock.remaining, Cooldown.sideSeconds)
        XCTAssertEqual(signals.tones, [.tick, .tick, .tick, .switchSides])
        XCTAssertTrue(signals.events.contains(.announce(SplitStageWords(halves: .sidesOnTheSpot).switching)),
                      "the switch is spoken in the words of a side")
    }

    /// The rebase as the sheet sets it off, through the store and the flow:
    /// kneeling in the side reach with the standing lunge behind them, the
    /// athlete brings the kneeling lunge back. The block carries on where they
    /// kneel — the lunge already done stands for this workout.
    func testBringingTheKneelingLungeBackMidBlockKeepsTheAthleteDown() {
        let store = makeStore()
        store.setBlockMoveHidden("hip-flexors", true)
        let flow = inCooldown(store)
        XCTAssertEqual(flow.cooldownPositions.map(\.id),
                       ["chest-opener", "half-fold", "standing-hip-flexors",
                        "child-side-reach", "lying-figure-four", "lying-twist"],
                       "the composition this was measured on")
        run(flow, until: { flow.cooldown.index == 3 }, limit: 1_000)

        store.setBlockMoveHidden("hip-flexors", false)
        flow.rebaseCooldownOnComposition()
        XCTAssertEqual(flow.cooldown.index, 3)
        XCTAssertEqual(flow.cooldownPositions[flow.cooldown.index].id, "child-side-reach")
        XCTAssertEqual(flow.cooldown.stage, .getReady, "the slot restarts on its own transition")
    }
}
