import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class AppStoreTests: AppStoreTestCase {

    // MARK: - Initial state and persistence

    func testFreshStoreStartsEmpty() {
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.totalProgress, 0)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(store.doneToday)
        XCTAssertEqual(store.nextSession.sessionNumber, 1)
    }

    func testCompleteWorkoutPersistsAndReloads() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let skippedPattern = session.exercises[1].pattern
        store.completeWorkout(session: session, result: .more,
                              overrides: [session.exercises[0].pattern: 6.0],
                              skipped: [skippedPattern])

        // a separate store on the same file sees the same state
        let reloaded = AppStore(storageURL: tempURL)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.engineState, store.engineState)
        XCTAssertEqual(reloaded.records.last?.result, .more)
        XCTAssertEqual(reloaded.records.last?.exercises?.count,
                       session.exercises.count, "workout snapshot was not saved")
        XCTAssertEqual(reloaded.records.last?.actuals?[session.exercises[0].pattern], 6)
        // skips and the per-pattern level snapshot survive the reload
        XCTAssertEqual(reloaded.records.last?.skipped, [skippedPattern])
        XCTAssertEqual(reloaded.records.last?.positionsAfter, store.currentPositions)
    }

    /// The journal keeps the sets behind the number, so history can say
    /// "15 · 15 · 10" instead of the bare mean the engine was handed.
    func testTheJournalKeepsTheSetsBehindTheReportedNumber() throws {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let ex = session.exercises[0]
        // One rep short on the last set. A clean start plans 3×4, and the
        // corridor floor is 0 — "minus five" would have been clamped there and
        // the assertion would have compared two clamps.
        let facts = SetFacts.recording(ex.load - 1, in: [:], ex, set: ex.sets - 1)
        let overrides = SetFacts.overrides(facts, in: session.exercises)
        store.completeWorkout(session: session, result: .plan,
                              overrides: overrides, setActuals: facts)

        let record = try XCTUnwrap(AppStore(storageURL: tempURL).records.last)
        XCTAssertEqual(record.setActuals?[ex.pattern], facts[ex.pattern])
        // ПЕРЕРАЗМЕЧЕНО §41.3 (v3.1): движок получает СЫРОЕ среднее (дробь),
        // а журнал тренировок хранит целое — он персистится, и менять его тип
        // ради десятой доли, которую человек не читает, нельзя. Утверждение то
        // же: записано ровно то число, по которому движок и действовал.
        XCTAssertEqual(record.actuals?[ex.pattern],
                       overrides[ex.pattern].map { Int($0.rounded()) },
                       "the stored number is the one the engine acted on")
    }

    func testSkippedExerciseKeepsItsLevel() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let skippedPattern = session.exercises[2].pattern
        store.completeWorkout(session: session, result: .more, skipped: [skippedPattern])
        XCTAssertEqual(Engine.progress(store.engineState, skippedPattern), 0,
                       "a skipped pattern must not level up")
        XCTAssertEqual(store.engineState.sub[skippedPattern] ?? 0, 0,
                       "nor collect a sub-step")
        // "moves by the rating" is two SUB-STEPS, which at level zero is not
        // yet a level.
        XCTAssertEqual(store.engineState.sub[session.exercises[0].pattern],
                       EngineConfig.deltaMore,
                       "a trained pattern must still move by the rating")
        XCTAssertEqual(store.records.last?.skipped, [skippedPattern])
    }

    /// The claim a UI walk used to make by tapping "easy" on a session where
    /// nothing was trained. It cannot tap it any more — the card is offered
    /// only for a plan finished in full (`SetFacts.didFullPlan`) — so the
    /// invariant is pinned here instead, in the terms the screen stated it in:
    /// the number on Progress.
    ///
    /// The rating is still handed to the engine as `.more`, because the point
    /// is the ENGINE's guarantee and not the screen's: it must hold for a call
    /// no button can produce, or the gate would be all that stands behind it.
    func testEasyOverAFullySkippedSessionLeavesTheTotalAtZero() {
        let store = AppStore(storageURL: tempURL)
        let session = store.nextSession
        let skipped = Set(session.exercises.map(\.pattern))
        store.completeWorkout(session: session, result: .more, skipped: skipped)
        XCTAssertEqual(store.totalProgress, 0,
                       "skipped exercises must not raise the level (honest skips)")
        XCTAssertEqual(store.engineState.counter, 1,
                       "the appearance is still spent — the session happened")
    }

}
