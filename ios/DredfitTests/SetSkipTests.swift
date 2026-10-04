//
//  The skip that happens DURING the workout — the app's half of the rule.
//
//  The engine's half is pinned in EngineV227Tests: the order is a contract,
//  the floor is not a place to record a dose of 0, and one tap per movement is
//  what makes a long session fit. What is left for this suite is everything
//  between the tap and the engine — that the app hands the skip over through
//  the one entry point that settles the order, that a movement it could not
//  record travels as a skipped exercise instead, and that neither the journal
//  nor an interrupted workout loses the count on the way.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SetSkipTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-skip" }

    /// Seeded through the state file, like the app's own load — in the v3
    /// shape, because a v2 state no longer decodes at all (§40.8) and a seed
    /// the store quietly replaced with a clean start would make the assertions
    /// here true for the wrong reason.
    ///
    /// `variation` rungs up every ladder, one rung BELOW the dose ceiling —
    /// a ceiling would offer a PROBE (§40.4), and a probe set is not a working
    /// set a skip can take, so the plan under test would stop being the plan
    /// §38.2 describes. `sets` opens a band, which exists only on the top
    /// variation (§40.5).
    private func store(variation: Int, sets: Int = EngineConfig.setsBase) throws -> AppStore {
        func at(_ p: Pattern) -> Int { min(variation, Library.count(p)) }
        func dose(_ p: Pattern) -> Int {
            let grid = Dose.grid(Library.unit(p, at(p)))
            return grid.max - grid.step
        }
        let vars = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(at($0))" }.joined(separator: ",")
        let doses = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(dose($0))" }.joined(separator: ",")
        let bands = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(sets)" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":0,"vars":[\(vars)],"doses":[\(doses)],
                        "sets":[\(bands)],"failStreak":[]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return makeStore()
    }

    /// Rotation does not show every movement every session, so "the next
    /// showing" is the nearest session that contains the movement at all.
    private func nextShown(_ store: AppStore, _ pattern: Pattern) -> SessionExercise? {
        var probe = store.engineState
        for _ in 0...8 {   // eight sessions is one full turn of the rotation
            if let ex = Engine.generateSession(probe).exercises
                .first(where: { $0.pattern == pattern }) {
                return ex
            }
            probe.counter += 1
        }
        return nil
    }

    // MARK: - Rule 1: the order, from the app's side

    /// The rule's two worked examples, walked through the STORE: a session
    /// completed on plan with one set skipped comes back one set shorter.
    ///
    /// This is the app's half of rule 1 and it is a real guard, not a copy of
    /// the engine's. The store cannot express the wrong order — it hands the
    /// tally to the overload that settles it — and the assertion below is what
    /// goes red if it ever starts writing the cut itself: with the cut written
    /// BEFORE the rating, `riseBy` hands the set straight back and the plan
    /// comes round unchanged. The second half of the test shows exactly that,
    /// so the first half cannot be read as passing by luck.
    func testASkippedSetReachesTheNextPlanThroughTheRating() throws {
        // The base band and a real band: a movement partway up its ladder,
        // and one at the very top of it where §40.5 opens the set bands.
        for (variation, sets) in [(2, EngineConfig.setsBase),
                                  (Library.count(.squat), EngineConfig.setsMax)] {
            let store = try store(variation: variation, sets: sets)
            let shown = try XCTUnwrap(nextShown(store, .squat))
            XCTAssertEqual(shown.sets, sets,
                           "v\(variation): the plan is not the one §38.2 describes")
            XCTAssertNil(shown.probe, "v\(variation): a probe set is not a working set")

            _ = store.completeWorkout(session: store.nextSession, result: .plan,
                                      setsSkipped: [.squat: 1])

            XCTAssertEqual(store.engineState.cutOf(.squat), 1,
                           "v\(variation): the skip did not reach the state")
            let after = try XCTUnwrap(nextShown(store, .squat))
            XCTAssertEqual(after.sets, shown.sets - 1,
                           "v\(variation): the next showing kept the set that was skipped")

            // The order the store must never take, walked from the same
            // starting point and with the same gap the store had (none — this
            // is the first workout): the skip written in advance is eaten by
            // the very event that would have handed the set back later.
            var base = EngineState.initial
            for pattern in Pattern.allCases {
                let v = min(variation, Library.count(pattern))
                let grid = Dose.grid(Library.unit(pattern, v))
                base.vars[pattern] = v
                base.doses[pattern] = grid.max - grid.step
                base.sets[pattern] = sets
            }
            let early = Engine.setCut(state: base, pattern: .squat, cut: 1)
            let wrong = Engine.applyFeedback(state: early,
                                             session: Engine.generateSession(early),
                                             result: .plan, overrides: [:], skipped: [],
                                             gapDays: nil)
            XCTAssertEqual(wrong.cutOf(.squat), 0,
                           "v\(variation): the wrong order no longer loses the skip — §38.2 "
                           + "rule 1 has stopped describing the engine")
        }
    }

    /// Every movement of the session at once, which is what a person short of
    /// time actually does — and the plan that comes back is shorter across the
    /// board rather than in the one place the walk happened to start.
    func testSkipsOnEveryMovementAllLand() throws {
        let store = try store(variation: 3, sets: EngineConfig.setsBase)
        let session = store.nextSession
        let skipped = Dictionary(uniqueKeysWithValues: session.exercises.map { ($0.pattern, 1) })

        store.completeWorkout(session: session, result: .plan, setsSkipped: skipped)

        for ex in session.exercises {
            XCTAssertEqual(store.engineState.cutOf(ex.pattern), 1,
                           "\(ex.pattern): the skip was lost")
        }
        XCTAssertLessThan(store.nextSession.estimatedTotalMin, session.estimatedTotalMin,
                          "a session with a set off every movement is not shorter")
    }

    // MARK: - Rule 2: what the app may record, and what it may not

    /// The arithmetic both escapes on the work screen read. A movement has to
    /// keep the floor's worth of sets to count as trained at all.
    func testTheFloorIsWhereTheSkipStopsBeingASkippedSet() {
        // A plan of two is already on the floor: there is no set to take.
        XCTAssertFalse(SetFacts.skipFits(1, of: EngineConfig.setsFloor, alreadySkipped: 0),
                       "on the floor a skipped set cannot be recorded as one")
        // A plan of five gives three, and the fourth is the movement itself.
        for gone in 0..<3 {
            XCTAssertTrue(SetFacts.skipFits(1, of: 5, alreadySkipped: gone),
                          "5 sets with \(gone) gone still has one to give")
        }
        XCTAssertFalse(SetFacts.skipFits(1, of: 5, alreadySkipped: 3),
                       "the fourth skip of five would leave a single set")
        // And the same rule read the other way: what "skip the rest" may take
        // is whatever leaves the floor standing.
        XCTAssertTrue(SetFacts.skipFits(3, of: 5, alreadySkipped: 0),
                      "two sets performed and the other three skipped is one tap")
        XCTAssertFalse(SetFacts.skipFits(4, of: 5, alreadySkipped: 0),
                       "a single set performed is not a trained movement")
    }

    /// A probing exercise never has more working sets than the shared floor,
    /// so none of them can be skipped on its own and the work screen offers
    /// "Skip exercise" in place of "Skip this set". That is what keeps the one
    /// card a hold summary lets a person correct, the last working set, a set
    /// the clock ran: the probe still ends on that summary, and a working set
    /// skipped before it would stand on the card under a line saying what the
    /// clock saw.
    ///
    /// The engine holds it by construction — a probe needs a variation below
    /// the top, where the sets stay at the base band, the probe takes one of
    /// them, and the pull slot's set count may only lower the push it caps —
    /// so it is swept rather than taken on trust: every rung of every ladder
    /// on its ceiling, every band asked for and one past the last, every cut,
    /// a full turn of the rotation, both branches of the pull slot, and that
    /// slot also on the top of its own ladder, in a band above any push that
    /// can probe.
    func testTheEngineNeverGivesAProbingExerciseThreeWorkingSets() {
        // Every movement on the ceiling of `rung` and journalled there; the
        // pull slot on the top of its own ladder instead when `pullOnTop`.
        func onTheCeiling(rung: Int, sets: Int, cut: Int, pullOnTop: Bool) -> EngineState {
            var state = EngineState.initial
            for p in Pattern.allCases {
                let v = pullOnTop && Pattern.pullSide.contains(p) ? Library.count(p) : min(rung, Library.count(p))
                let ceiling = Dose.grid(Library.unit(p, v)).max
                state.vars[p] = v
                state.doses[p] = ceiling
                state.sets[p] = sets
                state.cut[p] = cut
                state.shown[p] = [v: ceiling]
            }
            return state
        }
        let longestLadder = Pattern.allCases.map { Library.count($0) }.max() ?? 1
        var probing: [SessionExercise] = []
        for rung in 1...longestLadder {
            for sets in 1...EngineConfig.setsMax + 1 {
                for cut in 0...EngineConfig.setsMax - EngineConfig.setsFloor {
                    for pullOnTop in [false, true] {
                        var state = onTheCeiling(rung: rung, sets: sets, cut: cut, pullOnTop: pullOnTop)
                        for counter in 0..<8 {   // eight sessions is one full turn of the rotation
                            state.counter = counter
                            for hasBar in [false, true] {
                                state.hasBar = hasBar
                                probing += Engine.generateSession(state).exercises.filter { $0.probe != nil }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(probing.contains { $0.unit == .hold },
                      "the sweep met no probing hold, so it says nothing about the summary")
        let widest = probing.max { $0.sets < $1.sets }
        XCTAssertLessThanOrEqual(widest?.sets ?? 0, EngineConfig.setsFloor,
                                 "\(widest?.pattern.rawValue ?? "?") v\(widest?.variation ?? 0) has "
                                 + "\(widest?.sets ?? 0) working sets beside its probe: one can be skipped alone")
    }

    /// What the app does instead, and the reason rule 2 exists: the movement
    /// travels as an ordinary skipped exercise, and NOT as a dose of 0. The
    /// engine costs one of them nothing and the other a whole tier.
    func testOnTheFloorTheMovementTravelsAsASkipAndNotAsAZero() throws {
        let store = try store(variation: 2, sets: EngineConfig.setsBase)
        // On the floor: every movement cut as far as the axis goes.
        let session = store.nextSession
        let onFloor = Dictionary(uniqueKeysWithValues: session.exercises.map { ($0.pattern, 1) })
        store.completeWorkout(session: session, result: .plan, setsSkipped: onFloor)
        let floored = try XCTUnwrap(nextShown(store, .squat))
        XCTAssertEqual(floored.sets, EngineConfig.setsFloor, "the seed is not on the floor")

        let before = store.engineState.position(.squat)
        let cutBefore = store.engineState.cutOf(.squat)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              skipped: [.squat], setsSkipped: [:])

        XCTAssertEqual(store.engineState.position(.squat), before,
                       "a skip on the floor moved the position")
        XCTAssertEqual(store.engineState.cutOf(.squat), cutBefore,
                       "a skip on the floor moved the cut")
    }

    /// A movement recorded as skipped carries no skipped SETS with it: it was
    /// not trained, so there is no volume to take off it next time. The flow
    /// drops the tally when it takes the exercise; this is the claim that
    /// makes the drop matter.
    func testASkippedMovementAndSkippedSetsAreNotBothRecorded() throws {
        let store = try store(variation: 3, sets: EngineConfig.setsBase)
        let session = store.nextSession

        store.completeWorkout(session: session, result: .plan, skipped: [.squat])

        XCTAssertEqual(store.engineState.cutOf(.squat), 0,
                       "a movement nobody trained lost sets from its plan")
        XCTAssertNil(store.records.last?.setsSkipped,
                     "nothing was skipped set-wise, so the journal must say nothing")
    }

    // MARK: - The journal and the interrupted workout

    /// What happened is what the journal keeps. The post-release audit asks
    /// whether the mid-workout skip has become the dominant price, and a
    /// record that kept only the rating could not answer it.
    func testTheJournalRemembersTheSkippedSetsAcrossARelaunch() throws {
        let store = try store(variation: 3, sets: EngineConfig.setsBase)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              setsSkipped: [.squat: 2])

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.records.last?.setsSkipped, [.squat: 2],
                       "the journal lost the sets that were skipped")
    }

    /// The tally survives process death the way the per-set facts do — it is
    /// in the snapshot, and it comes back sanitized.
    func testTheSnapshotCarriesTheTallyAndHealsIt() throws {
        let snapshot = WorkoutSnapshot(
            sessionNumber: 1, exIndex: 1, setIndex: 2,
            setsSkipped: [.squat: 1, .pull: -3, .hinge: 99],
            workoutStart: .now, savedAt: .now)
        let restored = try JSONDecoder().decode(
            WorkoutSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(restored.setsSkipped?[.squat], 1)
        XCTAssertEqual(restored.skips, [.squat: 1, .hinge: EngineConfig.setsMax],
                       "a hand-edited file must not reach the engine as it is")
    }

    /// A snapshot written before the skip existed still decodes — the field is
    /// optional for the same reason every field below it is.
    func testAnOlderSnapshotStillDecodes() throws {
        let json = """
        {"sessionNumber":1,"exIndex":0,"setIndex":0,"actuals":[],"skipped":[],
         "workoutStart":0,"savedAt":0}
        """
        let snapshot = try JSONDecoder().decode(WorkoutSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.skips.isEmpty, "an older snapshot must read as no skips")
    }
}
