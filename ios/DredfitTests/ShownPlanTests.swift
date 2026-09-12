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

    /// A trainee well up the ladders, seeded through the state file the way
    /// the app itself loads one: every movement `variation` rungs up (capped
    /// by its own ladder), with the journal of what was shown filled in behind
    /// it — a descent lands IN that journal (§40.6), and a state without one
    /// would send every movement to the floor instead.
    ///
    /// SEEDED IN THE v3 SHAPE — `vars`/`doses`/`shown`, never `levels`. This
    /// factory wrote the retired v2 shape for a whole release cycle and
    /// checked nothing afterwards: the state did not decode (§40.8), the store
    /// started clean, and both sweeps below ran ONE state 28 and 12 times over
    /// while their messages named a level and a budget. The guard after the
    /// load is the other half of that fix, and it is the half that would have
    /// caught it.
    ///
    /// The dose sits one rung BELOW the ceiling deliberately. At the ceiling
    /// §40.4 offers a probe; a probe takes a working set out of the plan, and
    /// neither the showing memory nor the postcondition repair speaks about an
    /// exercise carrying one (`Engine.recordShown`, `repairDescent`). That is
    /// a different guarantee, and not this suite's.
    private func advancedStore(variation: Int = 5) throws -> AppStore {
        func at(_ p: Pattern) -> Int { min(variation, Library.count(p)) }
        func dose(_ p: Pattern, _ v: Int) -> Int {
            let grid = Dose.grid(Library.unit(p, v))
            return grid.max - grid.step
        }
        let vars = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(at($0))" }.joined(separator: ",")
        let doses = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(dose($0, at($0)))" }.joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let journal = Pattern.allCases.map { p in
            let rows = (1...at(p)).map { "\"\($0)\":\(dose(p, $0))" }.joined(separator: ",")
            return "\"\(p.rawValue)\",{\(rows)}"
        }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":0,"vars":[\(vars)],"doses":[\(doses)],
                        "shown":[\(journal)],"failStreak":[\(zeros)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        // The seed must actually load — a state that failed to decode would
        // start clean and make every assertion here vacuous. The journal is
        // checked alongside the position because a clean start carries none at
        // all, so this still bites at `variation == 1`, where the positions of
        // a clean start and of the seed agree.
        XCTAssertEqual(store.engineState.vars[.pull], at(.pull),
                       "the seed did not load: the pull slot is not where it was written")
        XCTAssertEqual(store.engineState.shownDose(.pull, variation: at(.pull)),
                       dose(.pull, at(.pull)),
                       "the seed did not load: the journal of what was shown is not there")
        return store
    }

    /// The widest position any ladder reaches — the sweeps below walk to it.
    private var deepestVariation: Int { Pattern.allCases.map(Library.count).max() ?? 1 }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now))!
            .addingTimeInterval(10 * 3600)
    }

    private func work(_ ex: SessionExercise) -> Int {
        ex.plannedVolume * (ex.perSide ? 2 : 1)
    }

    // MARK: - Once per showing

    /// The showing is written down whole: every movement of the plan, and the
    /// work it was shown with.
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
    ///
    /// RE-MARKED (test revision, 26.08.2026): the outer sweep was over a
    /// `budget` the state has not carried since the time budget went
    /// (`AppSettings.swift`). `JSONDecoder` ignores keys it does not know, so
    /// `timeBudgetMin` and `timeBudgetChosen` landed nowhere and the four
    /// values ran four IDENTICAL configurations while the message printed a
    /// number as if the axis were live. What is left is the axis that exists.
    func testWritingAShowingDownDoesNotChangeThePlan() throws {
        for variation in 1...deepestVariation {
            let store = try advancedStore(variation: variation)
            let shown = store.nextSession
            store.recordPlanShown(shown)
            XCTAssertEqual(store.nextSession, shown,
                           "variation \(variation): the plan moved under the reader")
            store.recordPlanShown(store.nextSession)
            XCTAssertEqual(store.nextSession, shown,
                           "variation \(variation): and again on the next redraw")
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
    ///
    /// RE-MARKED (test revision, 26.08.2026): the dead `budget` sweep is gone
    /// for the reason given on the test above it — three values, one
    /// configuration — and the level axis is the ladder axis now.
    func testAPlanThatWasOnlySeenIsNotBeatenAWeekLater() throws {
        for variation in 1...deepestVariation {
            let store = try advancedStore(variation: variation)
            _ = store.completeWorkout(session: store.nextSession, result: .plan,
                                      date: day(-10))
            let seen = store.nextSession
            let ordBefore = seen.exercises.reduce(into: [Pattern: Int]()) { acc, ex in
                acc[ex.pattern] = Engine.progress(store.engineState, ex.pattern)
            }
            store.recordPlanShown(seen)

            // A week goes by with no workout: the blind-zone decay redraws
            // the plan on the next launch, and nothing else does.
            store.refreshDay(now: day(0))
            store.applySilentDecayIfNeeded(now: day(0))

            for ex in store.nextSession.exercises {
                guard let was = seen.exercises.first(where: { $0.pattern == ex.pattern }),
                      let ordBefore = ordBefore[ex.pattern] else { continue }
                guard Engine.progress(store.engineState, ex.pattern) <= ordBefore
                else { continue }
                XCTAssertLessThanOrEqual(
                    work(ex), work(was),
                    "variation \(variation): \(ex.pattern.rawValue) came back "
                    + "heavier than the plan that was on screen a week ago")
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
    /// starting the ladders over is starting the plan over, and sets skipped
    /// five rungs up have no meaning back on the first variation.
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
