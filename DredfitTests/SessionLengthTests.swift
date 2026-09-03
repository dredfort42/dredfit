//
//  How long a session takes, and what the person can do about it.
//
//  This suite used to be about the TIME BUDGET: that the answer was stored,
//  survived a relaunch, reached the plan, and bought its minutes out of the
//  sets rather than the levels. All thirteen tests went with the mechanism —
//  the audit measured what its rungs actually did: 10, 15 and 20 produced the
//  SAME plan, and the "20" rung missed its own target in 100 % of sessions.
//
//  What replaced it was a handle on the plan, and that has now been removed
//  too: nobody is asked before the workout how much of it they have in them.
//  The plan announces its length; the person shortens the session from inside
//  it (SetSkipTests), and the movement's own VARIATION is the one thing still
//  worth choosing in advance — which is what is left here.
//
//  The hard-coded minute rows this file used to carry went with the level
//  scale (§40.7): they were keyed by `L`, and there is no `L`. Every number
//  below is DERIVED from the engine, which is the only place duration
//  arithmetic has ever lived.
//

import XCTest
import DredfitCore
@testable import Dredfit

@MainActor
final class SessionLengthTests: AppStoreTestCase {

    override var tempURLPrefix: String { "dredfit-length" }

    /// A trainee `variation` rungs up every ladder, at the dose ceiling —
    /// where a full session runs long, which is the case the range exists for.
    ///
    /// Seeded in the v3 shape: a v2 state does not decode at all now (§40.8),
    /// and a seed the store quietly replaced with a clean start would make
    /// every assertion here true for the wrong reason. `lastHard` keeps a
    /// probe out of the plan, so the numbers are about working sets.
    private func advancedStore(counter: Int = 0, variation: Int,
                               hasBar: Bool = false) throws -> AppStore {
        func at(_ p: Pattern) -> Int { min(variation, Library.count(p)) }
        let vars = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(at($0))" }.joined(separator: ",")
        let doses = Pattern.allCases
            .map { "\"\($0.rawValue)\",\(Dose.grid(Library.unit($0, at($0))).max)" }
            .joined(separator: ",")
        let zeros = Pattern.allCases
            .map { "\"\($0.rawValue)\",0" }.joined(separator: ",")
        let journal = Pattern.allCases.map { p in
            let rows = (1...at(p)).map { "\"\($0)\":\(Dose.grid(Library.unit(p, $0)).max)" }
                .joined(separator: ",")
            return "\"\(p.rawValue)\",{\(rows)}"
        }.joined(separator: ",")
        let hard = Pattern.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        let json = """
        {"engineState":{"counter":\(counter),"hasBar":\(hasBar),
                        "vars":[\(vars)],"doses":[\(doses)],
                        "shown":[\(journal)],"lastHard":[\(hard)],
                        "failStreak":[\(zeros)]},
         "records":[],
         "settings":{"restWeekdays":[],"soundsEnabled":true,
                     "reminderEnabled":false,"reminderHour":9,"reminderMinute":0}}
        """
        try Data(json.utf8).write(to: tempURL)
        let store = AppStore(storageURL: tempURL)
        XCTAssertEqual(store.engineState.vars[.squat], at(.squat), "the seed must load")
        return store
    }

    /// The widest position any ladder reaches — the sweeps below walk to it.
    private var deepestVariation: Int { Pattern.allCases.map(Library.count).max() ?? 1 }

    // MARK: - The range on Today

    /// A range is a promise about which end is which, and both ends are the
    /// ENGINE's own `estimatedTotalMin` — the app owns no duration arithmetic.
    ///
    /// RE-MARKED (test revision, 26.08.2026), class: the assert was true by
    /// construction. `sessionLengthRange` builds its low end as
    /// `min(flooredSession, full)` (`AppStore+Handles.swift`), so
    /// `floor <= full` is what the clamp GUARANTEES and no mutation of the
    /// floor could break it: with `cut: 0` the floor session was the full one,
    /// Today read "about 31 to 31 minutes", and all three asserts of this
    /// suite stayed green. The width is asserted STRICTLY now, and the low end
    /// is pinned against a session counted here rather than against the clamp.
    func test_sessionLengthRange_onEveryVariation_isStrictlyShorterAtItsFloor() throws {
        for variation in 1...deepestVariation {
            let store = try advancedStore(variation: variation)
            let length = store.sessionLengthRange()
            // Every movement stands on the base band and the floor is below
            // it, so at least one set — and its pause — comes off each of the
            // six. A range whose ends meet is not a range.
            XCTAssertLessThan(length.floor, length.full,
                              "variation \(variation): the range must have width — "
                              + "\(EngineConfig.setsBase) sets can be taken down to "
                              + "\(EngineConfig.setsFloor) on every movement")
            XCTAssertEqual(length.full, Int(store.nextSession.estimatedTotalMin.rounded()),
                           "variation \(variation): the full end is not the announced plan")
            XCTAssertGreaterThan(length.floor, 0, "variation \(variation): a session takes time")
        }
    }

    /// …and the low end is the session it CLAIMS to be: the same plan with
    /// every movement on the sets floor.
    ///
    /// The expectation is built from `EngineConfig.setsFloor` and checked to
    /// have landed there before the minutes are compared, so it is an
    /// expectation and not an echo of `min(…)`. A floor session that quietly
    /// kept its sets fails on the set count, one line before the arithmetic.
    func test_sessionLengthRange_floor_isTheSessionWithEveryMovementOnTheSetsFloor() throws {
        for variation in 1...deepestVariation {
            let store = try advancedStore(variation: variation)
            var floored = store.engineState
            for pattern in Pattern.allCases {
                floored = Engine.setCut(
                    state: floored, pattern: pattern,
                    cut: floored.position(pattern).sets - EngineConfig.setsFloor)
            }
            let shortest = Engine.generateSession(floored)
            for ex in shortest.exercises {
                XCTAssertEqual(ex.sets, EngineConfig.setsFloor,
                               "variation \(variation) \(ex.pattern): the expectation itself "
                               + "did not reach the floor")
            }
            XCTAssertEqual(store.sessionLengthRange().floor,
                           Int(shortest.estimatedTotalMin.rounded()),
                           "variation \(variation): the low end is not the floored session")
        }
    }

    /// The claim is about the WHOLE scale: nothing anywhere on it can be
    /// squeezed below what a clean start costs on its sets floor. The floor of
    /// the shortest possible session IS the clean start's — the least work the
    /// app is willing to call a workout (§37.1).
    func testNoPositionIsShorterThanACleanStartOnItsFloor() throws {
        let cleanFloor = try advancedStore(variation: 1).sessionLengthRange().floor
        for variation in 1...deepestVariation {
            let store = try advancedStore(variation: variation)
            XCTAssertGreaterThanOrEqual(
                store.sessionLengthRange().floor, cleanFloor,
                "variation \(variation) can be squeezed under the shortest session there is")
        }
    }

    /// And a session grows as the ladder does — otherwise the range would be
    /// saying nothing at all.
    func testTheFullSessionGrowsAlongTheLadder() throws {
        let low = try advancedStore(variation: 1).sessionLengthRange().full
        let high = try advancedStore(variation: deepestVariation).sessionLengthRange().full
        XCTAssertGreaterThan(high, low,
                             "a session at the top of the ladders must cost more than one at the bottom")
    }

    // MARK: - The handle that is left

    /// The step below is absent on the first variation — there is nothing under
    /// it in the library — and the block that carries the handle is absent with
    /// it, rather than standing disabled beside a name it cannot deliver.
    func testTheEasierHandleIsInactiveOnTheFirstVariation() throws {
        let store = try advancedStore(variation: 1)
        for ex in store.nextSession.exercises {
            XCTAssertEqual(ex.variation, 1)
            XCTAssertFalse(store.canMakeEasier(ex.pattern),
                           "\(ex.pattern): there is nothing below the first variation")
            XCTAssertNil(store.easierStep(ex.pattern))
        }
    }

    /// And where it IS active it carries its RESULT: the block names the
    /// variation the person would get, and the tap delivers that one.
    func testTheEasierHandlePreviewIsWhatTheTapDelivers() throws {
        let store = try advancedStore(variation: 3)
        let target = try XCTUnwrap(store.nextSession.exercises.first).pattern
        let step = try XCTUnwrap(store.easierStep(target))

        store.makeEasier(target)

        let now = try XCTUnwrap(store.nextSession.exercises.first { $0.pattern == target })
        XCTAssertEqual(step.name, now.name,
                       "the block promised a variation the tap did not deliver")
        XCTAssertEqual(step.dose, now.display,
                       "the block promised a dose the tap did not deliver")
        XCTAssertEqual(step.variation, now.variation,
                       "the block promised a rung the tap did not land on")
    }

    /// The block asks a QUESTION of the engine: everything it shows comes back
    /// from `easierVariation` on a copy, and the state the person is standing
    /// on is untouched until they tap. A preview that wrote would move the plan
    /// of anybody who merely opened a technique sheet.
    func testTheEasierStepWritesNothing() throws {
        let store = try advancedStore(variation: 3)
        let before = store.engineState
        for ex in store.nextSession.exercises {
            _ = store.easierStep(ex.pattern)
        }
        XCTAssertEqual(store.engineState, before,
                       "reading the step below moved the state")
    }

    /// The one fact the old glued preview could not carry, and the reason the
    /// block takes the pieces apart.
    ///
    /// `pull_bar` 3 → 2 is the ONLY boundary in the library where the unit
    /// changes (§40.1): the negatives are reps and the scapular hang below them
    /// is seconds. Pinned by its two ends rather than re-derived from
    /// `Library.unit` on both sides — that comparison is the implementation,
    /// and a test that restates it would stay green if the flag were wired to
    /// the wrong pair.
    ///
    /// The bar branch needs `hasBar` AND an odd counter, or the pull slot deals
    /// `pull` and the pattern is not in the session at all.
    func testTheUnitChangeIsFlaggedOnTheOneBoundaryThatHasOne() throws {
        let crossing = try advancedStore(counter: 1, variation: 3, hasBar: true)
        let down = try XCTUnwrap(crossing.easierStep(.pullBar))
        XCTAssertEqual(down.variation, 2)
        XCTAssertTrue(down.unitChanged,
                      "negatives → a hang is reps → seconds, and the block has to say so")

        // One rung higher the neighbours are both reps, and the note must not
        // appear — a flag that is always true says nothing.
        let inside = try advancedStore(counter: 1, variation: 4, hasBar: true)
        let quiet = try XCTUnwrap(inside.easierStep(.pullBar))
        XCTAssertEqual(quiet.variation, 3)
        XCTAssertFalse(quiet.unitChanged,
                       "4 → 3 stays in reps; the unit note would be a lie")
    }

    /// The handle goes through the ENGINE, so its landing is §40.6's and
    /// nothing else: one variation down, on the base set count.
    ///
    /// RE-MARKED §41.1 (v3.1, 26.08.2026), class: the test pinned the defect.
    /// It used to require the landing dose to EQUAL the journal, and it was
    /// green the whole time the handle was making things harder. A neighbour
    /// variation can be per-side: hinge 4 → 3 is a two-legged 3×15 becoming a
    /// two-sided 3×15, and the journal answered "15" to both — 45 reps became
    /// 90. Pressing "make it easier" doubled the work, on 49 boundaries out of
    /// 49 by the audit's count.
    ///
    /// So the journal is a CEILING now, and the property the handle exists for
    /// is asserted in its own right: the work must not go up. The number the
    /// old line pinned is the ceiling assert below; the number it should have
    /// pinned is the one after it.
    func testTheEasierHandleLandsInTheJournalAndNeverHeavier() throws {
        /// Every set's dose, both sides counted — the same measure §41.1's gate
        /// uses. Safe as a uniform product here because `sub` and `cut` are
        /// asserted zero on both sides of the handle.
        func work(_ p: Pattern, _ v: Int, sets: Int, dose: Int) -> Int {
            sets * dose * Library.sides(p, v)
        }
        for variation in 2...deepestVariation {
            let store = try advancedStore(variation: variation)
            for ex in store.nextSession.exercises where store.canMakeEasier(ex.pattern) {
                let p = ex.pattern
                let target = ex.variation - 1
                let journal = store.engineState.shownDose(p, variation: target)
                    ?? Dose.grid(Library.unit(p, target)).min

                let easier = Engine.easierVariation(state: store.engineState, pattern: p)
                let landed = try XCTUnwrap(easier.doses[p])

                XCTAssertEqual(easier.vars[p], target,
                               "variation \(variation) \(p): the variation must drop")
                XCTAssertEqual(easier.sets[p] ?? EngineConfig.setsBase, EngineConfig.setsBase,
                               "variation \(variation) \(p): the landing is on the base band")
                XCTAssertEqual(easier.sub[p] ?? 0, 0)
                XCTAssertEqual(easier.cutOf(p), 0)
                XCTAssertLessThanOrEqual(landed, journal,
                                         "variation \(variation) \(p): the journal is the ceiling")

                let before = (ex.loads ?? Array(repeating: ex.load, count: ex.sets))
                    .reduce(0, +) * Library.sides(p, ex.variation)
                let after = work(p, target, sets: EngineConfig.setsBase, dose: landed)
                XCTAssertLessThanOrEqual(after, before,
                                         "variation \(variation) \(p): easier must be easier")
            }
        }
    }
}
