//
//  The skip that happens DURING the workout — the app's half of spec §38.2.
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
final class SetSkipTests: XCTestCase {

    nonisolated(unsafe) private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dredfit-skip-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    /// Seeded through the state file, like the app's own load.
    private func store(level: Int) throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":0,"levels":[\(levels)],"failStreak":[]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    /// Rotation does not show every movement every session, so "the next
    /// showing" is the nearest session that contains the movement at all.
    private func nextShown(_ store: AppStore, _ pattern: Pattern) -> SessionExercise? {
        var probe = store.engineState
        for _ in 0...EngineConfig.stepsPerTier {
            if let ex = Engine.generateSession(probe).exercises
                .first(where: { $0.pattern == pattern }) {
                return ex
            }
            probe.counter += 1
        }
        return nil
    }

    // MARK: - Rule 1: the order, from the app's side

    /// §38.2's two worked examples, walked through the STORE: a session
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
        for (level, sets, load) in [(24, 3, 4), (40, 5, 8)] {
            let store = try store(level: level)
            let shown = try XCTUnwrap(nextShown(store, .squat))
            XCTAssertEqual([shown.sets, shown.load], [sets, load],
                           "L\(level): the plan is not the one §38.2 describes")

            store.completeWorkout(session: store.nextSession, result: .plan,
                                  setsSkipped: [.squat: 1])

            XCTAssertEqual(store.engineState.cutOf(.squat), 1,
                           "L\(level): the skip did not reach the state")
            let after = try XCTUnwrap(nextShown(store, .squat))
            XCTAssertEqual([after.sets, after.load], [sets - 1, load],
                           "L\(level): the next showing kept the set that was skipped")

            // The order the store must never take, walked from the same
            // starting point and with the same gap the store had (none — this
            // is the first workout): the skip written in advance is eaten by
            // the very event that would have handed the set back later.
            var base = EngineState.initial
            for pattern in Pattern.allCases { base.levels[pattern] = level }
            let early = Engine.setCut(state: base, pattern: .squat, cut: 1)
            let wrong = Engine.applyFeedback(state: early,
                                             session: Engine.generateSession(early),
                                             result: .plan, overrides: [:], skipped: [],
                                             gapDays: nil)
            XCTAssertEqual(wrong.cutOf(.squat), 0,
                           "L\(level): the wrong order no longer loses the skip — §38.2 "
                           + "rule 1 has stopped describing the engine")
        }
    }

    /// Every movement of the session at once, which is what a person short of
    /// time actually does — and the plan that comes back is shorter across the
    /// board rather than in the one place the walk happened to start.
    func testSkipsOnEveryMovementAllLand() throws {
        let store = try store(level: 40)
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

    /// What the app does instead, and the reason rule 2 exists: the movement
    /// travels as an ordinary skipped exercise, and NOT as a dose of 0. The
    /// engine costs one of them nothing and the other a whole tier.
    func testOnTheFloorTheMovementTravelsAsASkipAndNotAsAZero() throws {
        let store = try store(level: 24)
        // On the floor: every movement cut as far as the axis goes.
        let session = store.nextSession
        let onFloor = Dictionary(uniqueKeysWithValues: session.exercises.map { ($0.pattern, 1) })
        store.completeWorkout(session: session, result: .plan, setsSkipped: onFloor)
        let floored = try XCTUnwrap(nextShown(store, .squat))
        XCTAssertEqual(floored.sets, EngineConfig.setsFloor, "the seed is not on the floor")

        let before = store.engineState.levels[.squat] ?? 0
        let cutBefore = store.engineState.cutOf(.squat)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              skipped: [.squat], setsSkipped: [:])

        XCTAssertEqual(store.engineState.levels[.squat], before,
                       "a skip on the floor moved the level")
        XCTAssertEqual(store.engineState.cutOf(.squat), cutBefore,
                       "a skip on the floor moved the cut")
    }

    /// A movement recorded as skipped carries no skipped SETS with it: it was
    /// not trained, so there is no volume to take off it next time. The flow
    /// drops the tally when it takes the exercise; this is the claim that
    /// makes the drop matter.
    func testASkippedMovementAndSkippedSetsAreNotBothRecorded() throws {
        let store = try store(level: 40)
        let session = store.nextSession

        store.completeWorkout(session: session, result: .plan, skipped: [.squat])

        XCTAssertEqual(store.engineState.cutOf(.squat), 0,
                       "a movement nobody trained lost sets from its plan")
        XCTAssertNil(store.records.last?.setsSkipped,
                     "nothing was skipped set-wise, so the journal must say nothing")
    }

    // MARK: - The journal and the interrupted workout

    /// What happened is what the journal keeps. §38.6 asks after the release
    /// whether the mid-workout skip has become the dominant price, and a
    /// record that kept only the rating could not answer it.
    func testTheJournalRemembersTheSkippedSetsAcrossARelaunch() throws {
        let store = try store(level: 40)
        store.completeWorkout(session: store.nextSession, result: .plan,
                              setsSkipped: [.squat: 2])

        let reloaded = AppStore(storageURL: tempURL)
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
