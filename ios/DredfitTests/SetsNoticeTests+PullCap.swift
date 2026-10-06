//
//  The push rows under the pull slot's cap. A push never shows more sets than
//  the weaker pull branch stands on, so its set count moves with the pulls —
//  down when a pull set is skipped, up when it comes back — while its own
//  position stands still. Both directions are announced on the push row: the
//  person did nothing to the push, and a row that changed by itself reads as a
//  bug. An extension rather than more of `SetsNoticeTests`, for the same
//  reason as `SetsNoticeTests+Credit`.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
extension SetsNoticeTests {

    /// Rows 3×8 and push-ups 3×10, doses well under the ceiling so no probe
    /// takes a set. Workout 1 carries both pushes, workout 2 the vertical
    /// one, workout 3 the horizontal one — the pull slot is in all of them,
    /// on the bar every other workout once the bar is on.
    private func pushStore(bar: Bool = false,
                           change: (inout EngineState) -> Void = { _ in }) throws -> AppStore {
        var seed = EngineState.initial
        seed.hasBar = bar
        seed.vars[.pull] = 4
        seed.doses[.pull] = 8
        seed.shown[.pull] = [4: 8]
        if bar {
            seed.vars[.pullBar] = 4
            seed.doses[.pullBar] = 5
            seed.shown[.pullBar] = [4: 5]
        }
        seed.vars[.pushH] = 3
        seed.doses[.pushH] = 10
        seed.shown[.pushH] = [3: 10]
        seed.vars[.pushV] = 3
        seed.doses[.pushV] = 8
        seed.shown[.pushV] = [3: 8]
        change(&seed)
        try JSONEncoder().encode(AppData(engineState: seed, records: [], settings: AppSettings()))
            .write(to: tempURL)
        let store = makeStore()
        XCTAssertEqual(store.engineState, seed,
                       "the seed did not load — everything below would be about a clean start")
        return store
    }

    private func pushH(_ session: Session) throws -> SessionExercise {
        try XCTUnwrap(session.exercises.first { $0.pattern == .pushH },
                      "this workout must carry the horizontal push — the rotation moved")
    }

    /// Workouts 1 and 2 trained, the second with one pull set skipped: the
    /// plan ahead is workout 3, whose push-ups the pull's two sets now cap.
    private func pushHeldBack(bar: Bool = false) throws -> AppStore {
        let store = try pushStore(bar: bar)
        train(store)
        train(store, setsSkipped: [bar ? .pullBar : .pull: 1])
        return store
    }

    // MARK: - Down

    /// The pull lost a set, so the push-ups show one set fewer than last time
    /// though nothing about them changed.
    func testAPushThePullsHoldBackSaysSo() throws {
        let store = try pushHeldBack()
        let row = try pushH(store.nextSession)
        XCTAssertEqual(row.sets, 2, "the pull's skipped set must cap the push — there is no drop to explain")
        XCTAssertTrue(store.setsJustHeldBackByThePulls(in: row),
                      "a push the pulls held back lost a set without a word")
        XCTAssertFalse(store.aSetJustCameBack(in: row))
    }

    /// With the bar on, the cap is the WEAKER branch, and that is usually the
    /// one not in today's plan: the bar lost a set, the next session trains
    /// the row — whose three sets stand untouched — and the push-ups still
    /// show two. The line has to come from the cap, not from a pull on screen.
    func testThePullBranchNotOnScreenCanHoldThePushBack() throws {
        let store = try pushHeldBack(bar: true)
        let plan = store.nextSession
        XCTAssertEqual(plan.exercises.map(\.pattern).filter { Pattern.pullSide.contains($0) }, [.pull],
                       "today's pull slot must be the row — the branch that lost the set sits it out")
        XCTAssertEqual(try XCTUnwrap(plan.exercises.first { $0.pattern == .pull }).sets, 3,
                       "the row on screen must stand on all its sets")
        let row = try pushH(plan)
        XCTAssertEqual(row.sets, 2, "the bar's two sets must cap the push")
        XCTAssertTrue(store.setsJustHeldBackByThePulls(in: row),
                      "the cap of a branch that is not on screen reached the push row without a word")
    }

    /// The push's own set was skipped, and then a pull set: both stand on two
    /// sets, so the cap binds at exactly the push's own count and takes
    /// nothing. The drop is the one the person made, and the row must not put
    /// it down to the pulls.
    func testAPushThatLostItsOwnSetSaysNothingAboutThePulls() throws {
        let store = try pushStore()
        train(store, setsSkipped: [.pushH: 1])
        train(store, setsSkipped: [.pull: 1])
        let row = try pushH(store.nextSession)
        XCTAssertEqual(row.sets, 2, "the push's own skipped set must still be off")
        let gate = try XCTUnwrap(Engine.pullCap(on: .pushH, in: store.engineState))
        XCTAssertEqual(gate.own, 2, "the push stands on two sets of its own")
        XCTAssertEqual(gate.cap, 2, "and the pulls cap it at the same two")
        XCTAssertFalse(store.setsJustHeldBackByThePulls(in: row),
                       "a set the push itself lost must not be put down to the pulls")
        XCTAssertFalse(store.aSetJustCameBack(in: row))
    }

    /// The pull starts a set short and sits workout 1 out whole, so its set
    /// stays off: workout 2's vertical push is held back just as workout 1's
    /// was.
    private func pullSitsOut() throws -> AppStore {
        let store = try pushStore { $0.cut[.pull] = 1 }
        skipThePullWhole(store, workouts: 1)
        XCTAssertEqual(store.engineState.cutOf(.pull), 1, "a pull skipped whole must keep its set off")
        return store
    }

    private func pushV(_ exercises: [SessionExercise]?) throws -> SessionExercise {
        try XCTUnwrap(exercises?.first { $0.pattern == .pushV }, "the vertical push must be in this plan")
    }

    /// A probe takes the slot of the last working set. Under a cap that has
    /// not moved, the row's working sets drop by that one: the probe's own
    /// line says why, and the pulls took nothing.
    func testAProbeArrivingUnderAStandingCapIsNotPutDownToThePulls() throws {
        let store = try pushStore {
            $0.cut[.pull] = 1
            $0.doses[.pushH] = 15
            $0.shown[.pushH] = [3: 15]
            $0.lastHard = [.pushH]
        }
        let first = try pushH(store.nextSession)
        XCTAssertNil(first.probe, "the hard last answer must keep the probe away the first time")
        XCTAssertEqual(first.sets, 2)
        skipThePullWhole(store, workouts: 2)
        let row = try pushH(store.nextSession)
        XCTAssertNotNil(row.probe, "the probe must be offered now")
        XCTAssertEqual(row.sets, 1, "one working set and the probe fill the two sets the cap allows")
        XCTAssertFalse(store.setsJustHeldBackByThePulls(in: row),
                       "the working set went to the probe, not to the pulls")
    }

    /// The other way round: a probe that leaves hands its slot back to a
    /// working set. Under a cap that has not moved, that is one more working
    /// set and no set back.
    func testAProbeLeavingUnderAStandingCapIsNoSetBack() throws {
        let store = try pushStore {
            $0.cut[.pull] = 1
            $0.doses[.pushH] = 15
            $0.shown[.pushH] = [3: 15]
        }
        let probing = try pushH(store.nextSession)
        XCTAssertNotNil(probing.probe)
        XCTAssertEqual(probing.sets, 1)
        // A number under the plan is a hard answer: the probe stays away next time.
        store.completeWorkout(session: store.nextSession, result: .plan, overrides: [.pushH: 12],
                              skipped: [.pull], date: day(-300))
        XCTAssertEqual(store.records.last?.heldBack?.contains(.pushH), true,
                       "one working set and the probe stood on three sets of the push's own")
        skipThePullWhole(store, workouts: 1)
        let row = try pushH(store.nextSession)
        XCTAssertNil(row.probe, "the hard answer must keep the probe away")
        XCTAssertEqual(row.sets, 2, "the probe's slot is a working set again, under the same cap")
        XCTAssertFalse(store.aSetJustCameBack(in: row),
                       "no set came back: the cap still allows two")
    }

    /// The cap takes the slot a leaving probe hands back, so the row's
    /// number stands where it stood. A line about fewer sets beside a number
    /// that did not move would contradict the row.
    func testACapTakingALeavingProbesSlotLeavesTheNumberAndSaysNothing() throws {
        let store = try pushStore {
            $0.doses[.pushH] = 15
            $0.shown[.pushH] = [3: 15]
        }
        XCTAssertEqual(try pushH(store.nextSession).sets, 2, "two working sets and the probe")
        store.completeWorkout(session: store.nextSession, result: .plan, overrides: [.pushH: 12],
                              setsSkipped: [.pull: 1], date: day(-300))
        skipThePullWhole(store, workouts: 1)
        let row = try pushH(store.nextSession)
        XCTAssertNil(row.probe, "the hard answer must keep the probe away")
        XCTAssertEqual(row.sets, 2, "the cap must hold the push at two working sets")
        XCTAssertEqual(Engine.pullCap(on: .pushH, in: store.engineState).map { $0.cap < $0.own }, true,
                       "the cap must bind")
        XCTAssertFalse(store.setsJustHeldBackByThePulls(in: row),
                       "the number did not drop, so nothing about fewer sets may be said")
    }

    /// And the mirror: the cap lifts while a probe arrives to take the slot
    /// it frees. The working sets stand still, and "A set is back." beside
    /// an unchanged number would be false — the probe's line says what the
    /// new set is.
    func testACapLiftingIntoAnArrivingProbeIsNoSetBack() throws {
        let store = try pushStore {
            $0.cut[.pull] = 1
            $0.doses[.pushH] = 15
            $0.shown[.pushH] = [3: 15]
            $0.lastHard = [.pushH]
        }
        XCTAssertEqual(try pushH(store.nextSession).sets, 2, "held back to two, no probe yet")
        train(store)
        train(store)
        XCTAssertEqual(store.records.first?.heldBack?.contains(.pushH), true)
        let row = try pushH(store.nextSession)
        XCTAssertNotNil(row.probe, "the probe must be offered now")
        XCTAssertEqual(row.sets, 2, "the lifted cap's set must have gone to the probe")
        XCTAssertFalse(store.aSetJustCameBack(in: row),
                       "the working sets did not grow, so no set is back")
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
    }

    /// Workouts on plan with the pull sat out whole, so its set stays off.
    private func skipThePullWhole(_ store: AppStore, workouts: Int) {
        for _ in 0..<workouts {
            store.completeWorkout(session: store.nextSession, result: .plan, skipped: [.pull],
                                  date: day(-298 + 2 * store.records.count))
        }
    }

    /// A push held back appearance after appearance at the same count has
    /// nothing new to say: the line is about the drop, not about the cap.
    func testAPushStillHeldBackAtTheSameCountSaysNothingMore() throws {
        let store = try pullSitsOut()
        XCTAssertEqual(try pushV(store.records.last?.exercises).sets, 2,
                       "the vertical push's last card must already have been held back")
        let row = try pushV(store.nextSession.exercises)
        XCTAssertEqual(row.sets, 2, "and the pulls must still hold it at two")
        XCTAssertFalse(store.setsJustHeldBackByThePulls(in: row),
                       "a count that did not move has nothing to explain")
    }

    // MARK: - Up

    /// The pull's set comes back, and with it the push-ups' third set. The
    /// push's own hold never armed — it lost nothing of its own — so only the
    /// journal can tell that the card before showed it held back.
    func testASetThePullsGiveBackIsAnnouncedOnThePush() throws {
        let store = try pushHeldBack()
        XCTAssertEqual(try pushH(store.nextSession).sets, 2)
        train(store)
        let row = try pushH(store.nextSession)
        XCTAssertEqual(row.sets, 3, "the pull's set came back, so the cap must lift")
        XCTAssertNil(store.engineState.setsHold[.pushH],
                     "the push's own hold must not be what speaks here")
        XCTAssertTrue(store.aSetJustCameBack(in: row),
                      "the set the pulls gave back reached the push row without a word")
        XCTAssertFalse(store.setsJustHeldBackByThePulls(in: row))
    }

    /// A card on another variation is another movement: more sets on an
    /// easier variation are not a set coming back, and the row already says
    /// what changed — the variation.
    func testNoSetComesBackAcrossAVariation() throws {
        let store = try pushHeldBack()
        train(store)
        store.makeEasier(.pushH)
        let row = try pushH(store.nextSession)
        XCTAssertEqual(row.variation, 2, "the handle must have moved the push down a variation")
        XCTAssertEqual(row.sets, 3, "with more sets than the held-back card")
        XCTAssertFalse(store.aSetJustCameBack(in: row),
                       "more sets on another variation are not a set coming back")
    }

    /// A record from a build that did not stamp it claims nothing: whether its
    /// card was held back cannot be read off the journal afterwards, so the
    /// rise stays as silent as it always was.
    func testARecordWithoutTheStampClaimsNothing() throws {
        let store = try pushHeldBack()
        train(store)
        let row = try pushH(store.nextSession)
        XCTAssertTrue(store.aSetJustCameBack(in: row), "the stamped journal must announce the rise")

        store.update { state in
            for index in state.records.indices { state.records[index].heldBack = nil }
        }
        let file = try XCTUnwrap(String(data: try Data(contentsOf: tempURL), encoding: .utf8))
        XCTAssertFalse(file.contains("heldBack"),
                       "the file must carry no stamp at all — the shape an older build wrote")
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.records.count, 3)
        XCTAssertFalse(reloaded.aSetJustCameBack(in: row),
                       "a record without the stamp must claim nothing")
    }

    // MARK: - The stamp

    /// Whether a card was held back is decided against the position the plan
    /// was BUILT from. Here the horizontal push's own set comes back in the
    /// very workout it was capped in: two sets of its own under a cap of two —
    /// nothing held back on that card, though the position the rating leaves
    /// stands on three. The vertical push of the same workout stood on three
    /// and showed two.
    func testTheStampReadsThePositionThePlanWasBuiltFrom() throws {
        let store = try pushStore {
            $0.cut[.pushH] = 1
            $0.cut[.pull] = 1
        }
        XCTAssertEqual(try pushH(store.nextSession).sets, 2)
        train(store)
        XCTAssertEqual(Engine.pullCap(on: .pushH, in: store.engineState)?.own, 3,
                       "the rating must hand the push its own set back")
        XCTAssertEqual(store.records.last?.heldBack, [.pushV],
                       "only the vertical push showed fewer sets than it stood on")

        // A probe borrows a set rather than taking one: two working sets and
        // the probe are the push's three.
        let probing = try pushStore {
            $0.doses[.pushH] = 15
            $0.shown[.pushH] = [3: 15]
        }
        let row = try pushH(probing.nextSession)
        XCTAssertNotNil(row.probe, "the push must be on its ceiling with the probe offered")
        XCTAssertEqual(row.sets, 2)
        train(probing)
        XCTAssertNil(probing.records.last?.heldBack, "the probe's slot is not a set held back")
    }

    /// A changed rating replays the workout on the state before it, and an
    /// abandoned one is settled on the plan it was taken from — both through
    /// `completeWorkout`, so both carry the stamp the tap would have written.
    func testAChangedOrSettledWorkoutKeepsTheStamp() throws {
        let store = try pushHeldBack()
        train(store)
        XCTAssertEqual(store.records.last?.heldBack, [.pushH])
        store.changeLastRating(to: .less)
        XCTAssertEqual(store.records.last?.result, .less, "the rating must have changed")
        XCTAssertEqual(store.records.last?.heldBack, [.pushH],
                       "the replayed record must keep what the card showed")

        let settling = try pushHeldBack()
        let plan = settling.nextSession
        let savedAt = Date.now.addingTimeInterval(-WorkoutSessionStore.forgottenAfter - 60)
        settling.saveWorkoutSnapshot(WorkoutSnapshot(
            sessionNumber: plan.sessionNumber, exIndex: plan.exercises.count, setIndex: 0,
            workoutStart: savedAt.addingTimeInterval(-30 * 60), savedAt: savedAt,
            fingerprint: WorkoutSnapshot.fingerprint(of: plan), atFeedback: true))
        let relaunched = makeStore()
        XCTAssertTrue(relaunched.settleAbandonedWorkout())
        XCTAssertEqual(relaunched.records.count, 3)
        XCTAssertEqual(relaunched.records.last?.heldBack, [.pushH],
                       "a workout settled on the athlete's behalf must carry the stamp too")
    }

    // MARK: - The row

    /// The sentence is the row's, and it stands beside a probe's: one says
    /// why the working sets dropped, the other what the last set is.
    func testThePullsLineStandsBesideTheProbeLine() throws {
        let probe = SessionProbe(variation: 4, name: "Feet-elevated push-up", unit: .reps,
                                 load: 4, perSide: false)
        let row = SessionExercise(
            pattern: .pushH, name: "Push-up", variation: 3, unit: .reps,
            load: 15, perSide: false, sets: 1, restSetSec: 60, restExerciseSec: 90,
            loads: nil, probe: probe)
        let line = try XCTUnwrap(ExerciseRow.pullsNote(heldBack: true))
        let probeLine = try XCTUnwrap(ExerciseRow.probeNote(row))
        XCTAssertFalse(line.isEmpty)
        XCTAssertNil(ExerciseRow.pullsNote(heldBack: false))
        XCTAssertEqual(ExerciseRow.notes(row, setCameBack: false, heldBackByPulls: true), [line, probeLine],
                       "the pulls' line comes first, about the number; the probe's after it")
        XCTAssertEqual(ExerciseRow.notes(row, setCameBack: false), [probeLine])
    }
}
