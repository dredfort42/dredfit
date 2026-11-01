import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class CooldownTests: XCTestCase {

    /// Every position of the pool of ten, surfaced by setting each one aside in
    /// turn over the rotation: the fallbacks only appear when their zone's
    /// first choice is gone.
    private var wholePool: [CooldownPosition] {
        var seen: [CooldownPosition] = []
        let first = Cooldown.positions(sessionNumber: 1)
        let asides = [Set<String>()] + first.map { [$0.id] }
        for hidden in asides {
            for session in 1...Cooldown.rotationPeriod {
                for position in Cooldown.positions(sessionNumber: session, hiding: hidden)
                where !seen.contains(where: { $0.id == position.id }) {
                    var plain = position
                    plain.needsSetup = false
                    seen.append(plain)
                }
            }
        }
        return seen
    }

    func testThePoolIsTen() {
        XCTAssertEqual(Set(wholePool.map(\.id)).count, 10)
    }

    /// The same six zones in every session, standing first and lying last.
    func testSixPositionsOneZoneEachFromStandingToLying() {
        XCTAssertEqual(Cooldown.positions(sessionNumber: 1).map(\.id),
                       ["chest-opener", "half-fold", "hip-flexors",
                        "child-side-reach", "lying-figure-four", "lying-twist"])
        XCTAssertEqual(Cooldown.positions(sessionNumber: 2).map(\.id),
                       ["wrists", "half-fold", "hip-flexors",
                        "rest-pose", "lying-figure-four", "lying-twist"],
                       "two zones alternate their variant from session to session")
        XCTAssertEqual(Cooldown.rotationPeriod, 2)
        XCTAssertEqual(Cooldown.positions(sessionNumber: 3), Cooldown.positions(sessionNumber: 1))
    }

    func testCompositionIsDeterministic() {
        let first = Cooldown.positions(sessionNumber: 7, hiding: ["half-fold"])
        for _ in 0..<5 {
            XCTAssertEqual(Cooldown.positions(sessionNumber: 7, hiding: ["half-fold"]), first)
        }
    }

    /// The point of the block's order: one trip down, and nobody gets up
    /// again — whatever is set aside, because a refilled zone is put back on
    /// its own level rather than where the gap was.
    func testTheBlockOnlyEverGoesDownAndPaysForOneDescent() {
        let ids = wholePool.map(\.id)
        for hidden in hiddenSets(of: ids) {
            for session in 1...Cooldown.rotationPeriod {
                let block = Cooldown.positions(sessionNumber: session, hiding: hidden)
                let named = "session \(session), set aside \(hidden.sorted())"
                XCTAssertEqual(block.count, Cooldown.positionCount, named)
                let levels = block.map(\.level)
                XCTAssertEqual(levels, levels.sorted(), "\(named): the block climbs back up")
                XCTAssertEqual(block.filter(\.needsSetup).count, 1, "\(named): one descent, one supplement")
                XCTAssertEqual(block.first(where: \.needsSetup)?.id,
                               block.first(where: { $0.level > .standing })?.id,
                               "\(named): the supplement belongs to the trip down")
            }
        }
    }

    /// A zone set aside entirely is refilled from its own level: the finishing
    /// twist gives its slot to another position lying down, not to one that
    /// would put the person back on their feet.
    func testAnEmptiedZoneIsRefilledFromItsOwnLevel() {
        XCTAssertEqual(Cooldown.positions(sessionNumber: 1, hiding: ["lying-twist"]).last?.id,
                       "knees-to-chest")
        XCTAssertEqual(Cooldown.positions(sessionNumber: 1, hiding: ["hip-flexors"])
                        .first(where: { $0.id.contains("hip-flexors") })?.id,
                       "standing-hip-flexors",
                       "someone who cannot kneel still gets the hip flexors, standing")
    }

    /// The standing lunge is the kneeling one for somebody who cannot kneel,
    /// not a stretch of its own: drawn to refill another zone, it would give
    /// the block the hip flexors twice, and a second switch pause.
    func testTheStandingLungeOnlyEverStandsInForTheKneelingOne() {
        for hidden in hiddenSets(of: wholePool.map(\.id)) {
            for session in 1...Cooldown.rotationPeriod {
                let ids = Cooldown.positions(sessionNumber: session, hiding: hidden).map(\.id)
                XCTAssertEqual(ids.contains("standing-hip-flexors"),
                               hidden.contains("hip-flexors") && !hidden.contains("standing-hip-flexors"),
                               "session \(session), set aside \(hidden.sorted())")
            }
        }
    }

    /// A list longer than the cap — a hand-edited state file — is honoured only
    /// as far as the block stays six. The standing lunge refills no other zone,
    /// so it is not spare: with four set aside and the kneeling lunge still
    /// drawn, honouring the fourth would leave five.
    func testAListPastTheCapStillComposesSix() {
        let hidden: Set<String> = ["chest-opener", "wrists", "half-fold", "rest-pose"]
        for session in 1...Cooldown.rotationPeriod {
            XCTAssertEqual(Cooldown.positions(sessionNumber: session, hiding: hidden).count,
                           Cooldown.positionCount, "session \(session)")
        }
    }

    /// The holds alone — 6 × 30 s = 3 min — do not fill the reserved minutes:
    /// the reserve also pays for the transitions and the switch pauses that
    /// carry them. The whole-block counterpart lives in BlockReserveTests,
    /// where both blocks are counted together.
    func testTheHoldsAloneDoNotFillTheReserve() {
        let holds = Cooldown.positionCount * Cooldown.positionSeconds
        XCTAssertEqual(holds, 180, "six positions of thirty seconds")
        XCTAssertLessThan(holds, EngineConfig.cooldownMin * 60,
                          "the reserve carries the transitions as well")
    }

    func testAPerSidePositionSplitsIntoTwoWholeSidesPlusThePause() {
        // 15 + 15, and 15 + 4 + 15 where the switch is a re-set (issue #35):
        // the slot splits into two equal whole sides, and the pause is the
        // app-layer constant shared with the workout's per-side holds.
        XCTAssertEqual(Cooldown.sideSeconds * 2, Cooldown.positionSeconds,
                       "the sides must consume the whole slot")
        XCTAssertEqual(Cooldown.sideSeconds, 15)
        XCTAssertEqual(Cooldown.sideSwitchPauseSec, 4)   // on trial
    }

    // MARK: - The stage machine (issue #35)

    /// Session one: chest opener, half fold, hip flexors (a re-set between
    /// sides), the side reach, the figure-four and the twist (switched on the
    /// spot) — every kind of position the block has.
    private var machinePositions: [CooldownPosition] {
        Cooldown.positions(sessionNumber: 1)
    }

    private func index(of id: String) throws -> Int {
        try XCTUnwrap(machinePositions.firstIndex { $0.id == id }, "\(id) is not in session one")
    }

    func testASideReSetWalksTheSidesAroundThePause() throws {
        let positions = machinePositions
        let lunge = try index(of: "hip-flexors")
        XCTAssertEqual(GuidedBlock.step(after: (lunge, .getReady), positions: positions)?.stage,
                       .firstHalf)
        XCTAssertEqual(GuidedBlock.step(after: (lunge, .firstHalf), positions: positions)?.stage,
                       .switchPause, "changing the front leg of a kneeling lunge is a re-set")
        XCTAssertEqual(GuidedBlock.step(after: (lunge, .switchPause), positions: positions)?.stage,
                       .secondHalf)
        let next = GuidedBlock.step(after: (lunge, .secondHalf), positions: positions)
        XCTAssertEqual(next?.index, lunge + 1)
        XCTAssertEqual(next?.stage, .getReady)
    }

    /// The warm-up's rule for its circles, here for sides: where the body
    /// stays put, the second side starts on the tone with the clock running.
    func testASwitchOnTheSpotRunsNoPause() throws {
        let positions = machinePositions
        for id in ["child-side-reach", "lying-figure-four", "lying-twist"] {
            let at = try index(of: id)
            XCTAssertEqual(GuidedBlock.step(after: (at, .firstHalf), positions: positions)?.stage,
                           .secondHalf, "\(id): a switch on the spot must not stop the clock")
            XCTAssertEqual(Cooldown.slotSeconds(of: positions[at]), Cooldown.positionSeconds)
        }
        XCTAssertEqual(Cooldown.slotSeconds(of: positions[try index(of: "hip-flexors")]),
                       Cooldown.positionSeconds + Cooldown.sideSwitchPauseSec)
    }

    func testTheBlockEndsAfterTheFarSideOfTheTwist() {
        let positions = machinePositions
        XCTAssertNil(GuidedBlock.step(after: (positions.count - 1, .secondHalf), positions: positions))
    }

    func testAdvanceNamesThePauseItEnters() throws {
        // The boundary crossed right now decides the signal: the first
        // side's end enters the pause (the falling switch tone), the
        // pause's end enters the second side (the usual go).
        let positions = machinePositions
        let lunge = try index(of: "hip-flexors")
        let intoPause = GuidedBlock.cooldown.advance(from: (lunge, .firstHalf), overshoot: 0,
                                                     positions: positions)
        XCTAssertEqual(intoPause?.entered, .switchPause)
        XCTAssertEqual(intoPause?.remaining, Cooldown.sideSwitchPauseSec)
        let intoSecond = GuidedBlock.cooldown.advance(from: (lunge, .switchPause), overshoot: 0,
                                                      positions: positions)
        XCTAssertEqual(intoSecond?.entered, .secondHalf)
        XCTAssertEqual(intoSecond?.remaining, Cooldown.sideSeconds)
    }

    func testAdvanceAbsorbsBackgroundedTimeAcrossStages() throws {
        // 22 s past the first side's end: the pause (4) and the second side
        // (15) are consumed whole, landing 3 s into the next position — which
        // opens with its transition (#52), the plain one: the trip down was
        // paid on the way into the lunge.
        let positions = machinePositions
        let lunge = try index(of: "hip-flexors")
        let landing = GuidedBlock.cooldown.advance(from: (lunge, .firstHalf), overshoot: 22,
                                                   positions: positions)
        XCTAssertEqual(landing?.index, lunge + 1)
        XCTAssertEqual(landing?.stage, .getReady)
        XCTAssertEqual(landing?.remaining, GetReady.seconds - 3)
        // An overshoot past the whole block is simply over.
        XCTAssertNil(GuidedBlock.cooldown.advance(from: (lunge, .firstHalf), overshoot: 10_000,
                                                  positions: positions))
    }

    /// The halves decide whether the app counts the sides itself and whether
    /// the clock stops between them, so they have to agree with the
    /// position's own instructions (I-10): a re-set only where the base of the
    /// body changes.
    func testTheHalvesAgreeWithWhatTheBodyDoes() {
        let reSet: Set<String> = ["hip-flexors", "standing-hip-flexors"]
        let onTheSpot: Set<String> = ["wrists", "child-side-reach", "lying-figure-four", "lying-twist"]
        for position in wholePool {
            switch position.halves {
            case .sides:          XCTAssertTrue(reSet.contains(position.id), position.id)
            case .sidesOnTheSpot: XCTAssertTrue(onTheSpot.contains(position.id), position.id)
            case .directions:     XCTFail("\(position.id): no stretch of the pool reverses")
            case nil:             XCTAssertFalse(reSet.union(onTheSpot).contains(position.id), position.id)
            }
        }
    }

    func testNoPositionTellsTheUserToSwapSidesItself() {
        for position in wholePool {
            for step in position.steps {
                XCTAssertNil(step.range(of: "swap", options: .caseInsensitive),
                             "\(position.id): the app counts the sides itself — "
                               + "a step must not ask the user to swap them")
                XCTAssertNil(step.range(of: "wall", options: .caseInsensitive),
                             "\(position.id): the block needs no wall")
            }
        }
    }

    // MARK: - Where a recomposed block picks up

    /// Session one with the kneeling lunge set aside stands through [chest
    /// opener, half fold, standing lunge]; setting the standing lunge aside too
    /// on slot 2 empties the hip flexors' zone, and its refill is the wrists —
    /// standing, so they sort in at slot 1, above the slot on screen, and the
    /// half fold slides to 2. A clamped ordinal would name the half fold —
    /// already done.
    func testHidingThePositionOnScreenNeverReopensOneAlreadyDone() throws {
        let before = Cooldown.positions(sessionNumber: 1, hiding: ["hip-flexors"])
        XCTAssertEqual(before.map(\.id), ["chest-opener", "half-fold", "standing-hip-flexors",
                                          "child-side-reach", "lying-figure-four", "lying-twist"],
                       "the composition this was measured on")
        let after = Cooldown.positions(sessionNumber: 1, hiding: ["hip-flexors", "standing-hip-flexors"])
        let passed = Set(before.prefix(2).map(\.id))
        XCTAssertTrue(passed.contains(after[2].id),
                      "the ordinal the clamp kept names a position already done")
        let landing = try XCTUnwrap(WorkoutSession.cooldownLanding(in: after, after: passed,
                                                                   reached: before[2].level))
        XCTAssertEqual(after[landing].id, "child-side-reach")
    }

    /// The one the athlete cannot even see coming: "Bring back" does not
    /// dismiss the technique sheet. Session one with both standing upper-body
    /// stretches set aside is [half fold, kneeling lunge, side reach, rest
    /// pose, figure-four, twist]; restoring the wrists on slot 1 puts them
    /// back at the top, where standing positions go, and pushes everything
    /// after them one slot right, so a clamped ordinal would name the half
    /// fold — already done.
    func testBringingAPositionBackNeverReopensOneAlreadyDone() throws {
        let before = Cooldown.positions(sessionNumber: 1, hiding: ["chest-opener", "wrists"])
        XCTAssertEqual(before.map(\.id), ["half-fold", "hip-flexors", "child-side-reach",
                                          "rest-pose", "lying-figure-four", "lying-twist"],
                       "the composition this was measured on")
        let after = Cooldown.positions(sessionNumber: 1, hiding: ["chest-opener"])
        let passed = Set(before.prefix(1).map(\.id))
        XCTAssertTrue(passed.contains(after[1].id),
                      "the ordinal the clamp kept names a position already done")
        let landing = try XCTUnwrap(WorkoutSession.cooldownLanding(in: after, after: passed,
                                                                   reached: before[1].level))
        XCTAssertEqual(after[landing].id, "hip-flexors")
    }

    /// Bringing a zone's first choice back drops the stand-in that ran in its
    /// place. Session one with the kneeling lunge set aside: kneeling in the
    /// side reach, the standing lunge behind them, the athlete brings the
    /// kneeling lunge back. Measured from the ids alone the block would land
    /// on it — up onto one knee, the hip flexors twice, seven positions.
    func testBringingBackAPositionAboveTheAthleteWaitsForTheNextWorkout() throws {
        let before = Cooldown.positions(sessionNumber: 1, hiding: ["hip-flexors"])
        let after = Cooldown.positions(sessionNumber: 1)
        let passed = Set(before.prefix(3).map(\.id))
        XCTAssertEqual(before[3].id, "child-side-reach", "the composition this was measured on")
        let landing = try XCTUnwrap(WorkoutSession.cooldownLanding(in: after, after: passed,
                                                                   reached: before[3].level))
        XCTAssertEqual(after[landing].id, "child-side-reach",
                       "the block carries on where the athlete kneels")
    }

    /// Every change the sheet can make, at every slot of every composition the
    /// app can draw: set the position on screen aside while the cap allows, or
    /// bring back any one already aside. The block that then runs — what is
    /// behind the athlete, and the new list from the landing on — never gets
    /// them up, never runs a position twice, never holds both lunges and never
    /// runs more than six. "Up" is measured from the position on screen as
    /// well: it is not in either half of the run, and a landing above it reads
    /// as a block that only goes down.
    func testNoChangeMidBlockGetsTheAthleteUpOrLengthensTheBlock() {
        for hidden in hiddenSets(of: wholePool.map(\.id)) {
            for session in 1...Cooldown.rotationPeriod {
                let before = Cooldown.positions(sessionNumber: session, hiding: hidden)
                for slot in before.indices {
                    var changes = hidden.map { hidden.subtracting([$0]) }
                    if hidden.count < AppStore.maxHiddenBlockMoves {
                        changes.append(hidden.union([before[slot].id]))
                    }
                    for change in changes {
                        let after = Cooldown.positions(sessionNumber: session, hiding: change)
                        let behind = Array(before.prefix(slot))
                        let landing = WorkoutSession.cooldownLanding(
                            in: after, after: Set(behind.map(\.id)), reached: before[slot].level)
                        let run = behind + (landing.map { Array(after[$0...]) } ?? [])
                        let named = "session \(session), set aside \(hidden.sorted()), "
                            + "slot \(slot), then \(change.sorted())"
                        let levels = run.map(\.level)
                        XCTAssertEqual(levels, levels.sorted(), "\(named): the athlete gets up again")
                        if let landing {
                            XCTAssertGreaterThanOrEqual(after[landing].level, before[slot].level,
                                                        "\(named): sent up from the position on screen")
                        }
                        XCTAssertEqual(Set(run.map(\.id)).count, run.count, "\(named): a position runs twice")
                        XCTAssertFalse(run.contains { $0.id == "hip-flexors" }
                                         && run.contains { $0.id == "standing-hip-flexors" },
                                       "\(named): both lunges")
                        XCTAssertLessThanOrEqual(run.count, Cooldown.positionCount,
                                                 "\(named): the block runs longer than it promised")
                    }
                }
            }
        }
    }

    private func hiddenSets(of ids: [String]) -> [Set<String>] {
        var out: [Set<String>] = [[]]
        for size in 1...AppStore.maxHiddenBlockMoves {
            out += combinations(ids, size)
        }
        return out
    }

    private func combinations(_ ids: [String], _ size: Int) -> [Set<String>] {
        guard size > 0 else { return [[]] }
        guard ids.count >= size else { return [] }
        var out: [Set<String>] = []
        for (offset, id) in ids.enumerated() {
            for rest in combinations(Array(ids[(offset + 1)...]), size - 1) {
                out.append(rest.union([id]))
            }
        }
        return out
    }
}
