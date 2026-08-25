//
//  The last accepted gap of the wave. The engine wrote
//  its memory of "what was on screen" only from a COMPLETED session, so a
//  plan a person looked at and did not train was invisible to it — and the
//  guarantee "a descent never adds load" held between finished workouts and
//  nowhere else. Measured against a merely-seen plan: a rise of up to ×1.47,
//  in 16–22 % of the "showed, skipped a week, opened again" episodes on
//  budgets of 30–35. The port exported `recordShown` for exactly one caller;
//  this is the app layer becoming it.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class ShownPlanTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-shown" }

    /// A trainee well up the scale, seeded through the state file the way the
    /// app itself loads one. High enough that the plan carries set bands the
    /// handle can move at all.
    private func advancedStore(level: Int = 40, budget: Int = 45) throws -> AppStore {
        let levels = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(level)" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":0,"levels":[\(levels)],"failStreak":[],
                        "timeBudgetMin":\(budget)},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,"timeBudgetChosen":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        return AppStore(storageURL: tempURL)
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now))!
            .addingTimeInterval(10 * 3600)
    }

    private func work(_ ex: SessionExercise) -> Int {
        ex.plannedVolume * (ex.perSide ? 2 : 1)
    }

    // MARK: - Once per showing

    /// The showing is written down whole: every movement of the plan, the work
    /// it was shown with, and the budget it was drawn under.
    func testAShowingIsWrittenDown() throws {
        let store = try advancedStore()
        let plan = store.nextSession
        XCTAssertTrue(store.engineState.shownWork.isEmpty, "nothing has been shown yet")

        store.recordPlanShown(plan)

        XCTAssertEqual(store.engineState.shownWork.count, plan.exercises.count)
        for ex in plan.exercises {
            XCTAssertEqual(store.engineState.shownWork[ex.pattern], work(ex),
                           "\(ex.pattern.rawValue) was shown at a different work")
        }
    }

    /// ONE WRITE PER SHOWING. SwiftUI redraws the plan on every scroll, every
    /// return to the tab and every Dynamic Type change; each redraw calling
    /// through would be a state write, a file write and a widget reload for a
    /// plan nobody saw twice. The state file is the witness: it is deleted
    /// after the first showing, and a second write would put it back.
    func testARedrawOfTheSameShowingWritesNothing() throws {
        let store = try advancedStore()
        store.recordPlanShown(store.nextSession)
        let afterFirst = store.engineState

        try FileManager.default.removeItem(at: tempURL)
        store.recordPlanShown(store.nextSession)
        store.recordPlanShown(store.nextSession)

        XCTAssertEqual(store.engineState, afterFirst, "a redraw is not a new showing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "the second and third redraws must not write at all")
    }

    /// …and writing it down must not change it. The memory keeps the work of
    /// the plan AFTER the postcondition repair, and the repair only trims work
    /// STRICTLY above what was shown — so the next draw has nothing to trim
    /// and the plan is a fixed point. Without that the card would shrink under
    /// the reader's eyes, one set per render.
    func testWritingAShowingDownDoesNotChangeThePlan() throws {
        for budget in [0, 30, 45, 90] {
            for level in [0, 12, 24, 32, 40, 44, 47] {
                let store = try advancedStore(level: level, budget: budget)
                let shown = store.nextSession
                store.recordPlanShown(shown)
                XCTAssertEqual(store.nextSession, shown,
                               "budget \(budget), level \(level): the plan moved under the reader")
                store.recordPlanShown(store.nextSession)
                XCTAssertEqual(store.nextSession, shown,
                               "budget \(budget), level \(level): and again on the next redraw")
            }
        }
    }

    /// A plan that changed under the reader — here because the workout in
    /// front of it was finished — is the new showing it is.
    func testTheNextPlanIsANewShowing() throws {
        let store = try advancedStore()
        let first = store.nextSession
        store.recordPlanShown(first)
        _ = store.completeWorkout(session: first, result: .plan, date: day(-1))

        let second = store.nextSession
        store.recordPlanShown(second)
        for ex in second.exercises {
            XCTAssertEqual(store.engineState.shownWork[ex.pattern], work(ex),
                           "\(ex.pattern.rawValue) is remembered at the plan on screen now")
        }
    }

    // MARK: - What the showing buys

    /// The guarantee itself, against a plan that was only LOOKED at: a
    /// movement whose position did not rise may not come back heavier. The
    /// week away is the case the measurement was taken on — showed, skipped a
    /// week, opened again — and the silent decay is what redraws the plan
    /// without a single tap.
    func testAPlanThatWasOnlySeenIsNotBeatenAWeekLater() throws {
        for budget in [30, 35, 45] {
            for level in [24, 32, 40, 44] {
                let store = try advancedStore(level: level, budget: budget)
                _ = store.completeWorkout(session: store.nextSession, result: .plan,
                                          date: day(-10))
                let seen = store.nextSession
                let ordBefore = seen.exercises.reduce(into: [Pattern: Int]()) { acc, ex in
                    acc[ex.pattern] = Level.posOrd(store.engineState.position(ex.pattern))
                }
                store.recordPlanShown(seen)

                // A week goes by with no workout: the blind-zone decay redraws
                // the plan on the next launch, and nothing else does.
                store.refreshDay(now: day(0))
                store.applySilentDecayIfNeeded(now: day(0))

                for ex in store.nextSession.exercises {
                    guard let was = seen.exercises.first(where: { $0.pattern == ex.pattern }),
                          let ordBefore = ordBefore[ex.pattern] else { continue }
                    guard Level.posOrd(store.engineState.position(ex.pattern)) <= ordBefore
                    else { continue }
                    XCTAssertLessThanOrEqual(
                        work(ex), work(was),
                        "budget \(budget), level \(level): \(ex.pattern.rawValue) came back "
                        + "heavier than the plan that was on screen a week ago")
                }
            }
        }
    }

    /// A launch that could not READ the state file draws its plan from an
    /// empty state — that is the least useful thing there is to remember, and
    /// writing it would pin the freeze and cost the trainee the journal for
    /// the rest of the launch. So a frozen journal is shown and not written
    /// down, and the real one still loads the moment it can be read.
    func testAFrozenJournalIsNeverWrittenDown() throws {
        try XCTSkipIf(getuid() == 0, "root reads through 0o000 permissions")
        let seed = try advancedStore()
        _ = seed.completeWorkout(session: seed.nextSession, result: .plan, date: day(-1))
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: tempURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: tempURL.path)
        }

        let frozen = AppStore(storageURL: tempURL)
        XCTAssertTrue(frozen.journalFrozen)
        frozen.recordPlanShown(frozen.nextSession)
        XCTAssertTrue(frozen.engineState.shownWork.isEmpty,
                      "a plan drawn from a state nobody could read is not a showing")

        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: tempURL.path)
        frozen.reloadIfNeeded()
        XCTAssertEqual(frozen.records.count, 1,
                       "the showing must not have pinned the freeze")
    }

    // MARK: - Reset

    /// A reset is exactly what the sets-handle fields are FOR, and `.initial`
    /// zeroes all of them. What it must NOT take with them: the bar in the
    /// doorway.
    ///
    /// The budget half of this test is gone with the budget, and the handle
    /// half with the handle: the `cut` axis is written by the skip inside the
    /// workout now. It IS one of the fields a reset clears, deliberately —
    /// starting the levels over is starting the plan over, and sets skipped
    /// at L40 have no meaning at L0.
    func testResetClearsTheSetsAxisAndKeepsTheDoorway() throws {
        let store = try advancedStore()
        store.setHasBar(true)
        let session = store.nextSession
        store.recordPlanShown(session)
        store.completeWorkout(session: session, result: .plan, setsSkipped: [.pull: 1])
        XCTAssertGreaterThan(store.engineState.cutOf(.pull), 0, "the skip landed")
        XCTAssertFalse(store.engineState.shownWork.isEmpty)

        store.resetProgress()

        XCTAssertTrue(store.engineState.cut.isEmpty)
        XCTAssertTrue(store.engineState.setsHold.isEmpty)
        XCTAssertTrue(store.engineState.shownWork.isEmpty)
        XCTAssertTrue(store.engineState.shownOrd.isEmpty)
        XCTAssertTrue(store.engineState.hasBar, "the bar did not leave the doorway")
    }

    // SNIPPED: `testTheIllnessLensShowingIsNotWrittenDown`. The lens built a
    // VIEW of the plan rather than moving the position, so its showing had to
    // be kept out of the memory the postcondition repair reads. There is no
    // lens, and no view: every plan on screen is the plan.
}
